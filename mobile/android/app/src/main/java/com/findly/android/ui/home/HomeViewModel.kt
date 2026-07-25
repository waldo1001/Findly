package com.findly.android.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.auth.AuthProvider
import com.findly.android.device.DeviceRegistrar
import kotlinx.coroutines.flow.StateFlow

/**
 * Thin Android `ViewModel` wrapper — all state-transition logic lives in [HomeStateHolder]
 * (specs/003-android-client.md §12, §14): nothing here is separately unit-tested beyond
 * delegation, matching the task's "viewmodel state transitions" test requirement, which is
 * satisfied by `HomeStateHolderTest` instead.
 */
class HomeViewModel(
    authProvider: AuthProvider,
    deviceRegistrar: DeviceRegistrar,
) : ViewModel() {
    private val stateHolder = HomeStateHolder(authProvider, deviceRegistrar, viewModelScope)
    val state: StateFlow<HomeUiState> = stateHolder.state
}

/** No DI framework in A1 (specs/003 §3) — a plain [ViewModelProvider.Factory] constructs
 * [HomeViewModel] with its two dependencies. */
class HomeViewModelFactory(
    private val authProvider: AuthProvider,
    private val deviceRegistrar: DeviceRegistrar,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T =
        HomeViewModel(authProvider, deviceRegistrar) as T
}
