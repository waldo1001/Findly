package com.findly.android.fakes

import com.findly.android.queue.worker.ScheduleRebuilder

/** Test fake — mirrors the backend's `test/fakes/` convention (backend/README.md). Records every
 * [rebuild] call for `SettingsChangedPushHandlerTest` (specs/009-device-runtime.md §5.2/§3.5). */
class FakeScheduleRebuilder : ScheduleRebuilder {
    val calls = mutableListOf<Pair<Int, Boolean>>()

    override fun rebuild(syncIntervalMinutes: Int, trackingEnabled: Boolean) {
        calls.add(syncIntervalMinutes to trackingEnabled)
    }
}
