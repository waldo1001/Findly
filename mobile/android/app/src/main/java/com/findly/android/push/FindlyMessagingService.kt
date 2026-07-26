package com.findly.android.push

import com.findly.android.FindlyApplication
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking

/**
 * The real FCM entry point (specs/003-android-client.md §9; specs/009-device-runtime.md §5). Kept
 * thin and untestable-by-design — same category as `queue/worker/LocationSyncWorker` (003
 * §10.5) — all real logic lives in unit-tested plain Kotlin classes
 * ([com.findly.android.pushmessages.PushMessageDispatcher] and its four per-type handlers,
 * [RealPushTokenProvider]'s listener bookkeeping) that this class only invokes.
 *
 * [onNewToken] fires through [RealPushTokenProvider]'s own listener list via
 * [FindlyApplication.container] — the process-wide singleton `AppContainer` that `AppContainer`'s
 * own `init` block already wired to `DeviceRegistrar::onPushTokenRefreshed` (001 §4.1, 000 §O4) —
 * so no second wiring point is introduced here.
 *
 * [onMessageReceived] blocks (via `runBlocking`) until the dispatcher's suspend work (an HTTP
 * call, a location fix capture) finishes, rather than firing-and-forgetting a detached coroutine
 * that could be silently abandoned if the process dies right after this method returns.
 * `FirebaseMessagingService` documents `onMessageReceived` as already running off the main thread,
 * so blocking here does not risk an ANR. The handlers themselves stay inside 009 §1.1's per-source
 * capture timeouts; this class does not enforce that itself.
 */
class FindlyMessagingService : FirebaseMessagingService() {

    private val container get() = (application as FindlyApplication).container

    override fun onNewToken(token: String) {
        (container.pushTokenProvider as? RealPushTokenProvider)?.notifyTokenRefreshed(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        runBlocking(Dispatchers.IO) {
            container.pushMessageDispatcher.dispatch(message.data)
        }
    }
}
