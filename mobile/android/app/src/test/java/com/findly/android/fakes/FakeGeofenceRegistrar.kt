package com.findly.android.fakes

import com.findly.android.network.dto.GeofenceDto
import com.findly.android.pushmessages.GeofenceRegistrar

/** Test fake — mirrors the backend's `test/fakes/` convention (backend/README.md). Records every
 * [registerAll] call for `GeofenceConfigChangedPushHandlerTest` (specs/009-device-runtime.md
 * §5.4/§6.2). */
class FakeGeofenceRegistrar : GeofenceRegistrar {
    val calls = mutableListOf<Pair<List<GeofenceDto>, String>>()

    override fun registerAll(geofences: List<GeofenceDto>, etag: String) {
        calls.add(geofences to etag)
    }
}
