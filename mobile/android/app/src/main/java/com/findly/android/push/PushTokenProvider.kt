package com.findly.android.push

/** Fired when the FCM registration token changes (specs/003-android-client.md §9). */
fun interface PushTokenRefreshListener {
    fun onNewToken(token: String)
}

/**
 * Abstraction over the FCM push-token source (specs/003-android-client.md §9). Distinct from
 * `auth/AuthProvider`'s Firebase Auth **ID token** — see specs/003 §7 for why the two are
 * separate mechanisms (one triggers a request retry, the other triggers a device
 * re-registration). [RealPushTokenProvider] is the real, A9 implementation — wraps
 * `FirebaseMessaging.getInstance()`, paired with [FindlyMessagingService]'s
 * `onNewToken` override (specs/009-device-runtime.md §5.5). The A1-era stub this replaced never
 * emitted a token at all (no real FCM SDK wired yet at the time).
 */
interface PushTokenProvider {
    suspend fun currentToken(): String?
    fun addRefreshListener(listener: PushTokenRefreshListener)
}
