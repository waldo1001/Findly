package com.findly.android.ui.history

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.network.ports.LocationsApi
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Thin Android `ViewModel` wrapper — all logic lives in [HistoryStateHolder] (specs/003-android-
 * client.md §14; same convention as `HomeViewModel`/`MapViewModel`). */
class HistoryViewModel(locationsApi: LocationsApi) : ViewModel() {
    private val stateHolder = HistoryStateHolder(locationsApi)
    val state: StateFlow<HistoryUiState> = stateHolder.state

    fun load(userId: String, from: String, to: String, deviceId: String? = null) {
        viewModelScope.launch { stateHolder.load(userId, from, to, deviceId) }
    }

    fun loadMore() {
        viewModelScope.launch { stateHolder.loadMore() }
    }
}

class HistoryViewModelFactory(private val locationsApi: LocationsApi) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = HistoryViewModel(locationsApi) as T
}
