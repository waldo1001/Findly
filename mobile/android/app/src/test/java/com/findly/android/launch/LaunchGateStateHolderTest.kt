package com.findly.android.launch

import com.findly.android.auth.AuthState
import com.findly.android.device.DeviceIdProvider
import com.findly.android.device.DeviceRegistrar
import com.findly.android.fakes.FakeAuthProvider
import com.findly.android.fakes.FakeDeviceInfoProvider
import com.findly.android.fakes.FakeDevicesApi
import com.findly.android.fakes.FakeFamilyApi
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
        val holder = LaunchGateStateHolder(authProvider, registrar(fakeApi), FakePushTokenProvider(), familyApi, backgroundScope)

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
        val holder = LaunchGateStateHolder(authProvider, registrar(fakeApi), FakePushTokenProvider(), FakeFamilyApi(), backgroundScope)

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
        val holder = LaunchGateStateHolder(authProvider, registrar(fakeApi), FakePushTokenProvider(), familyApi, backgroundScope)

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
        val holder = LaunchGateStateHolder(authProvider, registrar(fakeApi), FakePushTokenProvider(), familyApi, backgroundScope)

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
        val holder = LaunchGateStateHolder(authProvider, registrar(fakeApi), FakePushTokenProvider(), familyApi, backgroundScope)

        runCurrent()

        val state = holder.state.value
        assertTrue(state is LaunchUiState.Ready)
        state as LaunchUiState.Ready
        assertEquals(LaunchUiState.RegistrationStatus.Registered, state.registration)
        assertEquals(null, state.familyHeader)
        assertEquals(1, fakeApi.registerDeviceCalls.size)
    }

    @Test
    fun `signed-in registration carries the current FCM push token`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
        val fakeApi = FakeDevicesApi()
        val pushTokenProvider = FakePushTokenProvider(tokenToReturn = "fcm-token-abc")
        val holder = LaunchGateStateHolder(authProvider, registrar(fakeApi), pushTokenProvider, FakeFamilyApi(), backgroundScope)

        runCurrent()

        assertEquals("fcm-token-abc", fakeApi.registerDeviceCalls.single().pushToken)
    }

    @Test
    fun `retryRegistration re-probes and registers once a bootstrap path has created the profile`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
        val fakeApi = FakeDevicesApi()
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.ProfileNotFound("no profile", "r_1"))
        }
        val holder = LaunchGateStateHolder(authProvider, registrar(fakeApi), FakePushTokenProvider(), familyApi, backgroundScope)

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
        val holder = LaunchGateStateHolder(authProvider, registrar(fakeApi), FakePushTokenProvider(), familyApi, backgroundScope)
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
        val holder = LaunchGateStateHolder(authProvider, registrar(fakeApi), FakePushTokenProvider(), FakeFamilyApi(), backgroundScope)

        runCurrent()
        holder.retryRegistration()
        runCurrent()

        assertEquals(LaunchUiState.SignedOut, holder.state.value)
        assertEquals(0, fakeApi.registerDeviceCalls.size)
    }
}
