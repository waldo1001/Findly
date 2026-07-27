package com.findly.android.location

import com.findly.android.queue.FixQueueStore
import com.findly.android.queue.FixSource
import com.findly.android.queue.QueuedFix
import java.time.Duration
import java.time.Instant
import java.util.UUID

/** Whether tracking is currently paused (`trackingEnabled: false`, specs/009-device-runtime.md
 * §4) — backed by whatever holds the last-applied [com.findly.android.network.DeviceSettingsSnapshot]. */
fun interface TrackingPauseState {
    suspend fun isPaused(): Boolean
}

/** Whether this device currently holds the location permission a capture needs (specs/009 §7). */
fun interface LocationPermissionState {
    suspend fun isGranted(): Boolean
}

/**
 * The capture-and-queue pipeline (specs/009-device-runtime.md §1) — ties A9's [LocationCapturer]
 * seam + [FixQueueStore] together with the §1.2 suppression rules, and owns the
 * [FixSource] → ([LocationAccuracyTier], timeout) mapping A9's seam deliberately left to its
 * callers (see [LocationCapturer]'s doc for why `BALANCED` alone can't tell `periodic` and
 * `geofence` apart). This is **the** seam every A10-owned trigger calls through: the periodic
 * worker/foreground service (`source: "periodic"`) and a manual refresh (`source: "manual"`).
 * `source: "locate"` is deliberately **not** routed through here — A9's
 * [com.findly.android.pushmessages.LocateRequestPushHandler] calls [LocationCapturer] directly,
 * bypassing suppression entirely, because a `LOCATE_REQUEST` must still be fulfilled while paused
 * (§5.1) — this class's pause/permission gate would be actively wrong for that case.
 *
 * `hint` is the seam **A11**'s geofence-transition handling calls for its own `source: "geofence"`
 * fix (§6.3: "additionally capture one fix with `source: geofence`") — when supplied, the
 * transition's own coordinates are used directly and [LocationCapturer] is never invoked at all
 * (§1.1: "MAY reuse the transition's own coordinates").
 *
 * Suppression order matters (§1.2): paused / permission-absent are checked **before** ever
 * invoking the capturer (no GPS burn at all); the identical-position debounce can only be checked
 * **after** a fix comes back, and pause is re-checked after capture too, so a pause that lands
 * mid-capture drops the result instead of queuing it ("in-flight captures dropped, not queued",
 * 009 §4). Every skip path is silent — never an exception, never surfaced to the user (§1.2).
 */
class FixCaptureCoordinator(
    private val capturer: LocationCapturer,
    private val queueStore: FixQueueStore,
    private val pauseState: TrackingPauseState,
    private val permissionState: LocationPermissionState,
    private val fixIdGenerator: () -> String = { UUID.randomUUID().toString() },
    private val now: () -> Instant = Instant::now,
) {
    private var lastCaptured: Pair<CapturedFix, Instant>? = null

    /**
     * Captures one fix for [source] and enqueues it, unless suppressed. [hint] short-circuits an
     * actual GPS request (see class doc). Returns the captured/reused fix even when it was
     * ultimately debounce-suppressed post-capture, so a caller like a geofence-event handler can
     * still use the position for its own purposes — `null` only ever means "nothing was queued".
     */
    suspend fun captureAndQueue(source: FixSource, hint: CapturedFix? = null): CapturedFix? {
        if (pauseState.isPaused()) return null
        if (!permissionState.isGranted()) return null

        val fix = hint ?: capturer.captureFix(accuracyFor(source), timeoutMillisFor(source)) ?: return null

        // Pause arriving mid-capture: drop, don't queue (009 §4).
        if (pauseState.isPaused()) return null

        if (isDuplicateWithinDebounce(fix)) return null
        lastCaptured = fix to now()

        queueStore.enqueue(
            QueuedFix(
                fixId = fixIdGenerator(),
                recordedAt = fix.recordedAt,
                lat = fix.lat,
                lon = fix.lon,
                accuracyM = fix.accuracyM,
                altitudeM = fix.altitudeM,
                speedMps = fix.speedMps,
                bearingDeg = fix.bearingDeg,
                batteryPct = fix.batteryPct,
                source = source,
            ),
        )
        return fix
    }

    /** §1.2: "an identical-position fix was captured < 60 s ago (debounce against duplicate
     * platform callbacks)". */
    private fun isDuplicateWithinDebounce(fix: CapturedFix): Boolean {
        val (previousFix, previousAt) = lastCaptured ?: return false
        val samePosition = previousFix.lat == fix.lat && previousFix.lon == fix.lon
        val withinDebounceWindow = Duration.between(previousAt, now()) < DEBOUNCE_WINDOW
        return samePosition && withinDebounceWindow
    }

    private companion object {
        val DEBOUNCE_WINDOW: Duration = Duration.ofSeconds(60)
        const val DEFAULT_TIMEOUT_MILLIS = 30_000L
        const val GEOFENCE_TIMEOUT_MILLIS = 15_000L

        /** §1.1's "Accuracy request" column for the sources that reach this class. */
        fun accuracyFor(source: FixSource): LocationAccuracyTier = when (source) {
            FixSource.Manual -> LocationAccuracyTier.HIGH
            FixSource.Periodic, FixSource.Geofence, FixSource.Locate -> LocationAccuracyTier.BALANCED
        }

        /** §1.1's "Timeout" column — the only reason this class doesn't just rely on
         * [LocationCapturer.captureFix]'s own 30 s default is `geofence`'s shorter 15 s. */
        fun timeoutMillisFor(source: FixSource): Long = when (source) {
            FixSource.Geofence -> GEOFENCE_TIMEOUT_MILLIS
            else -> DEFAULT_TIMEOUT_MILLIS
        }
    }
}
