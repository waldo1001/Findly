package com.findly.android.ui.home

import com.findly.android.auth.AuthState
import com.findly.android.device.DeviceIdProvider
import com.findly.android.device.DeviceRegistrar
import com.findly.android.fakes.FakeAuthProvider
import com.findly.android.fakes.FakeDeviceInfoProvider
import com.findly.android.fakes.FakeDevicesApi
import com.findly.android.fakes.FakePushTokenProvider
import com.findly.android.fakes.InMemoryDeviceIdStore
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [HomeStateHolder] is pure Kotlin (no `androidx.lifecycle.ViewModel`), so its state-transition
 * logic is tested directly with a `backgroundScope` + fakes — no Robolectric, no emulator
 * (specs/003-android-client.md §14, §16).
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
            backgroundScope,
        )

        runCurrent()

        assertEquals(HomeUiState.SignedOut, holder.state.value)
    }

    @Test
    fun `signed-in auth state registers the device and reaches Registered`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
        val fakeApi = FakeDevicesApi()
        val holder = HomeStateHolder(
            authProvider,
            registrar(fakeApi),
            FakePushTokenProvider(),
            backgroundScope,
        )

        runCurrent()

        val state = holder.state.value
        assertTrue(state is HomeUiState.SignedIn)
        state as HomeUiState.SignedIn
        assertEquals("uid-1", state.uid)
        assertEquals(HomeUiState.RegistrationStatus.Registered, state.registration)
        assertEquals(1, fakeApi.registerDeviceCalls.size)
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
        val holder = HomeStateHolder(authProvider, registrar(fakeApi), pushTokenProvider, backgroundScope)

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
        val holder = HomeStateHolder(authProvider, registrar(fakeApi), pushTokenProvider, backgroundScope)

        runCurrent()

        assertEquals(1, fakeApi.registerDeviceCalls.size)
        assertEquals(null, fakeApi.registerDeviceCalls.single().pushToken)
        val state = holder.state.value
        assertTrue(state is HomeUiState.SignedIn)
        assertEquals(HomeUiState.RegistrationStatus.Registered, (state as HomeUiState.SignedIn).registration)
    }
}
