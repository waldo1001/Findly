package com.findly.android.fakes

import com.findly.android.location.settings.CachedGeofenceConfig
import com.findly.android.location.settings.GeofenceConfigStateStore

class InMemoryGeofenceConfigStateStore(initial: CachedGeofenceConfig? = null) : GeofenceConfigStateStore {
    private var stored: CachedGeofenceConfig? = initial

    override suspend fun current(): CachedGeofenceConfig? = stored

    override suspend fun update(config: CachedGeofenceConfig) {
        stored = config
    }

    override suspend fun clear() {
        stored = null
    }
}
