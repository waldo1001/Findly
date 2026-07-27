package com.findly.android.ui.home

import com.findly.android.auth.AuthProvider
import com.findly.android.auth.AuthState
import com.findly.android.device.DeviceRegistrar
import com.findly.android.network.ApiResult
import com.findly.android.push.PushTokenProvider
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
 *
 * [pushTokenProvider] closes the 000 §O4 / 001 §4.1 first-sign-in gap found in code review: on a
 * device's very first sign-in, FCM can produce a push token before or during OTP entry, while
 * `AppContainer`'s `PushTokenProvider.addRefreshListener` callback still silently drops it (no
 * `uid` yet). Fetching [PushTokenProvider.currentToken] synchronously here, right before the
 * first [DeviceRegistrar.registerOrUpdate] call, closes that window by reading whatever FCM
 * currently has instead of relying solely on that passive listener. A `null` result (FCM hasn't
 * produced a token yet, or the fetch failed) is an accepted, spec'd state (001 §4.1: `pushToken`
 * is OPTIONAL) — registration still proceeds, and the existing refresh-listener path picks up any
 * later token once the user is actually signed in.
 */
class HomeStateHolder(
    private val authProvider: AuthProvider,
    private val deviceRegistrar: DeviceRegistrar,
    private val pushTokenProvider: PushTokenProvider,
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
                val pushToken = pushTokenProvider.currentToken()
                val result = deviceRegistrar.registerOrUpdate(uid = authState.uid, pushToken = pushToken)
                val status = when (result) {
                    is ApiResult.Success -> HomeUiState.RegistrationStatus.Registered
                    is ApiResult.Failure -> HomeUiState.RegistrationStatus.Failed
                }
                _state.value = HomeUiState.SignedIn(authState.uid, status)
            }
        }
    }
}
