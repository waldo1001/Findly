package com.findly.android.launch

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.auth.AuthProvider
import com.findly.android.device.DeviceRegistrar
import com.findly.android.network.ports.FamilyApi
import com.findly.android.push.PushTokenProvider
import com.findly.android.ui.settings.LocalStateWiper
import kotlinx.coroutines.flow.StateFlow

/**
 * Thin Android `ViewModel` wrapper — all state-transition logic lives in [LaunchGateStateHolder]
 * (specs/010-app-shell-and-screen-ux.md §1.1, mirroring the deleted `HomeViewModel`'s shape,
 * specs/003-android-client.md §12/§14): nothing here is separately unit-tested beyond delegation,
 * satisfied by `LaunchGateStateHolderTest` instead.
 *
 * [retryRegistration] is exposed so [com.findly.android.ui.nav.FindlyNavHost] can trigger a
 * device-registration retry from any of the 010 §2.2 Onboarding bootstrap-completion callbacks,
 * without this `ViewModel` needing any state of its own.
 */
class LaunchGateViewModel(
    authProvider: AuthProvider,
    deviceRegistrar: DeviceRegistrar,
    pushTokenProvider: PushTokenProvider,
    familyApi: FamilyApi,
    localStateWiper: LocalStateWiper,
) : ViewModel() {
    private val stateHolder =
        LaunchGateStateHolder(authProvider, deviceRegistrar, pushTokenProvider, familyApi, localStateWiper, viewModelScope)
    val state: StateFlow<LaunchUiState> = stateHolder.state

    fun retryRegistration() = stateHolder.retryRegistration()
}

/** No DI framework (specs/003 §3) — a plain [ViewModelProvider.Factory] constructs
 * [LaunchGateViewModel] with its five dependencies — [localStateWiper] added by 010 §1.1's A37
 * amendment, so a confirmed auth failure on the launch probe can clear local state the same way
 * every other session-ending path already does ([LocalStateWiper]'s doc). */
class LaunchGateViewModelFactory(
    private val authProvider: AuthProvider,
    private val deviceRegistrar: DeviceRegistrar,
    private val pushTokenProvider: PushTokenProvider,
    private val familyApi: FamilyApi,
    private val localStateWiper: LocalStateWiper,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T =
        LaunchGateViewModel(authProvider, deviceRegistrar, pushTokenProvider, familyApi, localStateWiper) as T
}
