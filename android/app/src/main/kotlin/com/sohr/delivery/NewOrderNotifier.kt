package com.sohr.delivery

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * The fallback alert, for when the floating card cannot be shown.
 *
 * This lives in Kotlin rather than Dart because the alert needs exactly one
 * owner. It used to be posted by the Dart background handler, which the
 * firebase_messaging plugin starts from its OWN broadcast receiver
 * (`FlutterFirebaseMessagingReceiver` listens for `c2dm.intent.RECEIVE` and
 * enqueues the background isolate directly) — completely independently of the
 * messaging service. So no amount of returning early from the service could
 * stop it, and the notification kept landing on top of the card. Deciding here,
 * where the overlay's own outcome is known, is the only place the two cannot
 * both fire.
 */
object NewOrderNotifier {
    private const val TAG = "NewOrderNotifier"

    /**
     * Must match the id Dart creates and the backend addresses.
     *
     * Android freezes a channel's importance and sound at creation, so this can
     * only change alongside a new id on both sides.
     */
    const val CHANNEL_ID = "new_orders_v3"

    fun notificationId(orderId: String): Int = orderId.hashCode() and 0x7fffffff

    fun post(context: Context, data: Map<String, String>) {
        val orderId = data.firstNonEmptyValue("orderMongoId", "_id", "orderId")
        if (orderId.isEmpty()) {
            Log.w(TAG, "[NEW_ORDER_NOTIFICATION] no order id — nothing to post")
            return
        }

        val display = data.firstNonEmptyValue("orderDisplayId", "orderNumber")
            .ifEmpty { "#" + orderId.takeLast(6).uppercase() }
        // First non-zero — see NewOrderOverlay.bind for why.
        val earning = listOf("riderEarning", "earnings", "price")
            .mapNotNull { data[it]?.trim() }
            .firstOrNull { (it.toDoubleOrNull() ?: 0.0) > 0.0 } ?: ""
        val store = data.firstNonEmptyValue("restaurantName", "storeName")

        val body = buildString {
            append("Order ").append(display)
            if (earning.isNotEmpty()) append(" • ₹").append(earning).append(" earning")
            append("\nTap to view and accept the order.")
            if (store.isNotEmpty()) append("\n").append(store)
        }

        ensureChannel(context)

        // Prefer the server's ready-made title; derive from the vertical when
        // the push predates it, so the alert always names the brand it can.
        val title = data["title"]?.takeIf { it.isNotBlank() }
            ?: when (data["vertical"]) {
                "quick" -> "New order from HiberMart"
                "food" -> "New order from Sohr Food"
                else -> "🔔 New Order Received!"
            }

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body.lineSequence().first())
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setColor(0xFFC4801C.toInt())
            .setAutoCancel(true)
            .setFullScreenIntent(openIntent(context, orderId, autoAccept = false), true)
            .setContentIntent(openIntent(context, orderId, autoAccept = false))
            .addAction(0, "Accept", openIntent(context, orderId, autoAccept = true))
            .addAction(0, "Reject", rejectIntent(context, orderId))
            .build()

        try {
            NotificationManagerCompatSafe(context).notify(notificationId(orderId), notification)
            Log.d(TAG, "[NEW_ORDER_NOTIFICATION] posted fallback for $orderId")
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS refused on Android 13+. Nothing to recover.
            Log.w(TAG, "[NEW_ORDER_NOTIFICATION] not permitted: $e")
        }
    }

    fun cancel(context: Context, orderId: String) {
        try {
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(notificationId(orderId))
            // The copy FCM renders from the server's own notification block,
            // tagged `order_<id>` under id 0 — the tag is a contract with
            // order-dispatch.service.js.
            manager.cancel("order_$orderId", 0)
        } catch (e: Exception) {
            Log.w(TAG, "could not cancel notifications for $orderId: $e")
        }
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val ringtone = Uri.parse("android.resource://${context.packageName}/${R.raw.neworder_ring}")

        // A channel's sound is FIXED at creation — setSound() on an existing one
        // is ignored. Without this, changing the ringtone would only reach fresh
        // installs and every rider already running the app would keep the old
        // tone forever. Recreating resets the channel's user tweaks, which is
        // the lesser evil for an alert this critical.
        manager.getNotificationChannel(CHANNEL_ID)?.let { existing ->
            if (existing.sound == ringtone) return
            manager.deleteNotificationChannel(CHANNEL_ID)
            Log.d(TAG, "[NOTIFICATION_CHANNEL] recreating $CHANNEL_ID — ringtone changed")
        }

        val channel = NotificationChannel(
            CHANNEL_ID,
            "New Orders",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Incoming order offers that require immediate action"
            enableVibration(true)
            setSound(
                ringtone,
                AudioAttributes.Builder()
                    // Audible with media volume down — the normal state for
                    // someone riding with the phone mounted.
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
        }
        manager.createNotificationChannel(channel)
        Log.d(TAG, "[NOTIFICATION_CHANNEL] id = $CHANNEL_ID importance = HIGH")
    }

    private fun openIntent(context: Context, orderId: String, autoAccept: Boolean): PendingIntent {
        // Explicit component for the same reason as NewOrderOverlay.openApp: a
        // launcher intent against an existing task is delivered as a plain
        // resume, and the extras are dropped.
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
            putExtra(NewOrderOverlay.EXTRA_ORDER_ID, orderId)
            putExtra(NewOrderOverlay.EXTRA_AUTO_ACCEPT, autoAccept)
        }
        return PendingIntent.getActivity(
            context,
            notificationId(orderId) + if (autoAccept) 1 else 0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun rejectIntent(context: Context, orderId: String): PendingIntent {
        val intent = Intent(context, RejectOrderReceiver::class.java)
            .putExtra(NewOrderOverlay.EXTRA_ORDER_ID, orderId)
        return PendingIntent.getBroadcast(
            context,
            notificationId(orderId) + 2,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}

/**
 * Rejecting from the notification, without opening the app.
 *
 * The id is queued rather than sent: this process cannot read the encrypted
 * auth token, so the app reports it on next launch. The server's own dispatch
 * timeout re-offers the order regardless — this only makes it sooner.
 */
class RejectOrderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val orderId = intent.getStringExtra(NewOrderOverlay.EXTRA_ORDER_ID) ?: return
        context.getSharedPreferences(NewOrderOverlay.REJECT_PREFS, Context.MODE_PRIVATE)
            .let { prefs ->
                val queued = prefs.getStringSet(NewOrderOverlay.REJECT_KEY, emptySet())!!
                    .toMutableSet()
                queued.add(orderId)
                prefs.edit().putStringSet(NewOrderOverlay.REJECT_KEY, queued).apply()
            }
        NewOrderNotifier.cancel(context, orderId)
        NewOrderOverlay.dismissFor(orderId)
    }
}

/** Thin wrapper so the SecurityException on Android 13+ is caught in one place. */
private class NotificationManagerCompatSafe(private val context: Context) {
    fun notify(id: Int, notification: Notification) {
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(id, notification)
    }
}

private fun Map<String, String>.firstNonEmptyValue(vararg keys: String): String {
    for (key in keys) {
        val value = this[key]?.trim()
        if (!value.isNullOrEmpty()) return value
    }
    return ""
}
