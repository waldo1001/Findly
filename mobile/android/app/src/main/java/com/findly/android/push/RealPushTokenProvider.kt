package com.findly.android.push

import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.tasks.await

/**
 * The real FCM-backed [PushTokenProvider] (specs/003-android-client.md §9;
 * specs/009-device-runtime.md §5.5) — replaces `StubPushTokenProvider` at the one `AppContainer`
 * wiring point, with no call-site change: `addRefreshListener` is still wired to
 * `DeviceRegistrar::onPushTokenRefreshed` there.
 *
 * [currentToken] wraps `FirebaseMessaging.getInstance().token`, a Play Services `Task<String>`,
 * via `kotlinx-coroutines-play-services`'s `Task<T>.await()` bridge — the same library
 * [com.findly.android.auth.FirebaseAuthProvider] already depends on
 * (`FirebaseUser.getIdToken().await()`), so no new coroutine-bridge dependency was needed. A
 * failed/cancelled `Task` (no Google Play Services, no network on first fetch, …) yields `null`
 * rather than throwing — the same "no valid token yet" contract the old stub documented (001
 * §4.1: `pushToken` is OPTIONAL on `POST /devices`). [firebaseMessaging] is a lazily-invoked
 * supplier (not an eagerly-evaluated default constructor argument) so a plain unit test can
 * construct this class and exercise [addRefreshListener]/[notifyTokenRefreshed] without ever
 * touching the real Firebase SDK.
 *
 * [notifyTokenRefreshed] is the producer side of the listener list — called only by
 * [FindlyMessagingService.onNewToken], which the FCM SDK invokes on a real token refresh. Kept
 * `internal` (not part of the [PushTokenProvider] interface) since only that one production
 * caller exists; every other consumer only ever calls [addRefreshListener] (003 §9's fixed
 * contract).
 */
class RealPushTokenProvider(
    private val firebaseMessaging: () -> FirebaseMessaging = { FirebaseMessaging.getInstance() },
) : PushTokenProvider {

    private val listeners = mutableListOf<PushTokenRefreshListener>()

    override suspend fun currentToken(): String? = try {
        firebaseMessaging().token.await()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        null
    }

    override fun addRefreshListener(listener: PushTokenRefreshListener) {
        listeners.add(listener)
    }

    internal fun notifyTokenRefreshed(token: String) {
        listeners.forEach { it.onNewToken(token) }
    }
}
