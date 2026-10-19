package com.sohr.delivery

import android.util.Log
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/**
 * Sees every push before Flutter does, purely so a new order can be drawn
 * without waking a Flutter engine first.
 *
 * `super.onMessageReceived` is always called, so the existing Dart handlers —
 * `onMessage`, `onBackgroundMessage`, the notification the background isolate
 * posts — behave exactly as before. This adds a path; it replaces nothing.
 *
 * Declared in AndroidManifest.xml with the MESSAGING_EVENT filter, which
 * supersedes the plugin's own service registration. Because this class extends
 * that service, superseding it costs nothing.
 */
class SohrMessagingService : FlutterFirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        val data = remoteMessage.data
        Log.d(TAG, "[FCM] MESSAGE RECEIVED (native)")
        Log.d(TAG, "[FCM] messageId = ${remoteMessage.messageId}")
        Log.d(TAG, "[FCM] data = $data")

        // ONE alert per order, decided here.
        //
        // Returning early is not enough to stop Flutter posting its own: the
        // plugin's FlutterFirebaseMessagingReceiver listens for
        // `c2dm.intent.RECEIVE` and starts the Dart background isolate itself,
        // with no route through this service at all. That is why the
        // notification kept landing on top of the card. Dart no longer posts
        // anything for a new order — the card, or the fallback below, and never
        // both.
        //
        // Foreground is excluded deliberately: the in-app alert owns that case,
        // and floating a second copy over our own screen helps nobody.
        if (data["type"] == "new_order" && !AppForeground.isForeground) {
            Log.d(TAG, "[NEW_ORDER] type = new_order")
            if (NewOrderOverlay.show(applicationContext, data)) {
                Log.d(TAG, "[NEW_ORDER] overlay owns this one — no notification")
            } else {
                Log.d(TAG, "[NEW_ORDER] overlay unavailable — posting the fallback")
                NewOrderNotifier.post(applicationContext, data)
            }
        }

        // Everything else, and every case the overlay declined, behaves exactly
        // as before.
        super.onMessageReceived(remoteMessage)

        when (data["type"]) {
            // Claimed by another partner, or withdrawn. Takes the card down
            // wherever it is — this is the only path that can reach a partner
            // whose app is closed, so it is what stops the ringtone.
            "order_taken", "order_cancelled" -> {
                val orderId = listOf("orderMongoId", "orderId", "_id")
                    .firstNotNullOfOrNull { data[it]?.takeIf(String::isNotBlank) }
                Log.d(TAG, "[NEW_ORDER] withdrawn: $orderId (${data["type"]})")
                if (orderId != null) {
                    NewOrderOverlay.dismissFor(orderId)
                    NewOrderNotifier.cancel(applicationContext, orderId)
                }
            }
        }
    }

    companion object {
        private const val TAG = "SohrMessaging"
    }
}
