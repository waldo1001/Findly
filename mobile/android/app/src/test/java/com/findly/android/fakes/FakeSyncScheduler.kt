package com.findly.android.fakes

import com.findly.android.location.settings.SyncScheduler

class FakeSyncScheduler : SyncScheduler {
    val rescheduleCalls = mutableListOf<Int>()
    var cancelAllCallCount = 0
        private set

    override fun reschedule(syncIntervalMinutes: Int) {
        rescheduleCalls.add(syncIntervalMinutes)
    }

    override fun cancelAll() {
        cancelAllCallCount++
    }
}
