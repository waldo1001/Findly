package com.findly.android.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.auth.AuthProvider
import com.findly.android.device.DeviceRegistrar
import com.findly.android.network.ports.FamilyApi
import com.findly.android.push.PushTokenProvider
import kotlinx.coroutines.flow.StateFlow

/**
 * Thin Android `ViewModel` wrapper — all state-transition logic lives in [HomeStateHolder]
 * (specs/003-android-client.md §12, §14): nothing here is separately unit-tested beyond
 * delegation, matching the task's "viewmodel state transitions" test requirement, which is
 * satisfied by `HomeStateHolderTest` instead.
 *
 * A24: [retryRegistration] is exposed so [com.findly.android.ui.nav.FindlyNavHost] can trigger a
 * device-registration retry from any of the four profile-bootstrap completion callbacks, without
 * this `ViewModel` needing any state of its own.
 */
class HomeViewModel(
    authProvider: AuthProvider,
    deviceRegistrar: DeviceRegistrar,
    pushTokenProvider: PushTokenProvider,
    familyApi: FamilyApi,
) : ViewModel() {
    private val stateHolder = HomeStateHolder(authProvider, deviceRegistrar, pushTokenProvider, familyApi, viewModelScope)
    val state: StateFlow<HomeUiState> = stateHolder.state

    fun retryRegistration() = stateHolder.retryRegistration()
}

/** No DI framework in A1 (specs/003 §3) — a plain [ViewModelProvider.Factory] constructs
 * [HomeViewModel] with its four dependencies. */
class HomeViewModelFactory(
    private val authProvider: AuthProvider,
    private val deviceRegistrar: DeviceRegistrar,
    private val pushTokenProvider: PushTokenProvider,
    private val familyApi: FamilyApi,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T =
        HomeViewModel(authProvider, deviceRegistrar, pushTokenProvider, familyApi) as T
}
