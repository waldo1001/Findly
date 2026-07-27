package com.findly.android.fakes

import com.findly.android.location.settings.DeviceSettingsStateStore
import com.findly.android.network.DeviceSettingsSnapshot

class InMemoryDeviceSettingsStateStore(initial: DeviceSettingsSnapshot? = null) : DeviceSettingsStateStore {
    private var stored: DeviceSettingsSnapshot? = initial

    override suspend fun current(): DeviceSettingsSnapshot? = stored

    override suspend fun update(settings: DeviceSettingsSnapshot) {
        stored = settings
    }
}
