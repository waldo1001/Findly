package com.findly.android.location

import android.app.PendingIntent
import android.location.Location
import android.os.Looper
import com.google.android.gms.common.api.Api
import com.google.android.gms.common.api.internal.ApiKey
import com.google.android.gms.location.CurrentLocationRequest
import com.google.android.gms.location.DeviceOrientationListener
import com.google.android.gms.location.DeviceOrientationRequest
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LastLocationRequest
import com.google.android.gms.location.LocationAvailability
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationListener
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.tasks.CancellationToken
import com.google.android.gms.tasks.Task
import java.util.concurrent.Executor
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertThrows
import org.junit.Test

/**
 * Review round (finding 6): the seven `catch (e: CancellationException) { throw e }` rethrows this
 * sweep added shipped with no test — a bare `grep -rn CancellationException app/src/test` found one
 * comment and zero assertions. [FusedLocationCapturer.captureFix] is genuinely testable despite
 * being framework glue (its KDoc calls it "thin, untested Android-framework glue by design" for the
 * *behavioral* reasons a real GPS fix can't be exercised without a device/emulator) because
 * [FusedLocationProviderClient] is, unusually for a Play Services client, a plain **interface**
 * (`javap` confirms — no final class, no hidden constructor), so it can be faked here with no
 * mocking library the way every other `FakeXxx` in this package already fakes its own interface.
 *
 * Both fakes below throw [CancellationException] **synchronously** from inside the client call
 * itself (never wrapped in a real `Task`) — the exact "have the fake throw CancellationException"
 * method the review specified. [FusedLocationCapturer.captureFix]'s own two `catch (e: Exception)`
 * blocks (one around the fresh fetch, one around the cached fallback) used to map every failure,
 * cancellation included, to a silent `null` — exactly the class of bug specs/003-android-client.md
 * §3.1's second rule exists to catch: a `suspend fun` that absorbs cancellation instead of letting
 * the coroutine actually finish cancelled.
 */
class FusedLocationCapturerCancellationTest {

    private val fakeBatteryLevelProvider = BatteryLevelProvider { 50 }

    @Test
    fun `captureFix propagates cancellation from the fresh fetch rather than mapping it to null`() = runTest {
        val client = FakeFusedLocationProviderClient(
            currentLocationResult = { throw CancellationException("scope cancelled") },
        )
        val capturer = FusedLocationCapturer(client, fakeBatteryLevelProvider)

        assertThrows(CancellationException::class.java) {
            kotlinx.coroutines.runBlocking {
                capturer.captureFix(
                    accuracy = LocationAccuracyTier.BALANCED,
                    timeoutMillis = 1_000L,
                    maxCachedAgeMillis = 60_000L,
                )
            }
        }
    }

    @Test
    fun `captureFix propagates cancellation from the cached fallback rather than mapping it to null`() = runTest {
        val client = FakeFusedLocationProviderClient(
            // The fresh fetch resolves to null (e.g. timed out) so captureFix falls through to
            // fallbackToLastLocationOrNull, which is what actually calls getLastLocation.
            currentLocationResult = { throw NoOpTaskCancellation },
            lastLocationResult = { throw CancellationException("scope cancelled") },
        )
        val capturer = FusedLocationCapturer(client, fakeBatteryLevelProvider)

        assertThrows(CancellationException::class.java) {
            kotlinx.coroutines.runBlocking {
                capturer.captureFix(
                    accuracy = LocationAccuracyTier.BALANCED,
                    timeoutMillis = 1_000L,
                    maxCachedAgeMillis = 60_000L,
                )
            }
        }
    }
}

/** A plain, ordinary (non-cancellation) failure for the fresh-fetch branch of the second test above
 * — must NOT be a [CancellationException] itself, or it would trivially satisfy that test without
 * ever reaching the fallback path being exercised. */
private object NoOpTaskCancellation : RuntimeException("fresh fetch failed (not cancellation)")

/** [FusedLocationProviderClient] is an interface (confirmed via `javap` against
 * play-services-location:21.3.0 — no final class, all members abstract), so unlike
 * [com.google.firebase.auth.FirebaseAuth] or `android.app.Service`, it can be faked directly with
 * no mocking library, matching every other `FakeXxx` in this test source set. Every method besides
 * the two this test drives is unreachable from [FusedLocationCapturer.captureFix] and throws if
 * ever called, so an accidental new dependency on one fails loudly instead of silently no-opping. */
private class FakeFusedLocationProviderClient(
    private val currentLocationResult: () -> Task<Location> = { notImplemented() },
    private val lastLocationResult: () -> Task<Location> = { notImplemented() },
) : FusedLocationProviderClient {
    override fun getApiKey(): ApiKey<Api.ApiOptions.NoOptions> = notImplemented()
    override fun getLastLocation(): Task<Location> = lastLocationResult()
    override fun getLastLocation(request: LastLocationRequest): Task<Location> = notImplemented()
    override fun getCurrentLocation(priority: Int, token: CancellationToken?): Task<Location> = notImplemented()
    override fun getCurrentLocation(request: CurrentLocationRequest, token: CancellationToken?): Task<Location> =
        currentLocationResult()
    override fun getLocationAvailability(): Task<LocationAvailability> = notImplemented()
    override fun requestLocationUpdates(
        request: LocationRequest,
        executor: Executor,
        listener: LocationListener,
    ): Task<Void> = notImplemented()
    override fun requestLocationUpdates(
        request: LocationRequest,
        listener: LocationListener,
        looper: Looper?,
    ): Task<Void> = notImplemented()
    override fun requestLocationUpdates(
        request: LocationRequest,
        callback: LocationCallback,
        looper: Looper?,
    ): Task<Void> = notImplemented()
    override fun requestLocationUpdates(
        request: LocationRequest,
        executor: Executor,
        callback: LocationCallback,
    ): Task<Void> = notImplemented()
    override fun requestLocationUpdates(request: LocationRequest, pendingIntent: PendingIntent): Task<Void> =
        notImplemented()
    override fun removeLocationUpdates(listener: LocationListener): Task<Void> = notImplemented()
    override fun removeLocationUpdates(callback: LocationCallback): Task<Void> = notImplemented()
    override fun removeLocationUpdates(pendingIntent: PendingIntent): Task<Void> = notImplemented()
    override fun flushLocations(): Task<Void> = notImplemented()
    override fun setMockMode(mockMode: Boolean): Task<Void> = notImplemented()
    override fun setMockLocation(location: Location): Task<Void> = notImplemented()
    override fun requestDeviceOrientationUpdates(
        request: DeviceOrientationRequest,
        executor: Executor,
        listener: DeviceOrientationListener,
    ): Task<Void> = notImplemented()
    override fun requestDeviceOrientationUpdates(
        request: DeviceOrientationRequest,
        listener: DeviceOrientationListener,
        looper: Looper?,
    ): Task<Void> = notImplemented()
    override fun removeDeviceOrientationUpdates(listener: DeviceOrientationListener): Task<Void> = notImplemented()
}

private fun notImplemented(): Nothing = throw UnsupportedOperationException("not needed in this test")
