package com.findly.android.launch

import com.findly.android.auth.AuthState
import com.findly.android.auth.IdTokenException
import com.findly.android.device.DeviceIdProvider
import com.findly.android.device.DeviceRegistrar
import com.findly.android.fakes.FakeAuthProvider
import com.findly.android.fakes.FakeDeviceInfoProvider
import com.findly.android.fakes.FakeDevicesApi
import com.findly.android.fakes.FakeLocalStateWiper
import com.findly.android.fakes.FakePushTokenProvider
import com.findly.android.fakes.InMemoryDeviceIdStore
import com.findly.android.network.FindlyApiClient
import com.findly.android.network.RetrofitFactory
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * specs/003-android-client.md §6.5 rule 3 meets specs/010-app-shell-and-screen-ux.md §1.1 (row
 * A37), through the **real** `AuthInterceptor` → `FindlyApiClient` stack rather than a scripted
 * `FamilyApi` fake: the cold-start probe of a phone whose cached Firebase user was deleted (the
 * 2026-10-05 Pixel crash) must land on Sign-in with the session wiped, never on the Family Map and
 * never with a device registration — while an offline device with a perfectly good session keeps
 * failing open.
 */
class LaunchGateUserInvalidTest {

    private lateinit var server: MockWebServer

    @Before
    fun setUp() {
        server = MockWebServer().apply { start() }
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    private fun gate(
        authProvider: FakeAuthProvider,
        devicesApi: FakeDevicesApi,
        wiper: FakeLocalStateWiper,
        scope: CoroutineScope,
    ): LaunchGateStateHolder {
        val client = FindlyApiClient(RetrofitFactory.create(server.url("/").toString(), authProvider), authProvider)
        return LaunchGateStateHolder(
            authProvider,
            DeviceRegistrar(devicesApi, DeviceIdProvider(InMemoryDeviceIdStore()), FakeDeviceInfoProvider()),
            FakePushTokenProvider(),
            client,
            wiper,
            scope,
        )
    }

    @Test
    fun `a cached session for a deleted Firebase user lands on SignedOut, wipes the session, and never registers`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1")).apply {
            tokenFailure = IdTokenException.UserInvalid(IllegalStateException("There is no user record"))
        }
        val devicesApi = FakeDevicesApi()
        val wiper = FakeLocalStateWiper()

        val holder = gate(authProvider, devicesApi, wiper, backgroundScope)
        val resolved = holder.state.first { it != LaunchUiState.Loading }

        assertEquals(LaunchUiState.SignedOut, resolved)
        assertEquals("must never fail open to the map", 0, devicesApi.registerDeviceCalls.size)
        assertEquals("the local session is wiped for the deleted user", listOf("uid-1"), wiper.wipeAllCalls)
        assertEquals(AuthState.SignedOut, authProvider.authState.value)
        assertEquals("no request reaches the backend", 0, server.requestCount)
    }

    @Test
    fun `an offline device with a valid session still fails open to Ready and is not signed out`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1")).apply {
            tokenFailure = IdTokenException.Transient(IOException("offline"))
        }
        val devicesApi = FakeDevicesApi()
        val wiper = FakeLocalStateWiper()

        val holder = gate(authProvider, devicesApi, wiper, backgroundScope)
        val resolved = holder.state.first { it != LaunchUiState.Loading }

        assertTrue("was $resolved", resolved is LaunchUiState.Ready)
        assertEquals(0, authProvider.signOutCallCount)
        assertEquals(emptyList<String>(), wiper.wipeAllCalls)
    }
}
