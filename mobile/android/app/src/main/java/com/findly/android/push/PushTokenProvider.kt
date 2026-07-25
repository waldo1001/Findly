package com.findly.android.push

/** Fired when the FCM registration token changes (specs/003-android-client.md §9). */
fun interface PushTokenRefreshListener {
    fun onNewToken(token: String)
}

/**
 * Abstraction over the FCM push-token source (specs/003-android-client.md §9). Distinct from
 * `auth/AuthProvider`'s Firebase Auth **ID token** — see specs/003 §7 for why the two are
 * separate mechanisms (one triggers a request retry, the other triggers a device
 * re-registration). The real implementation (H1/A2) wraps
 * `FirebaseMessaging.getInstance()` + a `FirebaseMessagingService.onNewToken` override;
 * [StubPushTokenProvider] is the A1 implementation — no real FCM SDK is wired
 * (`google-services.json` is absent, per the Mobile H1-waiver).
 */
interface PushTokenProvider {
    suspend fun currentToken(): String?
    fun addRefreshListener(listener: PushTokenRefreshListener)
}
