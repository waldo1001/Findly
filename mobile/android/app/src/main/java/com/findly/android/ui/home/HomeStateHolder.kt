package com.findly.android.ui.home

import com.findly.android.auth.AuthProvider
import com.findly.android.auth.AuthState
import com.findly.android.device.DeviceRegistrar
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.ports.FamilyApi
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
 *
 * **A24** (001 §1.5.3, §4.1): `POST /devices` is not one of the four profile-bootstrap endpoints
 * (`POST /families`/`/invites/accept`/`/groups`/`/groups/join`), so registering unconditionally on
 * `SignedIn` doomed every brand-new user's first screen to a 404 that read as a network error. Now
 * probes `GET /families/me` first — the exact idiom
 * [com.findly.android.ui.groups.GroupsListStateHolder.refresh] settled on for A21: only a
 * confirmed `PROFILE_NOT_FOUND` short-circuits into [HomeUiState.ProfileNeeded]; any other outcome
 * (a genuine `Success`, `FAMILY_NOT_FOUND` — device endpoints work without a family, 001 §1.5.4 —
 * or an inconclusive failure like a timeout) falls through to registration, so a transient probe
 * blip can never strand an already-onboarded user. [retryRegistration] is the seam
 * [com.findly.android.ui.nav.FindlyNavHost] calls when any of the four bootstrap paths off
 * `GroupsListScreen`'s `ProfileNeeded` state (specs/003 §12.2) completes, so the device is
 * registered immediately rather than only on the next cold start.
 */
class HomeStateHolder(
    private val authProvider: AuthProvider,
    private val deviceRegistrar: DeviceRegistrar,
    private val pushTokenProvider: PushTokenProvider,
    private val familyApi: FamilyApi,
    private val scope: CoroutineScope,
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

            is AuthState.SignedIn -> attemptRegistration(authState.uid)
        }
    }

    private suspend fun attemptRegistration(uid: String) {
        _state.value = HomeUiState.SignedIn(uid, HomeUiState.RegistrationStatus.Registering)

        // 001 §1.5.3/§4.1: a profile-less caller's POST /devices is doomed to 404
        // PROFILE_NOT_FOUND, so never attempt it — only a confirmed PROFILE_NOT_FOUND short-
        // circuits; any other outcome (success, FAMILY_NOT_FOUND, or an inconclusive failure)
        // falls through and registers, mirroring GroupsListStateHolder.refresh() (A21).
        val profileProbe = familyApi.getMyFamily()
        if (profileProbe is ApiResult.Failure && profileProbe.error is ApiError.ProfileNotFound) {
            _state.value = HomeUiState.ProfileNeeded(uid)
            return
        }

        val pushToken = pushTokenProvider.currentToken()
        val result = deviceRegistrar.registerOrUpdate(uid = uid, pushToken = pushToken)
        val status = when (result) {
            is ApiResult.Success -> HomeUiState.RegistrationStatus.Registered
            is ApiResult.Failure -> HomeUiState.RegistrationStatus.Failed
        }
        _state.value = HomeUiState.SignedIn(uid, status)
    }

    /** Called after any of the four 001 §1.5.3 profile-bootstrap paths (create family, accept
     * invite, create group, join group) completes off `GroupsListScreen`'s `ProfileNeeded` state
     * (specs/003 §12.2, A21) — re-probes and registers immediately rather than leaving the device
     * unregistered until the app cold-starts and re-observes `SignedIn`. A no-op if the caller was
     * never signed in (nothing pending to retry). */
    fun retryRegistration() {
        val uid = when (val current = _state.value) {
            is HomeUiState.ProfileNeeded -> current.uid
            is HomeUiState.SignedIn -> current.uid
            else -> return
        }
        scope.launch { attemptRegistration(uid) }
    }
}
