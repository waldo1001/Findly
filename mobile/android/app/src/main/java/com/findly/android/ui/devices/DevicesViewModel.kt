package com.findly.android.ui.devices

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.network.ports.DevicesApi
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Thin Android `ViewModel` wrapper — all logic lives in [DevicesStateHolder] (specs/003-
 * android-client.md §14; same convention as the retired `SettingsViewModel`). */
class DevicesViewModel(
    devicesApi: DevicesApi,
    isParent: Boolean,
    // Code-review fix (A41 round 2, finding 9): a supplier, resolved fresh by
    // DevicesStateHolder on every load() rather than a value snapshotted once here.
    localDeviceId: () -> String? = { null },
) : ViewModel() {
    private val stateHolder = DevicesStateHolder(devicesApi, isParent, viewModelScope, localDeviceId)
    val state: StateFlow<DevicesUiState> = stateHolder.state
    val isParent: Boolean = stateHolder.isParent

    fun reload() {
        viewModelScope.launch { stateHolder.load() }
    }

    fun updateRenameDraft(deviceId: String, draft: String) {
        stateHolder.updateRenameDraft(deviceId, draft)
    }

    fun setTracking(deviceId: String, enabled: Boolean) {
        viewModelScope.launch { stateHolder.setTracking(deviceId, enabled) }
    }

    fun setSyncInterval(deviceId: String, minutes: Int) {
        viewModelScope.launch { stateHolder.setSyncInterval(deviceId, minutes) }
    }

    fun rename(deviceId: String, name: String) {
        viewModelScope.launch { stateHolder.rename(deviceId, name) }
    }
}

class DevicesViewModelFactory(
    private val devicesApi: DevicesApi,
    private val isParent: Boolean,
    private val localDeviceId: () -> String? = { null },
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T =
        DevicesViewModel(devicesApi, isParent, localDeviceId) as T
}
