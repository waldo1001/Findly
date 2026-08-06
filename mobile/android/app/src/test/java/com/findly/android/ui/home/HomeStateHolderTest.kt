package com.findly.android.ui.home

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
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [HomeStateHolder] is pure Kotlin (no `androidx.lifecycle.ViewModel`), so its state-transition
 * logic is tested directly with a `backgroundScope` + fakes — no Robolectric, no emulator
 * (specs/003-android-client.md §14, §16).
 *
 * A24 (001 §1.5.3, §4.1; specs/003 §12.2): `POST /devices` is not one of the four
 * profile-bootstrap endpoints, so a signed-in caller with no `Users` profile row yet must never
 * reach `deviceRegistrar.registerOrUpdate` — the same "probe `families/me` first, only
 * `PROFILE_NOT_FOUND` short-circuits" idiom [com.findly.android.ui.groups.GroupsListStateHolder]
 * settled on for A21.
 */
class HomeStateHolderTest {

    private fun registrar(fakeApi: FakeDevicesApi) = DeviceRegistrar(
        devicesApi = fakeApi,
        deviceIdProvider = DeviceIdProvider(InMemoryDeviceIdStore()),
        deviceInfoProvider = FakeDeviceInfoProvider(),
    )

    @Test
    fun `signed-out auth state yields SignedOut`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedOut)
        val holder = HomeStateHolder(
            authProvider,
            registrar(FakeDevicesApi()),
            FakePushTokenProvider(),
            FakeFamilyApi(),
            backgroundScope,
        )

        runCurrent()

        assertEquals(HomeUiState.SignedOut, holder.state.value)
    }

    @Test
    fun `signed-in auth state probes for a profile, then registers the device and reaches Registered`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
        val fakeApi = FakeDevicesApi()
        val familyApi = FakeFamilyApi() // default getMyFamilyResult is a Success
        val holder = HomeStateHolder(
            authProvider,
            registrar(fakeApi),
            FakePushTokenProvider(),
            familyApi,
            backgroundScope,
        )

        runCurrent()

        val state = holder.state.value
        assertTrue(state is HomeUiState.SignedIn)
        state as HomeUiState.SignedIn
        assertEquals("uid-1", state.uid)
        assertEquals(HomeUiState.RegistrationStatus.Registered, state.registration)
        assertEquals(1, fakeApi.registerDeviceCalls.size)
        assertEquals(1, familyApi.getMyFamilyCallCount)
    }

    @Test
    fun `registration failure surfaces Failed without crashing the state machine`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
        val fakeApi = FakeDevicesApi().apply {
            resultToReturn = ApiResult.Failure(ApiError.InternalError("boom", null))
        }
        val holder = HomeStateHolder(
            authProvider,
            registrar(fakeApi),
            FakePushTokenProvider(),
            FakeFamilyApi(),
            backgroundScope,
        )

        runCurrent()

        val state = holder.state.value
        assertTrue(state is HomeUiState.SignedIn)
        assertEquals(HomeUiState.RegistrationStatus.Failed, (state as HomeUiState.SignedIn).registration)
    }

    @Test
    fun `initial state is Loading before the auth flow has been collected`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedOut)
        val holder = HomeStateHolder(
            authProvider,
            registrar(FakeDevicesApi()),
            FakePushTokenProvider(),
            FakeFamilyApi(),
            backgroundScope,
        )

        // Before advancing the dispatcher, the collector hasn't run yet.
        assertEquals(HomeUiState.Loading, holder.state.value)
    }

    @Test
    fun `signed-in registration carries the current FCM push token (000 O4, 001 §4_1)`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
        val fakeApi = FakeDevicesApi()
        val pushTokenProvider = FakePushTokenProvider(tokenToReturn = "fcm-token-abc")
        val holder = HomeStateHolder(authProvider, registrar(fakeApi), pushTokenProvider, FakeFamilyApi(), backgroundScope)

        runCurrent()

        assertEquals(1, fakeApi.registerDeviceCalls.size)
        assertEquals("fcm-token-abc", fakeApi.registerDeviceCalls.single().pushToken)
        assertEquals(1, pushTokenProvider.currentTokenCallCount)
        val state = holder.state.value
        assertTrue(state is HomeUiState.SignedIn)
        assertEquals(HomeUiState.RegistrationStatus.Registered, (state as HomeUiState.SignedIn).registration)
    }

    @Test
    fun `signed-in registration still succeeds when no push token is available yet`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
        val fakeApi = FakeDevicesApi()
        val pushTokenProvider = FakePushTokenProvider(tokenToReturn = null)
        val holder = HomeStateHolder(authProvider, registrar(fakeApi), pushTokenProvider, FakeFamilyApi(), backgroundScope)

        runCurrent()

        assertEquals(1, fakeApi.registerDeviceCalls.size)
        assertEquals(null, fakeApi.registerDeviceCalls.single().pushToken)
        val state = holder.state.value
        assertTrue(state is HomeUiState.SignedIn)
        assertEquals(HomeUiState.RegistrationStatus.Registered, (state as HomeUiState.SignedIn).registration)
    }

    @Test
    fun `PROFILE_NOT_FOUND on the probe yields ProfileNeeded and never attempts the doomed device registration`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
        val fakeApi = FakeDevicesApi()
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.ProfileNotFound("no profile", "r_1"))
        }
        val holder = HomeStateHolder(authProvider, registrar(fakeApi), FakePushTokenProvider(), familyApi, backgroundScope)

        runCurrent()

        assertEquals(HomeUiState.ProfileNeeded("uid-1"), holder.state.value)
        assertEquals(0, fakeApi.registerDeviceCalls.size)
    }

    @Test
    fun `FAMILY_NOT_FOUND on the probe still attempts registration (device endpoints work without a family)`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
        val fakeApi = FakeDevicesApi()
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.FamilyNotFound("no family", "r_1"))
        }
        val holder = HomeStateHolder(authProvider, registrar(fakeApi), FakePushTokenProvider(), familyApi, backgroundScope)

        runCurrent()

        val state = holder.state.value
        assertTrue(state is HomeUiState.SignedIn)
        assertEquals(HomeUiState.RegistrationStatus.Registered, (state as HomeUiState.SignedIn).registration)
        assertEquals(1, fakeApi.registerDeviceCalls.size)
    }

    @Test
    fun `an inconclusive probe failure fails open and still attempts registration rather than stranding a valid user`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
        val fakeApi = FakeDevicesApi()
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.NetworkFailure(RuntimeException("offline")))
        }
        val holder = HomeStateHolder(authProvider, registrar(fakeApi), FakePushTokenProvider(), familyApi, backgroundScope)

        runCurrent()

        val state = holder.state.value
        assertTrue(state is HomeUiState.SignedIn)
        assertEquals(HomeUiState.RegistrationStatus.Registered, (state as HomeUiState.SignedIn).registration)
        assertEquals(1, fakeApi.registerDeviceCalls.size)
    }

    @Test
    fun `retryRegistration re-probes and registers once a bootstrap path has created the profile`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
        val fakeApi = FakeDevicesApi()
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.ProfileNotFound("no profile", "r_1"))
        }
        val holder = HomeStateHolder(authProvider, registrar(fakeApi), FakePushTokenProvider(), familyApi, backgroundScope)

        runCurrent()
        assertEquals(HomeUiState.ProfileNeeded("uid-1"), holder.state.value)
        assertEquals(0, fakeApi.registerDeviceCalls.size)

        // A24 (specs/003 §12.2's ProfileNeeded first-run flow): one of the four bootstrap paths
        // off GroupsListScreen just created the profile — retryRegistration is the seam that path
        // calls instead of leaving the device unregistered until the app cold-starts.
        familyApi.getMyFamilyResult = ApiResult.Success(
            FamilyMeResponseDto(
                familyId = "fam_test",
                familyName = "Wauters",
                createdAt = "2026-08-06T00:00:00Z",
                me = CallerRoleDto("uid-1", "parent"),
                members = emptyList(),
            ),
            features = null,
        )
        holder.retryRegistration()
        runCurrent()

        val state = holder.state.value
        assertTrue(state is HomeUiState.SignedIn)
        assertEquals(HomeUiState.RegistrationStatus.Registered, (state as HomeUiState.SignedIn).registration)
        assertEquals(1, fakeApi.registerDeviceCalls.size)
        assertEquals(2, familyApi.getMyFamilyCallCount)
    }

    @Test
    fun `retryRegistration is a no-op when the caller was never signed in`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedOut)
        val fakeApi = FakeDevicesApi()
        val holder = HomeStateHolder(authProvider, registrar(fakeApi), FakePushTokenProvider(), FakeFamilyApi(), backgroundScope)

        runCurrent()
        holder.retryRegistration()
        runCurrent()

        assertEquals(HomeUiState.SignedOut, holder.state.value)
        assertEquals(0, fakeApi.registerDeviceCalls.size)
    }
}
