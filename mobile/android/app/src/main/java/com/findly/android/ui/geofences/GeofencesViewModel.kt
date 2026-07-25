package com.findly.android.ui.geofences

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.network.ports.GeofenceApi
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Thin Android `ViewModel` wrapper — all logic lives in [GeofencesStateHolder] (specs/003-
 * android-client.md §14; same convention as `HomeViewModel`/`MapViewModel`). */
class GeofencesViewModel(private val geofenceApi: GeofenceApi) : ViewModel() {
    private val stateHolder = GeofencesStateHolder(geofenceApi, viewModelScope)
    val state: StateFlow<GeofencesUiState> = stateHolder.state

    fun validate(draft: GeofenceUi): String? = stateHolder.validate(draft)

    fun upsertGeofence(draft: GeofenceUi) = stateHolder.upsertGeofence(draft)

    fun removeGeofence(geofenceId: String) = stateHolder.removeGeofence(geofenceId)

    fun save() {
        viewModelScope.launch { stateHolder.save() }
    }

    fun reload() {
        viewModelScope.launch { stateHolder.load() }
    }
}

class GeofencesViewModelFactory(private val geofenceApi: GeofenceApi) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = GeofencesViewModel(geofenceApi) as T
}
