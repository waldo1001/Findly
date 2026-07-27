package com.findly.android.location.settings

import com.findly.android.network.DeviceSettingsSnapshot

/**
 * Holds the last-applied [DeviceSettingsSnapshot] (specs/009-device-runtime.md §3.5) — the shared
 * source of truth [DeviceSettingsCoordinator] reads as "previous" when deciding what changed, and
 * that a real [com.findly.android.location.TrackingPauseState] reads to answer "are we paused
 * right now" for every capture attempt. Persisted (not merely in-memory) so a paused device stays
 * correctly known-paused across a process restart, before the next settings sync has a chance to
 * confirm it again (`SharedPreferencesDeviceSettingsStateStore` is the real implementation).
 */
interface DeviceSettingsStateStore {
    suspend fun current(): DeviceSettingsSnapshot?
    suspend fun update(settings: DeviceSettingsSnapshot)
}
