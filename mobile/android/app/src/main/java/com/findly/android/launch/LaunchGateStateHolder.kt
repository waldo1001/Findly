package com.findly.android.launch

import com.findly.android.auth.AuthProvider
import com.findly.android.auth.AuthState
import com.findly.android.device.DeviceRegistrar
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.FamilyMeResponseDto
import com.findly.android.network.ports.FamilyApi
import com.findly.android.push.PushTokenProvider
import com.findly.android.ui.onboarding.OnboardingVariant
import com.findly.android.ui.settings.LocalStateWiper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * The launch-gate's pure state machine (specs/010-app-shell-and-screen-ux.md §1.1) — extracted
 * from the deleted `HomeStateHolder` (the retired `ui/home` package) (010 §1.2: "the launch-gate logic Home used to
 * own (probe → register → route) moves to a pure, platform-agnostic launch component with the
 * same tests"). Constructor-injected [CoroutineScope] so tests supply a `TestScope`/
 * `backgroundScope` — no `androidx.lifecycle.ViewModel` dependency, no `android.*` import.
 * [LaunchGateViewModel] is a thin wrapper that owns one of these using `viewModelScope`.
 *
 * On cold start (010 §1.1's table): not signed in → [LaunchUiState.SignedOut] (the caller routes
 * to Sign-in); signed in → probe `GET /families/me` **before any device registration**:
 * - a confirmed `404 PROFILE_NOT_FOUND` → [LaunchUiState.Onboarding] (profile-less) — `POST
 *   /devices` is not one of the four 001 §1.5.3 bootstrap endpoints, so it is never attempted for
 *   a caller with no profile at all (the A24 rule, carried forward unchanged).
 * - a confirmed `404 FAMILY_NOT_FOUND` → [LaunchUiState.Onboarding] (family-less) — new in 010;
 *   device registration still proceeds (device endpoints work without a family, 001 §1.5.4).
 * - a **confirmed** `AUTH_MISSING_TOKEN`/`AUTH_INVALID_TOKEN`/`AUTH_TOKEN_EXPIRED`/`AUTH_FORBIDDEN`
 *   (010 §1.1, amended by row A37) → wipes local state via [localStateWiper], signs out, and lands
 *   on [LaunchUiState.SignedOut] — device registration is **never** attempted. This is NOT the
 *   fails-open case: the backend has confirmed the caller is unauthorized, so rendering the app
 *   shell would just 401 every screen individually. Distinguishing this from a genuinely
 *   *inconclusive* 401 (below) is by typed error code, never HTTP status alone — see
 *   [isConfirmedAuthFailure].
 * - anything else (a genuine `Success`, or an *inconclusive* failure — timeout, 5xx, or a 401 that
 *   arrived with no decodable error code at all) → registers and lands on [LaunchUiState.Ready]. A
 *   blip on the probe MUST NOT strand a valid user in onboarding (010 §1.1) — this is the "fails
 *   open" rule.
 *
 * A successful probe's family/caller data is cached into [LaunchUiState.FamilyHeader] so the 010
 * §1.2 drawer header never needs a network call of its own.
 *
 * [retryRegistration] is the seam [com.findly.android.ui.nav.FindlyNavHost] calls after any of the
 * 010 §2.2 Onboarding bootstrap paths completes, so the device is registered — and the caller
 * routed onward — immediately rather than only on the next cold start (the A24 rule).
 */
class LaunchGateStateHolder(
    private val authProvider: AuthProvider,
    private val deviceRegistrar: DeviceRegistrar,
    private val pushTokenProvider: PushTokenProvider,
    private val familyApi: FamilyApi,
    private val localStateWiper: LocalStateWiper,
    private val scope: CoroutineScope,
) {
    private val _state = MutableStateFlow<LaunchUiState>(LaunchUiState.Loading)
    val state: StateFlow<LaunchUiState> = _state.asStateFlow()

    init {
        scope.launch {
            authProvider.authState.collect { authState -> onAuthStateChanged(authState) }
        }
    }

    private suspend fun onAuthStateChanged(authState: AuthState) {
        when (authState) {
            is AuthState.Loading -> _state.value = LaunchUiState.Loading
            is AuthState.SignedOut -> _state.value = LaunchUiState.SignedOut
            is AuthState.SignedIn -> resolve(authState.uid)
        }
    }

    private suspend fun resolve(uid: String) {
        _state.value = LaunchUiState.Loading

        val probe = familyApi.getMyFamily()
        if (probe is ApiResult.Failure && probe.error is ApiError.ProfileNotFound) {
            _state.value = LaunchUiState.Onboarding(uid, OnboardingVariant.ProfileLess)
            return
        }

        // specs/010-app-shell-and-screen-ux.md §1.1 (amended, row A37): a CONFIRMED auth failure
        // is not an inconclusive probe — it MUST route to Sign-in, clearing the local session, and
        // MUST NOT fail open to the map. Reuses the exact same wipe-then-sign-out shape every other
        // session-ending path in this codebase already uses (e.g. `PrivacyStateHolder`'s account
        // deletion) rather than inventing a second one (I43).
        if (probe is ApiResult.Failure && probe.error.isConfirmedAuthFailure()) {
            localStateWiper.wipeAll(uid)
            authProvider.signOut()
            _state.value = LaunchUiState.SignedOut
            return
        }

        val familyConfirmedMissing = probe is ApiResult.Failure && probe.error is ApiError.FamilyNotFound

        val pushToken = pushTokenProvider.currentToken()
        val registrationResult = deviceRegistrar.registerOrUpdate(uid = uid, pushToken = pushToken)

        _state.value = if (familyConfirmedMissing) {
            LaunchUiState.Onboarding(uid, OnboardingVariant.FamilyLess)
        } else {
            val status = when (registrationResult) {
                is ApiResult.Success -> LaunchUiState.RegistrationStatus.Registered
                is ApiResult.Failure -> LaunchUiState.RegistrationStatus.Failed
            }
            LaunchUiState.Ready(uid, status, familyHeaderFrom(probe))
        }
    }

    private fun familyHeaderFrom(probe: ApiResult<FamilyMeResponseDto>): LaunchUiState.FamilyHeader? {
        val data = (probe as? ApiResult.Success)?.data ?: return null
        val me = data.members.find { it.userId == data.me.userId }
        return LaunchUiState.FamilyHeader(
            familyName = data.familyName,
            callerDisplayName = me?.displayName.orEmpty(),
            isParent = data.me.role == "parent",
        )
    }

    /** Called after any of the 010 §2.2 Onboarding bootstrap paths (create family, accept invite,
     * create group, join group) completes — re-probes and registers immediately rather than
     * leaving the device unregistered/the caller stuck on a stale routing decision until the app
     * cold-starts. A no-op if the caller was never signed in (nothing pending to retry). */
    fun retryRegistration() {
        val uid = when (val current = _state.value) {
            is LaunchUiState.Onboarding -> current.uid
            is LaunchUiState.Ready -> current.uid
            else -> return
        }
        scope.launch { resolve(uid) }
    }
}

/**
 * specs/010-app-shell-and-screen-ux.md §1.1 (amended, row A37) — the four confirmed-auth-failure
 * codes of 001-api-contract.md §10 that MUST route the launch probe to Sign-in rather than fail
 * open: the backend has told us the caller is unauthorized, which is categorically different from
 * an *inconclusive* probe (timeout, 5xx, or a 401/403 that arrived with no decodable error code at
 * all). [ApiError.NetworkFailure] and every other `ApiError` subtype are deliberately excluded —
 * they stay inconclusive and keep failing open, unchanged.
 */
private fun ApiError.isConfirmedAuthFailure(): Boolean = when (this) {
    is ApiError.AuthMissingToken,
    is ApiError.AuthInvalidToken,
    is ApiError.AuthTokenExpired,
    is ApiError.AuthForbidden,
    -> true
    else -> false
}
