package com.findly.android.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.network.ports.DevicesApi
import com.findly.android.network.ports.FamilyApi
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Thin Android `ViewModel` wrapper — all logic lives in [SettingsStateHolder] (specs/003-
 * android-client.md §14; same convention as `HomeViewModel`/`MapViewModel`). */
class SettingsViewModel(
    familyApi: FamilyApi,
    devicesApi: DevicesApi,
) : ViewModel() {
    private val stateHolder = SettingsStateHolder(familyApi, devicesApi, viewModelScope)
    val state: StateFlow<SettingsUiState> = stateHolder.state

    fun reload() {
        viewModelScope.launch { stateHolder.load() }
    }

    fun updateDeviceSettings(deviceId: String, syncIntervalMinutes: Int? = null, trackingEnabled: Boolean? = null) {
        viewModelScope.launch { stateHolder.updateDeviceSettings(deviceId, syncIntervalMinutes, trackingEnabled) }
    }

    fun updateMemberRole(userId: String, role: String) {
        viewModelScope.launch { stateHolder.updateMember(userId, role = role) }
    }

    fun removeMember(userId: String) {
        viewModelScope.launch { stateHolder.removeMember(userId) }
    }
}

class SettingsViewModelFactory(
    private val familyApi: FamilyApi,
    private val devicesApi: DevicesApi,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = SettingsViewModel(familyApi, devicesApi) as T
}
