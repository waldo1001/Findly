package com.findly.android.ui.devices

import com.findly.android.network.ports.DevicesApi
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The Devices screen's pure state machine (specs/010-app-shell-and-screen-ux.md §4; wire shapes
 * specs/001-api-contract.md §4.2/§4.3).
 *
 * STUB (deliberately wrong, not absent): every method is a no-op so `DevicesStateHolderTest`
 * fails on its assertions, not on a missing type — TDD red, about to be replaced.
 */
class DevicesStateHolder(
    private val devicesApi: DevicesApi,
    val isParent: Boolean,
    scope: CoroutineScope,
) {
    private val _state = MutableStateFlow<DevicesUiState>(DevicesUiState.Loading)
    val state: StateFlow<DevicesUiState> = _state.asStateFlow()

    suspend fun load() = Unit

    fun updateRenameDraft(deviceId: String, draft: String) = Unit

    suspend fun setTracking(deviceId: String, enabled: Boolean) = Unit

    suspend fun setSyncInterval(deviceId: String, minutes: Int) = Unit

    suspend fun rename(deviceId: String, name: String) = Unit
}
