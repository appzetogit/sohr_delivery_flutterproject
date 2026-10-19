package com.sohr.delivery

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.ActivityInfo
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.graphics.BitmapFactory
import android.graphics.PixelFormat
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.CountDownTimer
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * The incoming-order card, drawn directly by the window manager.
 *
 * Everything here runs in the app's own process off the FCM `RemoteMessage`, so
 * there is no Flutter engine, no background isolate and no cross-isolate handoff
 * involved in getting the order onto the screen. That handoff is what failed
 * repeatedly on device ("key empty after 30 reads, 0 direct messages") and this
 * exists to remove it rather than keep debugging it.
 *
 * An overlay rather than a custom notification because Android caps notification
 * layouts at roughly 256dp and this card is about 450dp; a RemoteViews version
 * would be clipped.
 */
object NewOrderOverlay {
    private const val TAG = "NewOrderOverlay"

    /** Matches the Dart-side default; the server's own window overrides it. */
    private const val DEFAULT_WINDOW_SECONDS = 20L

    /** Resolution of the countdown ring. 1000 steps is finer than a pixel of
     *  arc on a 62dp badge, so the sweep reads as continuous. */
    private const val RING_STEPS = 1000

    /** ~25fps. Fast enough that the ring glides, slow enough to be free. */
    private const val RING_TICK_MS = 40L

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newCachedThreadPool()

    private var view: View? = null
    private var windowManager: WindowManager? = null
    private var timer: CountDownTimer? = null
    private var player: MediaPlayer? = null
    private var alarmWatchdog: Runnable? = null

    /// The order the Directions call has already been made for.
    private var routedOrderId: String? = null

    /**
     * The order currently on screen.
     *
     * The de-duplication key for the whole feature: the same order arriving
     * again — a re-offer round, a duplicate push, both transports firing —
     * refreshes the card in place instead of stacking a second window or
     * restarting the ringtone.
     */
    private var showingOrderId: String? = null

    fun canDrawOverlay(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

    /**
     * Returns whether the card will be on screen.
     *
     * The caller uses this to decide whether Flutter should also post its
     * notification. Two alerts for one order is what made the screen look
     * messy — the notification was landing on top of the card.
     */
    @SuppressLint("InflateParams")
    fun show(context: Context, data: Map<String, String>): Boolean {
        val orderId = data.firstNonEmpty("orderMongoId", "_id", "orderId")
        if (orderId.isEmpty()) {
            Log.w(TAG, "[NEW_ORDER] push carries no order id — nothing to show")
            return false
        }
        if (!canDrawOverlay(context)) {
            Log.w(TAG, "[NEW_ORDER] 'Display over other apps' not granted — skipping overlay")
            return false
        }

        main.post {
            try {
                if (showingOrderId == orderId && view != null) {
                    Log.d(TAG, "[NEW_ORDER] $orderId already on screen — refreshing in place")
                    view?.let { bind(context, it, data, orderId) }
                    return@post
                }
                dismissInternal()
                showingOrderId = orderId

                val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
                val card = LayoutInflater.from(context).inflate(R.layout.overlay_new_order, null)
                bind(context, card, data, orderId)

                wm.addView(card, layoutParams())
                windowManager = wm
                view = card

                startAlarm(context, data.remainingSeconds())
                startCountdown(context, data)
                // The server posts its own tray copy for ROMs where this never
                // runs. Ours is up, so that one goes — otherwise it sits on top
                // of the card.
                NewOrderNotifier.cancel(context, orderId)
                Log.d(TAG, "[NEW_ORDER_NOTIFICATION] overlay shown for $orderId")
            } catch (e: Exception) {
                // A window that fails to attach must not take the process with
                // it. The caller has already let Flutter post its notification
                // as the fallback, so the partner is still told.
                Log.e(TAG, "[NEW_ORDER] overlay failed: $e")
                showingOrderId = null
            }
        }
        return true
    }

    /** Called when the order is claimed, cancelled or otherwise withdrawn. */
    fun dismissFor(orderId: String) = main.post {
        if (showingOrderId == null || showingOrderId == orderId) dismissInternal()
    }

    fun dismiss() = main.post { dismissInternal() }

    // ------------------------------------------------------------------ bind

    private fun bind(context: Context, root: View, data: Map<String, String>, orderId: String) {
        val display = data.firstNonEmpty("orderDisplayId", "orderNumber")
            .ifEmpty { "#" + orderId.takeLast(6).uppercase() }
        // First non-ZERO, not first present: the push carries riderEarning=0
        // next to earnings=50 for the same order, and "₹0" on a ₹50 job is the
        // difference between accepting and declining.
        val earning = data.firstNonZero("riderEarning", "earnings", "price")

        // Which brand the pickup is for — the rider decides differently for a
        // restaurant order than a mart run, so it leads the card.
        val source = when (data["vertical"]) {
            "quick" -> "HiberMart"
            "food" -> "Sohr Food"
            else -> null
        }

        // FOOD vs MART, as the first thing the eye lands on. Colour AND emoji
        // differ, so the two are told apart at a glance rather than read.
        root.html(
            R.id.headline,
            buildString {
                if (source != null) {
                    append("Order from <b>").append(source).append("</b> • ").append(display)
                } else {
                    append("Order ").append(display)
                }
                if (earning.isNotEmpty()) {
                    append(" • <font color='#1E8E3E'><b>₹").append(earning)
                        .append("</b></font> earning")
                }
            },
        )

        root.text(R.id.pickup_name, data.firstNonEmpty("restaurantName", "storeName").ifEmpty { "Store" })
        root.text(R.id.pickup_address, data.firstNonEmpty("restaurantAddress", "pickupAddress"))
        root.text(R.id.pickup_distance, data.firstNonEmpty("pickupDistanceKm").km())

        root.text(R.id.drop_name, data.firstNonEmpty("customerName").ifEmpty { "Customer" })
        root.text(R.id.drop_address, data.firstNonEmpty("customerAddress", "dropAddress"))
        // Left to bindTripFigures, which has the routed leg rather than the
        // zero the push carries.

        val itemCount = data.firstNonEmpty("itemsCount", "itemCount", "totalItems")
        val itemsN = itemCount.toIntOrNull() ?: 0
        root.text(
            R.id.items_count,
            if (itemCount.isEmpty()) "—" else "$itemCount ${if (itemsN == 1) "item" else "items"}",
        )

        // Cash vs prepaid decides whether money is collected at the door, so it
        // carries a word and a colour rather than a colour alone. The *amount*
        // deliberately isn't here — see the collection note below.
        val cash = data.firstNonEmpty("paymentMethod").lowercase().let {
            it == "cash" || it == "cod" || it == "razorpay_qr"
        }
        root.findViewById<TextView>(R.id.payment_chip)?.apply {
            text = if (cash) "Cash" else "Prepaid"
            setTextColor(if (cash) 0xFFD97706.toInt() else 0xFF1E8E3E.toInt())
        }

        root.text(R.id.earning, if (earning.isEmpty()) "—" else "₹$earning")

        // Base pay and incentive are optional — the push does not carry them
        // yet, and an empty "Base Pay: ₹" line reads as a bug.
        val basePay = data.firstNonEmpty("basePay", "baseEarning")
        val incentive = data.firstNonEmpty("incentive", "surge")
        root.findViewById<TextView>(R.id.earning_breakdown)?.apply {
            val parts = listOfNotNull(
                basePay.takeIf { it.isNotEmpty() }?.let { "Base Pay: ₹$it" },
                incentive.takeIf { it.isNotEmpty() }?.let { "Incentive: ₹$it" },
            )
            if (parts.isEmpty()) {
                visibility = View.GONE
            } else {
                text = parts.joinToString("  •  ")
                visibility = View.VISIBLE
            }
        }

        // No order value and no "collect ₹X" on this card on purpose: the only
        // figure a rider needs to decide on an offer is their own earning, and
        // two large amounts side by side had them reading the customer's total
        // as theirs. The collection amount still shows on the trip screen,
        // where it is actually needed.

        bindTripFigures(context, root, data, orderId)

        bindThumbnails(root, data["items"], itemCount.toIntOrNull() ?: 0)
        bindRouteMap(root, data)
        bindRider(root)

        root.findViewById<View>(R.id.btn_accept)?.setOnClickListener {
            Log.d(TAG, "[NEW_ORDER_NOTIFICATION] ACCEPT tapped for $orderId")
            stopAlarm()
            // The app owns the accept: it holds the auth token in encrypted
            // storage that this process cannot read, and the partner needs the
            // trip screen next anyway.
            openApp(context, orderId, autoAccept = true)
            dismissInternal()
        }
        root.findViewById<View>(R.id.btn_reject)?.setOnClickListener {
            Log.d(TAG, "[NEW_ORDER_NOTIFICATION] REJECT tapped for $orderId")
            stopAlarm()
            // Queued rather than sent from here, for the same token reason. The
            // app flushes it on next launch; the server's own dispatch timeout
            // re-offers the order regardless, so nothing is stranded.
            queueRejection(context, orderId)
            dismissInternal()
        }
        root.findViewById<View>(R.id.overlay_root)?.setOnClickListener {
            stopAlarm()
            openApp(context, orderId, autoAccept = false)
            dismissInternal()
        }
    }

    /**
     * The real distance and time for this trip: rider → store → customer.
     *
     * Computed here rather than read off the push, because the push sends
     * `tripDistanceKm=0` and `tripDurationMins=0` — which is what left both
     * chips showing a dash. Push values are still preferred when they are
     * actually populated, so this costs nothing once the backend fills them in.
     *
     * Falls back in order: Directions API → straight-line estimate from the
     * coordinates → a dash only when there are no coordinates at all.
     */
    private fun bindTripFigures(
        context: Context,
        root: View,
        data: Map<String, String>,
        orderId: String,
    ) {
        val pushKm = data.firstNonEmpty("tripDistanceKm", "distance").toDoubleOrNull() ?: 0.0
        val pushMins = data.firstNonEmpty("tripDurationMins").toDoubleOrNull() ?: 0.0
        if (pushKm > 0 && pushMins > 0) {
            applyTripFigures(root, pushKm, pushMins, exact = true)
            return
        }

        val pickup = data.latLng("pickupLat", "pickupLng")
        val drop = data.latLng("dropLat", "dropLng")
        if (pickup == null || drop == null) {
            applyTripFigures(root, 0.0, 0.0, exact = false)
            return
        }

        // Loading state, so the chips never sit on a dash while work is in
        // flight: the partner can see it is coming rather than broken.
        setChip(root, R.id.map_chip_distance, "…", "Total Distance")
        setChip(root, R.id.map_chip_eta, "…", "Est. Delivery Time")

        // The second push for the same order must not re-run this.
        if (routedOrderId == orderId) return
        routedOrderId = orderId

        val origin = lastKnownLatLng(context) ?: pickup
        io.execute {
            val route = fetchRoute(context, origin, pickup, drop)
            main.post {
                if (showingOrderId != orderId || !root.isAttachedToWindow) return@post
                if (route != null) {
                    applyTripFigures(root, route.km, route.mins, exact = true)
                    route.polyline?.let { bindRouteMap(root, data, it) }
                } else {
                    // A straight line is a floor, not a guess — the road
                    // distance is always at least this, so an approximate
                    // number beats a dash that says nothing at all.
                    val km = (haversineKm(origin, pickup) + haversineKm(pickup, drop))
                    applyTripFigures(root, km, km / 20.0 * 60 + 5, exact = false)
                }
            }
        }
    }

    private fun setChip(root: View, id: Int, value: String, label: String) {
        root.html(id, "<b>$value</b><br/><font color='#6B7280'>$label</font>")
    }

    private fun applyTripFigures(root: View, km: Double, mins: Double, exact: Boolean) {
        // "~" marks an estimate. A partner deciding in twenty seconds should be
        // able to tell a measured number from a derived one.
        val prefix = if (exact) "" else "~"
        val kmLabel = if (km <= 0) "—" else prefix + formatKm(km)
        val etaLabel = if (mins <= 0) {
            "—"
        } else {
            val m = mins.toInt().coerceAtLeast(1)
            "$prefix$m–${m + 5} mins"
        }
        setChip(root, R.id.map_chip_distance, kmLabel, "Total Distance")
        setChip(root, R.id.map_chip_eta, etaLabel, "Est. Delivery Time")
        root.text(R.id.drop_distance, kmLabel)
    }

    private data class TripRoute(val km: Double, val mins: Double, val polyline: String?)

    /**
     * Rider → store → customer in a single Directions call, so the numbers and
     * the line on the map come from the same route.
     *
     * Needs "Directions API" enabled on the same key the app already uses for
     * maps. If it is not, this returns null and the caller estimates instead of
     * showing nothing.
     */
    private fun fetchRoute(
        context: Context,
        origin: LatLngLite,
        pickup: LatLngLite,
        drop: LatLngLite,
    ): TripRoute? {
        val key = mapsApiKey(context)
        if (key.isNullOrBlank()) return null
        val url = "https://maps.googleapis.com/maps/api/directions/json" +
            "?origin=" + origin.lat + "," + origin.lng +
            "&destination=" + drop.lat + "," + drop.lng +
            "&waypoints=" + pickup.lat + "," + pickup.lng +
            "&mode=driving&key=" + key
        return try {
            val body = (URL(url).openConnection() as HttpURLConnection).run {
                connectTimeout = 5000
                readTimeout = 5000
                inputStream.bufferedReader().use { it.readText() }
            }
            val json = JSONObject(body)
            val status = json.optString("status")
            if (status != "OK") {
                Log.w(TAG, "[NEW_ORDER] directions returned $status — estimating instead")
                return null
            }
            val route = json.getJSONArray("routes").getJSONObject(0)
            val legs = route.getJSONArray("legs")
            var metres = 0.0
            var seconds = 0.0
            for (i in 0 until legs.length()) {
                val leg = legs.getJSONObject(i)
                metres += leg.getJSONObject("distance").optDouble("value", 0.0)
                seconds += leg.getJSONObject("duration").optDouble("value", 0.0)
            }
            Log.d(TAG, "[NEW_ORDER] routed ${metres / 1000}km in ${seconds / 60}min")
            TripRoute(
                metres / 1000.0,
                seconds / 60.0,
                route.optJSONObject("overview_polyline")
                    ?.optString("points")
                    ?.takeIf { it.isNotBlank() },
            )
        } catch (e: Exception) {
            Log.w(TAG, "[NEW_ORDER] directions failed: $e")
            null
        }
    }

    /** Last fix the OS already has. Never requests one — this must not block. */
    private fun lastKnownLatLng(context: Context): LatLngLite? {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION)
            != PackageManager.PERMISSION_GRANTED
        ) {
            return null
        }
        return try {
            val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
                .mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }
                .maxByOrNull { it.time }
                ?.let { LatLngLite(it.latitude, it.longitude) }
        } catch (e: Exception) {
            Log.w(TAG, "no last known location: $e")
            null
        }
    }

    /**
     * A Google static-map tile of the pickup → drop leg.
     *
     * The push already carries `pickupLat/Lng` and `dropLat/Lng`, so this needs
     * no API call of its own beyond fetching the image. The line is drawn
     * straight between the two points, not along the road: the push has no
     * encoded polyline, and inventing a route would be a lie about the distance.
     *
     * Needs "Maps Static API" enabled on the same key the app already uses for
     * maps. If it is not, the request 403s, the tile stays hidden, and the rest
     * of the card is unaffected.
     */
    private fun bindRouteMap(root: View, data: Map<String, String>, encodedRoute: String? = null) {
        val view = root.findViewById<ImageView>(R.id.route_map) ?: return
        val container = root.findViewById<View>(R.id.map_container) ?: return
        container.visibility = View.GONE

        val pLat = data["pickupLat"]?.toDoubleOrNull()
        val pLng = data["pickupLng"]?.toDoubleOrNull()
        val dLat = data["dropLat"]?.toDoubleOrNull()
        val dLng = data["dropLng"]?.toDoubleOrNull()
        if (pLat == null || pLng == null || dLat == null || dLng == null) {
            Log.d(TAG, "[NEW_ORDER] no coordinates on the push — map hidden")
            return
        }

        val key = mapsApiKey(root.context)
        if (key.isNullOrBlank()) {
            Log.w(TAG, "[NEW_ORDER] no maps API key in the manifest — map hidden")
            return
        }

        val url = buildString {
            append("https://maps.googleapis.com/maps/api/staticmap")
            append("?size=640x300&scale=2")
            append("&markers=").append("color:0xC4801C%7Clabel:S%7C").append(pLat).append(",").append(pLng)
            append("&markers=").append("color:0x1E8E3E%7Clabel:C%7C").append(dLat).append(",").append(dLng)
            // The routed line when Directions gave us one, so the tile shows
            // the roads the numbers were measured along. Straight store-to-door
            // otherwise, which is honest about knowing no better.
            append("&path=").append("color:0x1E8E3Eff%7Cweight:4%7C")
            if (encodedRoute != null) {
                append("enc:").append(java.net.URLEncoder.encode(encodedRoute, "UTF-8"))
            } else {
                append(pLat).append(",").append(pLng).append("%7C")
                    .append(dLat).append(",").append(dLng)
            }
            append("&key=").append(key)
        }

        io.execute {
            val bitmap = try {
                (URL(url).openConnection() as HttpURLConnection).run {
                    connectTimeout = 4000
                    readTimeout = 4000
                    inputStream.use { BitmapFactory.decodeStream(it) }
                }
            } catch (e: Exception) {
                Log.w(TAG, "[NEW_ORDER] static map failed: $e")
                null
            }
            if (bitmap != null) {
                main.post {
                    view.setImageBitmap(bitmap)
                    container.visibility = View.VISIBLE
                }
            }
        }
    }

    /**
     * The scooter illustration in the header.
     *
     * Resolved by name at runtime so the artwork is a drop-in: put
     * `rider_scooter.png` in `res/drawable/` and it appears, with no code
     * change. Hidden while that file is absent rather than showing a gap.
     */
    private fun bindRider(root: View) {
        val view = root.findViewById<ImageView>(R.id.rider_art) ?: return
        val id = root.context.resources.getIdentifier(
            "rider_scooter", "drawable", root.context.packageName
        )
        if (id != 0) {
            view.setImageResource(id)
            view.visibility = View.VISIBLE
        } else {
            view.visibility = View.GONE
        }
    }

    private fun mapsApiKey(context: Context): String? = try {
        context.packageManager
            .getApplicationInfo(context.packageName, PackageManager.GET_META_DATA)
            .metaData?.getString("com.google.android.geo.API_KEY")
    } catch (e: Exception) {
        null
    }

    /**
     * Product thumbnails, loaded off the main thread.
     *
     * Silently degrades to the count alone: the backend does not send `items`
     * yet, and a picture is decoration on a card whose job is to be answered in
     * twenty seconds.
     */
    private fun bindThumbnails(root: View, itemsJson: String?, totalCount: Int) {
        val strip = root.findViewById<LinearLayout>(R.id.thumbnails) ?: return
        strip.removeAllViews()
        if (itemsJson.isNullOrBlank()) return

        val urls = try {
            val array = JSONArray(itemsJson)
            (0 until array.length())
                .mapNotNull { array.optJSONObject(it)?.optString("image") }
                .filter { it.isNotBlank() }
        } catch (e: Exception) {
            Log.w(TAG, "[NEW_ORDER] items payload unreadable: $e")
            return
        }

        val context = root.context
        val size = (38 * context.resources.displayMetrics.density).toInt()
        val gap = (6 * context.resources.displayMetrics.density).toInt()

        urls.take(3).forEach { url ->
            val image = ImageView(context).apply {
                layoutParams = LinearLayout.LayoutParams(size, size)
                    .also { it.marginEnd = gap }
                setBackgroundResource(R.drawable.bg_overlay_thumb)
                scaleType = ImageView.ScaleType.CENTER_CROP
                clipToOutline = true
            }
            strip.addView(image)
            io.execute {
                val bitmap = try {
                    (URL(url).openConnection() as HttpURLConnection).run {
                        connectTimeout = 4000
                        readTimeout = 4000
                        inputStream.use { BitmapFactory.decodeStream(it) }
                    }
                } catch (_: Exception) {
                    null
                }
                if (bitmap != null) main.post { image.setImageBitmap(bitmap) }
            }
        }

        val remaining = totalCount - minOf(urls.size, 3)
        if (remaining > 0) {
            strip.addView(TextView(context).apply {
                layoutParams = LinearLayout.LayoutParams(size, size)
                setBackgroundResource(R.drawable.bg_overlay_thumb)
                gravity = Gravity.CENTER
                text = "+$remaining"
                textSize = 13f
                setTextColor(0xFF181C2E.toInt())
            })
        }
    }

    // -------------------------------------------------------------- lifecycle

    private fun layoutParams(): WindowManager.LayoutParams {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        return WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            // NOT_FOCUSABLE keeps the keyboard and the app underneath usable;
            // the card still receives its own taps. WRAP_CONTENT above means
            // the window is exactly as tall as the card, so everything below it
            // belongs to whatever app the partner was already using.
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP
            y = 0
            // The card is laid out for a tall viewport like the rest of the
            // app. This window is not an Activity, so the manifest's portrait
            // lock does not reach it — without this it would follow whatever
            // orientation the app underneath happens to be in.
            screenOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
    }

    private fun startCountdown(context: Context, data: Map<String, String>) {
        val seconds = data.remainingSeconds()
        val totalMs = seconds * 1000
        val countdown = view?.findViewById<TextView>(R.id.countdown)
        val ring = view?.findViewById<CountdownRing>(R.id.countdown_ring)
        ring?.start(totalMs)

        var lastSecondShown = -1
        timer?.cancel()
        timer = object : CountDownTimer(totalMs, 1000L) {
            override fun onTick(msLeft: Long) {
                val left = (msLeft / 1000).toInt()
                if (left == lastSecondShown) return
                lastSecondShown = left
                val colour = if (left <= seconds * 0.3) "#E04444" else "#1E8E3E"
                countdown?.setHtml(
                    "🕐  Accept within <font color='$colour'><b>$left</b></font> sec"
                )
            }

            override fun onFinish() {
                ring?.stop()
                countdown?.setHtml("🕐  <font color='#E04444'><b>Expired</b></font>")
                Log.d(TAG, "[NEW_ORDER] offer expired on screen")
                stopAlarm()
                dismissInternal()
            }
        }.start()
    }

    /** Server-driven, exactly as the in-app card is. */
    private fun Map<String, String>.remainingSeconds(): Long {
        this["acceptanceDeadlineAt"]?.takeIf { it.isNotBlank() }?.let { raw ->
            runCatching {
                val deadline = java.time.Instant.parse(raw).toEpochMilli()
                val left = (deadline - System.currentTimeMillis()) / 1000
                // A push held in Doze arrives already past its deadline; opening
                // the card at zero is worse than opening it short.
                if (left > 0) return left
            }
        }
        this["acceptTimeoutSeconds"]?.toLongOrNull()?.takeIf { it > 0 }?.let { return it }
        return DEFAULT_WINDOW_SECONDS
    }

    private fun startAlarm(context: Context, windowSeconds: Long) {
        stopAlarm()
        try {
            // Attributes passed to create(), not set afterwards: create() already
            // prepares the player, and setAudioAttributes is ignored after
            // prepare — so the alarm-stream routing was silently not applied.
            val attributes = AudioAttributes.Builder()
                // Alarm usage, so it is audible with media volume down — the
                // normal state for someone riding with the phone mounted.
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            player = MediaPlayer.create(
                context,
                R.raw.neworder_ring,
                attributes,
                AudioManager.AUDIO_SESSION_ID_GENERATE,
            )?.apply {
                // A player that errors mid-loop would otherwise sit there
                // holding audio focus with nothing able to stop it.
                setOnErrorListener { _, what, extra ->
                    Log.w(TAG, "ringtone error $what/$extra — releasing")
                    stopAlarm()
                    true
                }
                isLooping = true
                start()
            }
            Log.d(TAG, "[NEW_ORDER] ringtone started")
        } catch (e: Exception) {
            Log.w(TAG, "ringtone failed: $e")
        }

        // Backstop. Every exit path already stops the alarm; this bounds it if
        // one is ever missed, because a ringtone that outlives its order is
        // worse than a missed order. Generous enough never to cut a live offer
        // short.
        alarmWatchdog?.let { main.removeCallbacks(it) }
        alarmWatchdog = main.postDelayedCompat((windowSeconds + 10) * 1000) {
            if (player != null) {
                Log.w(TAG, "[NEW_ORDER] alarm watchdog fired — forcing silence")
                stopAlarm()
            }
        }

        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            // A bounded pattern, repeated a fixed number of times rather than
            // forever — a phone that will not stop buzzing is worse than a
            // missed order.
            val pattern = longArrayOf(0, 400, 300, 400, 900, 400, 300, 400)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(pattern, -1)
            }
        } catch (e: Exception) {
            Log.w(TAG, "vibration failed: $e")
        }
    }

    /**
     * Silences the ringtone. Safe to call any number of times, from any state.
     *
     * The field is cleared FIRST, and only then is the local reference stopped.
     * It used to be the other way round, inside a swallowing try/catch: if
     * `isPlaying` or `stop()` threw — which a MediaPlayer in an error state does
     * — `release()` never ran, and the very next line dropped the only
     * reference to a still-looping player. Nothing could reach it again and it
     * rang until the process died. That is the "plays indefinitely" bug.
     *
     * `release()` stops playback on its own, so it is the call that actually
     * matters and it gets its own try.
     */
    private fun stopAlarm() {
        alarmWatchdog?.let { main.removeCallbacks(it) }
        alarmWatchdog = null

        val current = player ?: return
        player = null
        try {
            current.stop()
        } catch (e: Exception) {
            Log.w(TAG, "ringtone stop failed, releasing anyway: $e")
        }
        try {
            current.release()
        } catch (e: Exception) {
            Log.w(TAG, "ringtone release failed: $e")
        }
        Log.d(TAG, "[NEW_ORDER] ringtone stopped")
    }

    private fun dismissInternal() {
        timer?.cancel()
        timer = null
        stopAlarm()
        val current = view
        val wm = windowManager
        view = null
        windowManager = null
        showingOrderId = null
        if (current != null && wm != null) {
            try {
                wm.removeView(current)
            } catch (_: Exception) {
                // Already detached — nothing to undo.
            }
        }
    }

    // ------------------------------------------------------------- app handoff

    /**
     * Opens the app on the order the partner just answered.
     *
     * An EXPLICIT intent, not `getLaunchIntentForPackage`. That returns a bare
     * ACTION_MAIN/CATEGORY_LAUNCHER intent, and when the task already exists
     * Android treats it as "resume this task" and **never delivers the extras**
     * — so `consumeLaunchOrder` found nothing, the accept never ran, and the
     * socket re-raised the card, ringing, with nothing left to resolve it. That
     * is the "still ringing after Accept" report, and the "asks me to accept
     * again" one: both are this single line.
     *
     * CLEAR_TOP + SINGLE_TOP against an explicit component guarantees the
     * running activity receives it through onNewIntent.
     */
    private fun openApp(context: Context, orderId: String, autoAccept: Boolean) {
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
            putExtra(EXTRA_ORDER_ID, orderId)
            putExtra(EXTRA_AUTO_ACCEPT, autoAccept)
        }
        context.startActivity(intent)
    }

    /**
     * Rejections the app has not reported to the server yet.
     *
     * Plain preferences on purpose: an order id is not a credential, and this
     * process cannot read the encrypted store the auth token lives in.
     */
    private fun queueRejection(context: Context, orderId: String) {
        val prefs = context.getSharedPreferences(REJECT_PREFS, Context.MODE_PRIVATE)
        val queued = prefs.getStringSet(REJECT_KEY, emptySet())!!.toMutableSet()
        queued.add(orderId)
        prefs.edit().putStringSet(REJECT_KEY, queued).apply()
    }

    const val EXTRA_ORDER_ID = "appzeto.newOrderId"
    const val EXTRA_AUTO_ACCEPT = "appzeto.autoAccept"
    const val REJECT_PREFS = "appzeto_overlay"
    const val REJECT_KEY = "pending_rejections"
}

/** Post-delayed that hands back the Runnable, so it can be cancelled. */
private fun Handler.postDelayedCompat(delayMs: Long, action: () -> Unit): Runnable {
    val runnable = Runnable { action() }
    postDelayed(runnable, delayMs)
    return runnable
}

private fun View.text(id: Int, value: String) {
    findViewById<TextView>(id)?.text = value
}

/** Small spans — a coloured number, a bolded name — without a SpannableBuilder. */
private fun View.html(id: Int, value: String) {
    findViewById<TextView>(id)?.setHtml(value)
}

private fun TextView.setHtml(value: String) {
    text = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
        android.text.Html.fromHtml(value, android.text.Html.FROM_HTML_MODE_LEGACY)
    } else {
        @Suppress("DEPRECATION")
        android.text.Html.fromHtml(value)
    }
}

private fun Map<String, String>.firstNonEmpty(vararg keys: String): String {
    for (key in keys) {
        val value = this[key]?.trim()
        if (!value.isNullOrEmpty()) return value
    }
    return ""
}

/** Like [firstNonEmpty] but also skips values that parse to zero. */
private fun Map<String, String>.firstNonZero(vararg keys: String): String {
    for (key in keys) {
        val value = this[key]?.trim() ?: continue
        if (value.isNotEmpty() && (value.toDoubleOrNull() ?: 0.0) > 0.0) return value
    }
    return ""
}

/** A plain lat/lng pair; the Maps SDK type is not available in this process. */
data class LatLngLite(val lat: Double, val lng: Double)

private fun Map<String, String>.latLng(latKey: String, lngKey: String): LatLngLite? {
    val lat = this[latKey]?.toDoubleOrNull() ?: return null
    val lng = this[lngKey]?.toDoubleOrNull() ?: return null
    return LatLngLite(lat, lng)
}

/** Straight-line kilometres, used only when the routing call is unavailable. */
private fun haversineKm(a: LatLngLite, b: LatLngLite): Double {
    val toRad = Math.PI / 180
    val dLat = (b.lat - a.lat) * toRad
    val dLng = (b.lng - a.lng) * toRad
    val h = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(a.lat * toRad) * Math.cos(b.lat * toRad) *
        Math.sin(dLng / 2) * Math.sin(dLng / 2)
    return 6371.0 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h))
}

/** Sub-100m reads as metres: "0.0 km" looks like missing data, not a short hop. */
private fun formatKm(km: Double): String =
    if (km < 0.1) "${(km * 1000).toInt()} m" else String.format("%.1f km", km)

private fun String.km(): String {
    val value = toDoubleOrNull() ?: return "—"
    // A 6-metre walk to the store rendered as "0.0 km", which reads as missing
    // data rather than "you are already there".
    return if (value <= 0.0) "—" else formatKm(value)
}
