package com.findly.android.ui.map

import java.time.Instant

/**
 * specs/010-app-shell-and-screen-ux.md §3.4 (normative) — decides WHEN the camera policy re-runs,
 * as pure state kept independent of [MapCamera.target] (which decides WHERE once a run happens).
 * MUST run: the first successful load, an explicit fit-all action, or a member selection. MUST
 * NOT run on an ordinary refresh — even one whose marker set changed — except the one carve-out
 * the spec grants: a screen that opened with zero located points still gets exactly one run the
 * first time any point arrives.
 *
 * [MapStateHolder] owns one [CameraPolicyState] across its lifetime and calls
 * [shouldRunOnLoadOrRefresh] before every `refresh()` completion; fit-all/selection are simpler
 * "always run" explicit actions and don't need this state machine at all — only the "never on
 * refresh" rule needs memory across calls.
 */
data class CameraPolicyState(val hasRunInitial: Boolean = false, val hadAnyPoint: Boolean = false) {
    companion object {
        val INITIAL = CameraPolicyState()
    }
}

object MapCameraPolicy {
    /** True on: the very first load/refresh ever (regardless of point count — a screen that
     * opens with zero points still gets its one "settle on the calm default" run), or the first
     * later refresh that brings the first-ever point in from a zero-point open. False on every
     * refresh after that, even one whose marker set changed — the 010 §3.4 rule this task exists
     * to enforce. */
    fun shouldRunOnLoadOrRefresh(state: CameraPolicyState, hasPoints: Boolean): Boolean =
        !state.hasRunInitial || (!state.hadAnyPoint && hasPoints)

    fun nextState(state: CameraPolicyState, hasPoints: Boolean): CameraPolicyState =
        CameraPolicyState(hasRunInitial = true, hadAnyPoint = state.hadAnyPoint || hasPoints)

    /** specs/010 §3.5 / §10 "Freshest-device resolution": newest `recordedAt` among located
     * devices wins; devices without a fix are never chosen. */
    fun freshestLocatedDevice(devices: List<RosterDeviceUi>): RosterDeviceUi? =
        devices.filter { it.hasLocation && it.recordedAt != null }
            .maxByOrNull { Instant.parse(it.recordedAt) }
}
