package com.findly.android.location.settings

import android.content.Context
import com.findly.android.network.FindlyJson
import com.findly.android.network.dto.GeofenceDto
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString

/** Real, thin Android-framework [GeofenceConfigStateStore] — untested, like
 * `SharedPreferencesDeviceSettingsStateStore` (specs/003-android-client.md §3). The geofence list
 * is serialized to a JSON string via [FindlyJson] (the same `Json` config every wire DTO already
 * uses) — not sensitive (geofence names/coordinates a family already configured, not a
 * credential), same posture as the interval/tracking-enabled pair next to it. */
class SharedPreferencesGeofenceConfigStateStore(context: Context) : GeofenceConfigStateStore {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val geofenceListSerializer = ListSerializer(GeofenceDto.serializer())

    override suspend fun current(): CachedGeofenceConfig? {
        val etag = prefs.getString(KEY_ETAG, null) ?: return null
        val geofencesJson = prefs.getString(KEY_GEOFENCES, null) ?: return null
        val geofences = FindlyJson.decodeFromString(geofenceListSerializer, geofencesJson)
        return CachedGeofenceConfig(etag, geofences)
    }

    override suspend fun update(config: CachedGeofenceConfig) {
        val geofencesJson = FindlyJson.encodeToString(geofenceListSerializer, config.geofences)
        prefs.edit()
            .putString(KEY_ETAG, config.etag)
            .putString(KEY_GEOFENCES, geofencesJson)
            .apply()
    }

    override suspend fun clear() {
        prefs.edit().clear().apply()
    }

    private companion object {
        const val PREFS_NAME = "findly_geofence_config"
        const val KEY_ETAG = "etag"
        const val KEY_GEOFENCES = "geofences_json"
    }
}
