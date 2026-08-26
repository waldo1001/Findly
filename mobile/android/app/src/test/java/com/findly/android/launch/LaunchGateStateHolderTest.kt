package com.findly.android.launch

import com.findly.android.auth.AuthState
import com.findly.android.device.DeviceIdProvider
import com.findly.android.device.DeviceRegistrar
import com.findly.android.fakes.FakeAuthProvider
import com.findly.android.fakes.FakeDeviceInfoProvider
import com.findly.android.fakes.FakeDevicesApi
import com.findly.android.fakes.FakeFamilyApi
import com.findly.android.fakes.FakeLocalStateWiper
import com.findly.android.fakes.FakePushTokenProvider
import com.findly.android.fakes.InMemoryDeviceIdStore
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.CallerRoleDto
import com.findly.android.network.dto.FamilyMeResponseDto
import com.findly.android.network.dto.MemberDto
import com.findly.android.ui.onboarding.OnboardingVariant
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [LaunchGateStateHolder] is pure Kotlin (no `androidx.lifecycle.ViewModel`) — extracted from the
 * deleted `HomeStateHolder` (the retired `ui/home` package) (specs/010-app-shell-and-screen-ux.md §1.1, §1.2's "the
 * launch-gate logic Home used to own... moves to a pure, platform-agnostic launch component with
 * the same tests"). Tested directly with a `backgroundScope` + fakes — no Robolectric, no
 * emulator (specs/003-android-client.md §14, §16).
 *
 * The A21/A24 rules this carries forward unchanged: probe `families/me` before any device
 * registration; register unless the probe *confirms* `PROFILE_NOT_FOUND`; an inconclusive probe
 * failure fails open to the map; `retryRegistration` re-probes and registers once a bootstrap path
 * has completed. New in 010: a confirmed `FAMILY_NOT_FOUND` now routes to Onboarding (family-less)
 * instead of silently registering into a plain `Ready` state, and a successful probe's family/
 * caller data is cached into [LaunchUiState.FamilyHeader] for the drawer header (010 §1.2).
 */
class LaunchGateStateHolderTest {

    private fun registrar(fakeApi: FakeDevicesApi) = DeviceRegistrar(
        devicesApi = fakeApi,
        deviceIdProvider = DeviceIdProvider(InMemoryDeviceIdStore()),
        deviceInfoProvider = FakeDeviceInfoProvider(),
    )

    private fun familyMe(
        uid: String = "uid-1",
        role: String = "parent",
        familyName: String = "Wauters",
        members: List<MemberDto> = listOf(MemberDto(uid, role, "Eric", "2026-08-06T00:00:00Z")),
    ) = FamilyMeResponseDto(
        familyId = "fam_test",
        familyName = familyName,
        createdAt = "2026-08-06T00:00:00Z",
        me = CallerRoleDto(uid, role),
        members = members,
    )

    @Test
    fun `signed-out auth state yields SignedOut`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedOut)
        val holder = LaunchGateStateHolder(
            authProvider,
            registrar(FakeDevicesApi()),
            FakePushTokenProvider(),
            FakeFamilyApi(),
            FakeLocalStateWiper(),
            backgroundScope,
        )

        runCurrent()

        assertEquals(LaunchUiState.SignedOut, holder.state.value)
    }

    @Test
    fun `initial state is Loading before the auth flow has been collected`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedOut)
        val holder = LaunchGateStateHolder(
            authProvider,
            registrar(FakeDevicesApi()),
            FakePushTokenProvider(),
            FakeFamilyApi(),
            FakeLocalStateWiper(),
            backgroundScope,
        )

        assertEquals(LaunchUiState.Loading, holder.state.value)
    }

    @Test
    fun `signed-in with a confirmed profile and family probes, registers, and caches the drawer header`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
        val fakeApi = FakeDevicesApi()
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Success(familyMe(), features = null)
        }
        val holder = LaunchGateStateHolder(authProvider, registrar(fakeApi), FakePushTokenProvider(), familyApi, FakeLocalStateWiper(), backgroundScope)

        runCurrent()

        val state = holder.state.value
        assertTrue(state is LaunchUiState.Ready)
        state as LaunchUiState.Ready
        assertEquals("uid-1", state.uid)
        assertEquals(LaunchUiState.RegistrationStatus.Registered, state.registration)
        assertEquals("Wauters", state.familyHeader?.familyName)
        assertEquals("Eric", state.familyHeader?.callerDisplayName)
        assertTrue(state.familyHeader?.isParent == true)
        assertEquals(1, fakeApi.registerDeviceCalls.size)
        assertEquals(1, familyApi.getMyFamilyCallCount)
    }

    @Test
    fun `registration failure surfaces Failed without crashing the state machine`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
        val fakeApi = FakeDevicesApi().apply {
            resultToReturn = ApiResult.Failure(ApiError.InternalError("boom", null))
        }
        val holder = LaunchGateStateHolder(authProvider, registrar(fakeApi), FakePushTokenProvider(), FakeFamilyApi(), FakeLocalStateWiper(), backgroundScope)

        runCurrent()

        val state = holder.state.value
        assertTrue(state is LaunchUiState.Ready)
        assertEquals(LaunchUiState.RegistrationStatus.Failed, (state as LaunchUiState.Ready).registration)
    }

    @Test
    fun `PROFILE_NOT_FOUND on the probe routes to Onboarding profile-less and never attempts the doomed registration`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
        val fakeApi = FakeDevicesApi()
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.ProfileNotFound("no profile", "r_1"))
        }
        val holder = LaunchGateStateHolder(authProvider, registrar(fakeApi), FakePushTokenProvider(), familyApi, FakeLocalStateWiper(), backgroundScope)

        runCurrent()

        val state = holder.state.value
        assertTrue(state is LaunchUiState.Onboarding)
        assertEquals(OnboardingVariant.ProfileLess, (state as LaunchUiState.Onboarding).variant)
        assertEquals(0, fakeApi.registerDeviceCalls.size)
    }

    @Test
    fun `FAMILY_NOT_FOUND on the probe routes to Onboarding family-less but still registers the device`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
        val fakeApi = FakeDevicesApi()
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.FamilyNotFound("no family", "r_1"))
        }
        val holder = LaunchGateStateHolder(authProvider, registrar(fakeApi), FakePushTokenProvider(), familyApi, FakeLocalStateWiper(), backgroundScope)

        runCurrent()

        val state = holder.state.value
        assertTrue(state is LaunchUiState.Onboarding)
        assertEquals(OnboardingVariant.FamilyLess, (state as LaunchUiState.Onboarding).variant)
        // Device endpoints work without a family (001 §1.5.4) — the A24 rule is unchanged.
        assertEquals(1, fakeApi.registerDeviceCalls.size)
    }

    @Test
    fun `an inconclusive probe failure fails open to Ready and still attempts registration`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
        val fakeApi = FakeDevicesApi()
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.NetworkFailure(RuntimeException("offline")))
        }
        val holder = LaunchGateStateHolder(authProvider, registrar(fakeApi), FakePushTokenProvider(), familyApi, FakeLocalStateWiper(), backgroundScope)

        runCurrent()

        val state = holder.state.value
        assertTrue(state is LaunchUiState.Ready)
        state as LaunchUiState.Ready
        assertEquals(LaunchUiState.RegistrationStatus.Registered, state.registration)
        assertEquals(null, state.familyHeader)
        assertEquals(1, fakeApi.registerDeviceCalls.size)
    }

    /**
     * specs/010-app-shell-and-screen-ux.md §1.1 (amended, row A37): a CONFIRMED auth failure on the
     * probe is not an inconclusive one — it MUST route to Sign-in, clearing the local session, and
     * MUST NOT fail open to the map. Table-driven over all four confirmed auth codes (001 §10) so
     * parity across the set is visible in one place; each iteration gets fresh fakes so the
     * per-call-count assertions below aren't polluted by a previous iteration.
     */
    @Test
    fun `a confirmed auth failure on the probe routes to SignedOut, wipes the session, and never registers`() = runTest {
        val confirmedAuthErrors = listOf(
            ApiError.AuthMissingToken("no token", "r_1"),
            ApiError.AuthInvalidToken("bad signature", "r_2"),
            ApiError.AuthTokenExpired("expired", "r_3"),
            ApiError.AuthForbidden("forbidden", "r_4"),
        )

        for (error in confirmedAuthErrors) {
            val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
            val fakeApi = FakeDevicesApi()
            val localStateWiper = FakeLocalStateWiper()
            val familyApi = FakeFamilyApi().apply { getMyFamilyResult = ApiResult.Failure(error) }
            val holder = LaunchGateStateHolder(
                authProvider,
                registrar(fakeApi),
                FakePushTokenProvider(),
                familyApi,
                localStateWiper,
                backgroundScope,
            )

            runCurrent()

            assertEquals("$error routes to SignedOut", LaunchUiState.SignedOut, holder.state.value)
            assertEquals("$error must never attempt device registration", 0, fakeApi.registerDeviceCalls.size)
            assertEquals("$error must wipe exactly the caller's local state once", listOf("uid-1"), localStateWiper.wipeAllCalls)
            assertEquals("$error must sign out exactly once", 1, authProvider.signOutCallCount)
        }
    }

    /** Companion to the confirmed-auth-failure test above: a genuinely transient failure (no
     * decodable error code at all — 010 §1.1's amended distinguishing rule) MUST keep failing open
     * to the map, unchanged. [ApiError.NetworkFailure] and [ApiError.InternalError] both carry no
     * auth-code classification, so neither may be confused with a confirmed auth failure. */
    @Test
    fun `a transient probe failure still fails open to Ready and never signs out`() = runTest {
        val transientErrors = listOf(
            ApiError.NetworkFailure(RuntimeException("offline")),
            ApiError.InternalError("boom", "r_1"),
        )

        for (error in transientErrors) {
            val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
            val fakeApi = FakeDevicesApi()
            val localStateWiper = FakeLocalStateWiper()
            val familyApi = FakeFamilyApi().apply { getMyFamilyResult = ApiResult.Failure(error) }
            val holder = LaunchGateStateHolder(
                authProvider,
                registrar(fakeApi),
                FakePushTokenProvider(),
                familyApi,
                localStateWiper,
                backgroundScope,
            )

            runCurrent()

            assertTrue("$error should fail open to Ready", holder.state.value is LaunchUiState.Ready)
            assertEquals("$error should still attempt registration", 1, fakeApi.registerDeviceCalls.size)
            assertEquals("$error must not sign out", 0, authProvider.signOutCallCount)
            assertEquals("$error must not wipe local state", emptyList<String>(), localStateWiper.wipeAllCalls)
        }
    }

    @Test
    fun `signed-in registration carries the current FCM push token`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
        val fakeApi = FakeDevicesApi()
        val pushTokenProvider = FakePushTokenProvider(tokenToReturn = "fcm-token-abc")
        val holder = LaunchGateStateHolder(authProvider, registrar(fakeApi), pushTokenProvider, FakeFamilyApi(), FakeLocalStateWiper(), backgroundScope)

        runCurrent()

        assertEquals("fcm-token-abc", fakeApi.registerDeviceCalls.single().pushToken)
    }

    @Test
    fun `signed-in registration still succeeds when no push token is available yet`() = runTest {
        // A null push token at first launch is the normal case (FCM often hasn't produced one
        // yet), not an edge case — 001 §4.1 documents pushToken as OPTIONAL for exactly this
        // reason. Coverage-gap fix (review finding): every other registration-asserting test in
        // this suite uses either the default fake or an explicit non-null token, so this path was
        // exercised implicitly but never actually asserted.
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
        val fakeApi = FakeDevicesApi()
        val pushTokenProvider = FakePushTokenProvider(tokenToReturn = null)
        val holder = LaunchGateStateHolder(authProvider, registrar(fakeApi), pushTokenProvider, FakeFamilyApi(), FakeLocalStateWiper(), backgroundScope)

        runCurrent()

        assertEquals(1, fakeApi.registerDeviceCalls.size)
        assertEquals(null, fakeApi.registerDeviceCalls.single().pushToken)
        val state = holder.state.value
        assertTrue(state is LaunchUiState.Ready)
        assertEquals(LaunchUiState.RegistrationStatus.Registered, (state as LaunchUiState.Ready).registration)
    }

    @Test
    fun `retryRegistration re-probes and registers once a bootstrap path has created the profile`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
        val fakeApi = FakeDevicesApi()
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.ProfileNotFound("no profile", "r_1"))
        }
        val holder = LaunchGateStateHolder(authProvider, registrar(fakeApi), FakePushTokenProvider(), familyApi, FakeLocalStateWiper(), backgroundScope)

        runCurrent()
        assertTrue(holder.state.value is LaunchUiState.Onboarding)
        assertEquals(0, fakeApi.registerDeviceCalls.size)

        familyApi.getMyFamilyResult = ApiResult.Success(familyMe(), features = null)
        holder.retryRegistration()
        runCurrent()

        val state = holder.state.value
        assertTrue(state is LaunchUiState.Ready)
        assertEquals(LaunchUiState.RegistrationStatus.Registered, (state as LaunchUiState.Ready).registration)
        assertEquals(1, fakeApi.registerDeviceCalls.size)
        assertEquals(2, familyApi.getMyFamilyCallCount)
    }

    @Test
    fun `retryRegistration re-probes from Ready too (a family-less user creating only a group)`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
        val fakeApi = FakeDevicesApi()
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.FamilyNotFound("no family", "r_1"))
        }
        val holder = LaunchGateStateHolder(authProvider, registrar(fakeApi), FakePushTokenProvider(), familyApi, FakeLocalStateWiper(), backgroundScope)
        runCurrent()
        assertTrue(holder.state.value is LaunchUiState.Onboarding)

        holder.retryRegistration()
        runCurrent()

        assertEquals(2, familyApi.getMyFamilyCallCount)
    }

    @Test
    fun `retryRegistration is a no-op when the caller was never signed in`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedOut)
        val fakeApi = FakeDevicesApi()
        val holder = LaunchGateStateHolder(authProvider, registrar(fakeApi), FakePushTokenProvider(), FakeFamilyApi(), FakeLocalStateWiper(), backgroundScope)

        runCurrent()
        holder.retryRegistration()
        runCurrent()

        assertEquals(LaunchUiState.SignedOut, holder.state.value)
        assertEquals(0, fakeApi.registerDeviceCalls.size)
    }
}
