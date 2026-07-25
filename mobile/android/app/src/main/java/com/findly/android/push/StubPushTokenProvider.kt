package com.findly.android.push

/**
 * A1 implementation of [PushTokenProvider] (specs/003-android-client.md §9) — never emits a
 * token (no real FCM SDK wired, `google-services.json` absent per the Mobile H1-waiver). The
 * contract is fixed now: `AppContainer` wires [addRefreshListener] to
 * `DeviceRegistrar::onPushTokenRefreshed`, so H1/A2 only need to swap this class for a real
 * `FirebaseMessaging`-backed one — no call-site change (001-api-contract.md §4.1,
 * 000-overview.md §O4).
 *
 * [simulateTokenRefresh] is a dev/test-only hook for exercising the wiring before real FCM
 * exists — it is never called from production code paths.
 */
class StubPushTokenProvider : PushTokenProvider {
    private val listeners = mutableListOf<PushTokenRefreshListener>()

    override suspend fun currentToken(): String? = null

    override fun addRefreshListener(listener: PushTokenRefreshListener) {
        listeners.add(listener)
    }

    /** TODO(H1/A2): replaced by a real `FirebaseMessagingService.onNewToken` override firing
     * this same listener list. */
    fun simulateTokenRefresh(token: String) {
        listeners.forEach { it.onNewToken(token) }
    }
}
