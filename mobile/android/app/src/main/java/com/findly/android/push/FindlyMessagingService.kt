package com.findly.android.push

import com.findly.android.FindlyApplication
import com.findly.android.pushmessages.PushMessageType
import com.findly.android.pushmessages.PushPriorityDemotion
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking

/**
 * The real FCM entry point (specs/003-android-client.md §9; specs/009-device-runtime.md §5). Kept
 * thin and untestable-by-design — same category as `queue/worker/LocationSyncWorker` (003
 * §10.5) — all real logic lives in unit-tested plain Kotlin classes
 * ([com.findly.android.pushmessages.PushMessageDispatcher] and its four per-type handlers,
 * [com.findly.android.pushmessages.LocateRequestHandoff], [RealPushTokenProvider]'s listener
 * bookkeeping) that this class only invokes.
 *
 * [onNewToken] fires through [RealPushTokenProvider]'s own listener list via
 * [FindlyApplication.container] — the process-wide singleton `AppContainer` that `AppContainer`'s
 * own `init` block already wired to `DeviceRegistrar::onPushTokenRefreshed` (001 §4.1, 000 §O4) —
 * so no second wiring point is introduced here.
 *
 * **A39 — `LOCATE_REQUEST` no longer blocks this callback (specs/009 §5.1 "Android execution
 * model", amended 2026-09-06).** `onMessageReceived` has roughly 10 s of guaranteed execution;
 * `LOCATE_REQUEST` used to `runBlocking` straight through a 30 s HIGH-accuracy GPS capture plus an
 * HTTP call, well past that budget, risking the process losing its Doze exemption and being
 * killed mid-capture. That type is now routed to [com.findly.android.pushmessages.LocateRequestHandoff.handle]
 * instead — a plain (non-`suspend`) method that returns immediately, having only read two cheap
 * `RemoteMessage` ints and handed the actual routing decision + capture off to a coroutine on
 * `AppContainer`'s own scope.
 *
 * The other three types (`SETTINGS_CHANGED`, `GEOFENCE_EVENT`, `GEOFENCE_CONFIG_CHANGED`) keep
 * their existing in-callback `runBlocking` dispatch — each is cheap (an in-memory schedule
 * rebuild, posting a local notification, or one small `GET /geofences` fetch plus geofence
 * re-registration) and, per the A39 task brief, "already correct". Honest caveat, not silently
 * assumed: `GEOFENCE_CONFIG_CHANGED`'s `GET /geofences` call is the one of the three that does real
 * network I/O with no bound tied to the 10 s budget — on a slow or lossy connection it *could*
 * approach or exceed it, unlike the other two, which never leave the process. Left unchanged here
 * because it is out of A39's scope (only `LOCATE_REQUEST` handling is authorized to change) and
 * flagged in the task report instead.
 */
class FindlyMessagingService : FirebaseMessagingService() {

    private val container get() = (application as FindlyApplication).container

    override fun onNewToken(token: String) {
        (container.pushTokenProvider as? RealPushTokenProvider)?.notifyTokenRefreshed(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        if (PushMessageType.from(message.data) is PushMessageType.LocateRequest) {
            val isHighPriority = message.priority == RemoteMessage.PRIORITY_HIGH
            val wasDemoted = PushPriorityDemotion.wasDemoted(message.priority, message.originalPriority)
            container.locateRequestHandoff.handle(message.data, isHighPriority, wasDemoted)
            return
        }

        runBlocking(Dispatchers.IO) {
            container.pushMessageDispatcher.dispatch(message.data)
        }
    }
}
