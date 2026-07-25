package com.findly.android.ui.locate

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.network.ports.LocateApi
import kotlinx.coroutines.flow.StateFlow

/** Thin Android `ViewModel` wrapper — all logic lives in [LocateStateHolder] (specs/003-android-
 * client.md §14; same convention as `HomeViewModel`/`MapViewModel`). `viewModelScope` clearing
 * (screen navigated away from) cancels any in-flight poll loop automatically. */
class LocateViewModel(locateApi: LocateApi) : ViewModel() {
    private val stateHolder = LocateStateHolder(locateApi, viewModelScope)
    val state: StateFlow<LocateUiState> = stateHolder.state

    fun requestLocate(targetUserId: String? = null, targetDeviceId: String? = null) =
        stateHolder.requestLocate(targetUserId, targetDeviceId)

    override fun onCleared() {
        stateHolder.cancelPolling()
        super.onCleared()
    }
}

class LocateViewModelFactory(private val locateApi: LocateApi) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = LocateViewModel(locateApi) as T
}
