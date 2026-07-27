package com.findly.android.fakes

import com.findly.android.location.settings.GeofenceRegistry

class FakeGeofenceRegistry : GeofenceRegistry {
    var unregisterAllCallCount = 0
        private set

    override suspend fun unregisterAll() {
        unregisterAllCallCount++
    }
}
