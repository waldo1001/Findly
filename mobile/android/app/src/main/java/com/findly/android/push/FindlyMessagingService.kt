package com.findly.android.push

import com.findly.android.FindlyApplication
import com.findly.android.pushmessages.PushMessageLane
import com.findly.android.pushmessages.PushMessageLanePolicy
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
 * ([com.findly.android.pushmessages.PushMessageLanePolicy],
 * [com.findly.android.pushmessages.PushMessageDispatcher] and its two per-type handlers,
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
 * **A43 — `GEOFENCE_CONFIG_CHANGED` no longer blocks this callback either (specs/009 §5.4/§6.2).**
 * A39's implementing agent flagged, rather than fixed out of scope, that this type's real
 * `GET /geofences` fetch plus full `GeofencingClient` unregister/re-register cycle carried no
 * timeout tied to this callback's ~10 s budget — on a slow or lossy connection that could approach
 * or exceed it, risking the same Doze-exemption loss and mid-re-registration kill that motivated
 * A39, landing in 009 §6.2's documented "zero geofences registered" state (which that section's
 * own self-healing bound, the next report's `geofenceEtag` piggyback, already covers — this is a
 * robustness fix, not a data-loss fix). Routed to
 * [com.findly.android.queue.worker.GeofenceConfigSyncWorkEnqueuer.enqueue] — the same expedited-
 * `WorkManager` seam A39 built for the demoted-`LOCATE_REQUEST` fallback
 * ([com.findly.android.queue.worker.LocateRequestWorker]) — instead of a coroutine handoff: unlike
 * `LOCATE_REQUEST`, there is no priority/permission/presence-service decision to make first, so a
 * synchronous, immediately-returning `WorkManager.enqueue()` call is the whole handoff.
 *
 * The remaining types (`SETTINGS_CHANGED`, `GEOFENCE_EVENT`, and any unknown/reserved/missing
 * type) keep the in-callback `runBlocking` dispatch — all are cheap, pure in-memory work (a
 * schedule rebuild, posting a local notification, or a no-op) with no I/O, independently verified
 * safe by both A39's and A43's reviewers.
 *
 * **A47 — which lane a push type takes is now [com.findly.android.pushmessages.PushMessageLanePolicy],
 * not an inline `if`/`if`/fallthrough here.** The three branches below only *carry out* whichever
 * [PushMessageLane] the policy returns; `dispatch(` is never reached for `LOCATE_REQUEST` or
 * `GEOFENCE_CONFIG_CHANGED` (verified: this `when`'s `Dispatcher` branch is `dispatch`'s only
 * production call site), so `PushMessageDispatcher` no longer carries handlers for either type —
 * see its own doc.
 */
class FindlyMessagingService : FirebaseMessagingService() {

    private val container get() = (application as FindlyApplication).container

    override fun onNewToken(token: String) {
        (container.pushTokenProvider as? RealPushTokenProvider)?.notifyTokenRefreshed(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val type = PushMessageType.from(message.data)

        when (PushMessageLanePolicy.decide(type)) {
            PushMessageLane.LocateHandoff -> {
                val isHighPriority = message.priority == RemoteMessage.PRIORITY_HIGH
                val wasDemoted = PushPriorityDemotion.wasDemoted(message.priority, message.originalPriority)
                container.locateRequestHandoff.handle(message.data, isHighPriority, wasDemoted)
            }

            PushMessageLane.ExpeditedGeofenceConfigSync -> container.geofenceConfigSyncWorkEnqueuer.enqueue()

            PushMessageLane.Dispatcher -> runBlocking(Dispatchers.IO) {
                container.pushMessageDispatcher.dispatch(message.data)
            }
        }
    }
}
