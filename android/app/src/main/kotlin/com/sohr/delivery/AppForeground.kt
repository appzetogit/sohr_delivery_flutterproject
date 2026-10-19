package com.sohr.delivery

/**
 * Whether the partner is currently looking at the app.
 *
 * Set from MainActivity's resume/pause. The FCM service reads it to decide who
 * owns a new order: the in-app alert when the app is in front, the floating
 * overlay when it is not. Without it both would fire and the partner would see
 * the same offer twice.
 */
object AppForeground {
    @Volatile
    var isForeground: Boolean = false
}
