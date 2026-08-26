package com.findly.android.ui.map

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.network.ports.LocationsApi
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Thin Android `ViewModel` wrapper — all state-transition logic lives in [MapStateHolder]
 * (specs/003-android-client.md §14: nothing here is separately unit-tested beyond delegation,
 * same convention as `HomeViewModel`). */
class MapViewModel(locationsApi: LocationsApi) : ViewModel() {
    private val stateHolder = MapStateHolder(locationsApi, viewModelScope)
    val state: StateFlow<MapUiState> = stateHolder.state

    fun refresh() {
        viewModelScope.launch { stateHolder.refresh() }
    }

    /** specs/010 §3.5 — select/deselect a member (toggling), zooming to their freshest located
     * device when one exists. */
    fun selectMember(userId: String) = stateHolder.selectMember(userId)

    /** specs/010 §3.5 — tapping the map background deselects. */
    fun deselect() = stateHolder.deselect()

    /** specs/010 §3.4's explicit fit-all action. */
    fun fitAll() = stateHolder.fitAll()
}

class MapViewModelFactory(private val locationsApi: LocationsApi) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = MapViewModel(locationsApi) as T
}
