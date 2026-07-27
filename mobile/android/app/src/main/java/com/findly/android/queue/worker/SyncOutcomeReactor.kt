package com.findly.android.queue.worker

import com.findly.android.network.ApiError
import com.findly.android.network.DeviceSettingsSnapshot
import com.findly.android.queue.GeofenceEventSyncOutcome
import com.findly.android.queue.SyncOutcome

/** What a caller of [com.findly.android.queue.LocationSyncCoordinator.syncOnce] must do next
 * (specs/009-device-runtime.md §9). */
sealed class SyncReaction {
    /** Nothing special — keep going (more of the queue may remain; the caller loops on its own). */
    data object Continue : SyncReaction()

    /**
     * A successful flush (any 2xx) — 001-api-contract.md §5.1: **every** accepted response
     * carries the current `deviceSettings` + `geofenceEtag`, and applying that piggyback is
     * mandatory (specs/009-device-runtime.md §1), not just a `403 TRACKING_PAUSED` nicety. The
     * caller applies [deviceSettings] via
     * [com.findly.android.location.settings.DeviceSettingsCoordinator.applySettings] and then
     * **keeps draining** — unlike [ApplySettings] below, a successful sync never stops the run.
     * [geofenceEtag] is threaded through (not consumed yet — A11 scope, §6.2's ETag-mismatch
     * re-sync) so it's available to whoever wires that next, rather than dropped on the floor.
     */
    data class Synced(val deviceSettings: DeviceSettingsSnapshot, val geofenceEtag: String) : SyncReaction()

    /** `403 TRACKING_PAUSED` — apply immediately via the `error.details.deviceSettings` echo
     * (§9), i.e. call [com.findly.android.location.settings.DeviceSettingsCoordinator.applySettings].
     * Stops the run: 001 §5.1 — "a paused device MUST NOT flush", so continuing to drain would
     * only draw more `403`s. */
    data class ApplySettings(val settings: DeviceSettingsSnapshot) : SyncReaction()

    /** `404 DEVICE_NOT_FOUND` — stop the schedule, clear local device state, re-run registration;
     * if that also fails, treat as signed-out (§9). */
    data object ReRegisterDevice : SyncReaction()

    /** A second consecutive `401 AUTH_TOKEN_EXPIRED` (the first is already handled by the
     * retry-once path, specs/003-android-client.md §6.4) — stop the schedule (§9). */
    data object SignedOut : SyncReaction()

    /** Network failure / 5xx / any other non-definitive error — apply [BackoffPolicy] and retry. */
    data object RetryTransient : SyncReaction()
}

/**
 * Pure `SyncOutcome → SyncReaction` mapping (specs/009 §9) — decoupled from WorkManager/foreground
 * service so both scheduling paths react identically without duplicating this logic.
 */
object SyncOutcomeReactor {
    fun reactionFor(outcome: SyncOutcome): SyncReaction = when (outcome) {
        is SyncOutcome.NothingToSync -> SyncReaction.Continue
        is SyncOutcome.Synced -> SyncReaction.Synced(outcome.deviceSettings, outcome.geofenceEtag)
        // The dead batch is already handled inside the queue store (offenders dropped, remainder
        // un-frozen) - nothing further to react to here beyond trying again for the remainder.
        is SyncOutcome.Rejected -> SyncReaction.Continue
        is SyncOutcome.TransientFailure -> SyncReaction.RetryTransient
        is SyncOutcome.Paused -> SyncReaction.ApplySettings(
            DeviceSettingsSnapshot(outcome.syncIntervalMinutes, outcome.trackingEnabled),
        )
        is SyncOutcome.OtherFailure -> when (outcome.error) {
            is ApiError.DeviceNotFound -> SyncReaction.ReRegisterDevice
            is ApiError.AuthTokenExpired -> SyncReaction.SignedOut
            else -> SyncReaction.RetryTransient
        }
    }

    /** [GeofenceEventSyncOutcome] -> [SyncReaction] (specs/009-device-runtime.md §6.3/§9) — a
     * second mapping over the exact same [SyncReaction] shape rather than a shared supertype with
     * [SyncOutcome], so the two flush loops ([LocationSyncRunner]'s fix drain and its geofence-event
     * drain) can react identically without coupling the two outcome hierarchies together. */
    fun reactionForGeofenceEvents(outcome: GeofenceEventSyncOutcome): SyncReaction = when (outcome) {
        is GeofenceEventSyncOutcome.NothingToSync -> SyncReaction.Continue
        is GeofenceEventSyncOutcome.Synced -> SyncReaction.Synced(outcome.deviceSettings, outcome.geofenceEtag)
        is GeofenceEventSyncOutcome.TransientFailure -> SyncReaction.RetryTransient
        is GeofenceEventSyncOutcome.Paused -> SyncReaction.ApplySettings(
            DeviceSettingsSnapshot(outcome.syncIntervalMinutes, outcome.trackingEnabled),
        )
        is GeofenceEventSyncOutcome.OtherFailure -> when (outcome.error) {
            is ApiError.DeviceNotFound -> SyncReaction.ReRegisterDevice
            is ApiError.AuthTokenExpired -> SyncReaction.SignedOut
            else -> SyncReaction.RetryTransient
        }
    }
}
