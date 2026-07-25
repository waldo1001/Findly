package com.findly.android.ui.home

import com.findly.android.auth.AuthProvider
import com.findly.android.auth.AuthState
import com.findly.android.device.DeviceRegistrar
import com.findly.android.network.ApiResult
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * The Home proof screen's pure state machine (specs/003-android-client.md §12). Constructor-
 * injected [CoroutineScope] so tests supply a `TestScope`/`backgroundScope` — no
 * `androidx.lifecycle.ViewModel` dependency, no `android.*` import, unit-testable with plain
 * JUnit. [HomeViewModel] is a thin wrapper that owns one of these using `viewModelScope`.
 */
class HomeStateHolder(
    private val authProvider: AuthProvider,
    private val deviceRegistrar: DeviceRegistrar,
    scope: CoroutineScope,
) {
    private val _state = MutableStateFlow<HomeUiState>(HomeUiState.Loading)
    val state: StateFlow<HomeUiState> = _state.asStateFlow()

    init {
        scope.launch {
            authProvider.authState.collect { authState -> onAuthStateChanged(authState) }
        }
    }

    private suspend fun onAuthStateChanged(authState: AuthState) {
        when (authState) {
            is AuthState.Loading -> _state.value = HomeUiState.Loading

            is AuthState.SignedOut -> _state.value = HomeUiState.SignedOut

            is AuthState.SignedIn -> {
                _state.value = HomeUiState.SignedIn(authState.uid, HomeUiState.RegistrationStatus.Registering)
                val result = deviceRegistrar.registerOrUpdate(uid = authState.uid)
                val status = when (result) {
                    is ApiResult.Success -> HomeUiState.RegistrationStatus.Registered
                    is ApiResult.Failure -> HomeUiState.RegistrationStatus.Failed
                }
                _state.value = HomeUiState.SignedIn(authState.uid, status)
            }
        }
    }
}
