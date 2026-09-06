package com.findly.android.ui.locate

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.network.ports.LocateApi
import com.findly.android.network.ports.LocationsApi
import kotlinx.coroutines.flow.StateFlow

/** Thin Android `ViewModel` wrapper — all logic lives in [LocateStateHolder] (specs/003-android-
 * client.md §14; same convention as `HomeViewModel`/`MapViewModel`). `viewModelScope` clearing
 * (screen navigated away from) cancels any in-flight poll loop automatically. [locationsApi] is
 * A39's addition — the specs/009 §5.1 "Requester side" `GET /locations/latest` fallback check. */
class LocateViewModel(locateApi: LocateApi, locationsApi: LocationsApi) : ViewModel() {
    private val stateHolder = LocateStateHolder(locateApi, locationsApi, viewModelScope)
    val state: StateFlow<LocateUiState> = stateHolder.state

    fun requestLocate(targetUserId: String? = null, targetDeviceId: String? = null) =
        stateHolder.requestLocate(targetUserId, targetDeviceId)

    override fun onCleared() {
        stateHolder.cancelPolling()
        super.onCleared()
    }
}

class LocateViewModelFactory(
    private val locateApi: LocateApi,
    private val locationsApi: LocationsApi,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = LocateViewModel(locateApi, locationsApi) as T
}
