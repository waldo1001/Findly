package com.findly.android.location.geofence

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.findly.android.FindlyApplication
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * `GeofencingClient`'s callback entry point (specs/009-device-runtime.md §6.3) — the
 * [android.app.PendingIntent] every `addGeofences` call registers
 * ([GeofencingClientManager]/`AppContainer`) fires this receiver on an enter/exit transition. Thin,
 * untested Android-framework glue by design; all decision logic (event building, queuing, the
 * additional `source: "geofence"` fix capture) lives in the tested [GeofenceTransitionHandler].
 *
 * Uses `goAsync()` + a dedicated coroutine because the real work here is suspend (Room writes,
 * [com.findly.android.location.FixCaptureCoordinator]'s own suspend capture path) and a
 * `BroadcastReceiver.onReceive()` has only a short window before the OS may consider it finished —
 * `goAsync()` extends that window so a process death mid-handling doesn't silently drop a detected
 * transition. Per the A11 task brief and specs/009 §6.3/§1.2/§4: a detected transition MUST NOT be
 * lost (unlike a mid-GPS-capture fix, which MAY be dropped) — this is the mechanism that honors
 * that.
 *
 * **A42 (docs/implementation-handoff.md) sweep, finding 2:** [GeofenceTransitionHandler.handle] has
 * no `try`/`catch` of its own (Room writes and the location-capture path can both throw on a cold
 * FCM/geofence-woken process, the same failure modes A39's review found for
 * [com.findly.android.queue.worker.LocateForegroundService]) and this scope carried no
 * [CoroutineExceptionHandler] — an uncaught throw here reached the default handler and killed the
 * process on every geofence transition that hit one of those failure modes. Logs the exception's
 * class name only, never its message/cause (specs/009-device-runtime.md §9: counts and error codes
 * only, never coordinates/`deviceId`/tokens/phone numbers — notable here since this handler's own
 * payload, a lat/lon transition, is exactly the kind of thing an exception message could embed).
 */
class GeofenceTransitionReceiver : BroadcastReceiver() {

    private val exceptionHandler = CoroutineExceptionHandler { _, throwable ->
        Log.d(TAG, "unhandled geofence-transition coroutine failure (${throwable::class.simpleName})")
    }

    override fun onReceive(context: Context, intent: Intent) {
        val geofencingEvent = GeofencingEvent.fromIntent(intent) ?: return
        if (geofencingEvent.hasError()) return
        val transitionEvent = geofencingEvent.toTransitionEventOrNull() ?: return

        val pendingResult = goAsync()
        val handler = (context.applicationContext as FindlyApplication).container.geofenceTransitionHandler
        CoroutineScope(Dispatchers.Default + exceptionHandler).launch {
            try {
                handler.handle(transitionEvent)
            } finally {
                pendingResult.finish()
            }
        }
    }

    private companion object {
        const val TAG = "FindlySync"
    }

    private fun GeofencingEvent.toTransitionEventOrNull(): GeofenceTransitionEvent? {
        val transition = when (geofenceTransition) {
            Geofence.GEOFENCE_TRANSITION_ENTER -> GeofenceTransitionType.Enter
            Geofence.GEOFENCE_TRANSITION_EXIT -> GeofenceTransitionType.Exit
            else -> return null // DWELL or anything else is never requested (§6.3: enter/exit only)
        }
        val ids = triggeringGeofences?.mapNotNull { it.requestId }?.takeIf { it.isNotEmpty() } ?: return null
        val location = triggeringLocation ?: return null
        return GeofenceTransitionEvent(
            geofenceIds = ids,
            transition = transition,
            lat = location.latitude,
            lon = location.longitude,
            accuracyM = location.accuracy.toDouble(),
        )
    }
}
