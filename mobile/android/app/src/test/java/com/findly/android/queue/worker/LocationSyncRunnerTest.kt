package com.findly.android.queue.worker

import com.findly.android.fakes.FakeGeofenceApi
import com.findly.android.fakes.FakeGeofenceRegistrar
import com.findly.android.fakes.FakeGeofenceRegistry
import com.findly.android.fakes.FakeLocationCapturer
import com.findly.android.fakes.FakeLocationsApi
import com.findly.android.fakes.FakeSyncScheduler
import com.findly.android.fakes.InMemoryDeviceSettingsStateStore
import com.findly.android.fakes.InMemoryGeofenceConfigStateStore
import com.findly.android.fakes.InMemoryLastCaptureDateStore
import com.findly.android.fakes.defaultFeatures
import com.findly.android.location.CapturedFix
import com.findly.android.location.FixCaptureCoordinator
import com.findly.android.location.LocationAccuracyTier
import com.findly.android.location.settings.DeviceSettingsCoordinator
import com.findly.android.location.settings.GeofenceConfigSyncCoordinator
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.DeviceSettingsSnapshot
import com.findly.android.network.dto.DeviceSettingsDto
import com.findly.android.network.dto.GeofenceEventsResponseDto
import com.findly.android.network.dto.ReportLocationsResponseDto
import com.findly.android.queue.FixSource
import com.findly.android.queue.GeofenceEventSyncCoordinator
import com.findly.android.queue.InMemoryFixQueueStore
import com.findly.android.queue.InMemoryGeofenceEventQueueStore
import com.findly.android.queue.LocationSyncCoordinator
import com.findly.android.queue.QueuedGeofenceEvent
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** [LocationSyncRunner] end to end against fakes — specs/009-device-runtime.md §3.1/§3.3/§6.3/§9's
 * "one periodic run" behavior, without WorkManager or a foreground service in the picture. */
class LocationSyncRunnerTest {

    private val today = LocalDate.of(2026, 7, 19)
    private val fix = CapturedFix(lat = 51.0, lon = 3.7, accuracyM = 10.0, recordedAt = "2026-07-19T09:00:00Z", batteryPct = 80)

    private class Harness(
        syncIntervalMinutes: Int = 15,
        lastCaptureDate: LocalDate? = null,
        capturedFix: CapturedFix? = null,
        fixedToday: LocalDate = LocalDate.of(2026, 7, 19),
        initialDeviceSettings: DeviceSettingsSnapshot? = null,
    ) {
        val queueStore = InMemoryFixQueueStore()
        val locationsApi = FakeLocationsApi()
        val scheduler = FakeSyncScheduler()
        val geofenceRegistry = FakeGeofenceRegistry()
        val geofenceRegistrar = FakeGeofenceRegistrar()
        val geofenceApi = FakeGeofenceApi()
        val geofenceConfigSyncCoordinator = GeofenceConfigSyncCoordinator(
            geofenceApi,
            InMemoryGeofenceConfigStateStore(),
            geofenceRegistrar,
        )
        val settingsCoordinator = DeviceSettingsCoordinator(
            scheduler,
            geofenceRegistry,
            InMemoryDeviceSettingsStateStore(initialDeviceSettings),
        )
        val lastCaptureDateStore = InMemoryLastCaptureDateStore(lastCaptureDate)
        val capturer = FakeLocationCapturer(fixToReturn = capturedFix)
        val geofenceEventQueueStore = InMemoryGeofenceEventQueueStore()
        val geofenceEventSyncCoordinator = GeofenceEventSyncCoordinator(geofenceEventQueueStore, geofenceApi, deviceId = "device-1")
        val reRegisterCalls = mutableListOf<Unit>()
        val signedOutCalls = mutableListOf<Unit>()

        val runner = LocationSyncRunner(
            currentSyncIntervalMinutes = { syncIntervalMinutes },
            lastCaptureDateStore = lastCaptureDateStore,
            today = { fixedToday },
            captureCoordinator = FixCaptureCoordinator(
                capturer = capturer,
                queueStore = queueStore,
                pauseState = { false },
                permissionState = { true },
            ),
            syncCoordinator = LocationSyncCoordinator(queueStore, locationsApi, deviceId = "device-1"),
            geofenceEventSyncCoordinator = geofenceEventSyncCoordinator,
            settingsCoordinator = settingsCoordinator,
            geofenceConfigSyncCoordinator = geofenceConfigSyncCoordinator,
            onReRegisterDevice = { reRegisterCalls.add(Unit) },
            onSignedOut = { signedOutCalls.add(Unit) },
        )
    }

    @Test
    fun `captures one periodic fix and flushes it successfully`() = runTest {
        val harness = Harness(capturedFix = fix)
        harness.locationsApi.nextResult = ApiResult.Success(
            ReportLocationsResponseDto(
                accepted = 1,
                duplicates = 0,
                lastKnownUpdated = true,
                deviceSettings = DeviceSettingsDto(15, true),
                geofenceEtag = "\"0\"",
            ),
            features = null,
        )

        val result = harness.runner.runOnce()

        assertEquals(RunResult.Success, result)
        assertEquals(0, harness.queueStore.pendingCount()) // accepted and removed
        assertEquals(LocationAccuracyTier.BALANCED, harness.capturer.requestedTiers.single())
        val reportedFix = harness.locationsApi.reportLocationsCalls.single().third.single()
        assertEquals(FixSource.Periodic.toWireValue(), reportedFix.source)
    }

    @Test
    fun `a successful sync's mandatory settings piggyback is applied even though the device is not paused (001 §5_1, 009 §1)`() = runTest {
        val harness = Harness(capturedFix = fix, initialDeviceSettings = DeviceSettingsSnapshot(15, true))
        // The server echoes back a CHANGED interval on this otherwise-successful 2xx response -
        // no 403 TRACKING_PAUSED involved at all.
        harness.locationsApi.nextResult = ApiResult.Success(
            ReportLocationsResponseDto(
                accepted = 1,
                duplicates = 0,
                lastKnownUpdated = true,
                deviceSettings = DeviceSettingsDto(30, true),
                geofenceEtag = "\"0\"",
            ),
            features = null,
        )

        val result = harness.runner.runOnce()

        assertEquals(RunResult.Success, result)
        assertEquals(
            "the schedule must rebuild to the new interval even on a plain accepted flush",
            listOf(30),
            harness.scheduler.rescheduleCalls,
        )
        assertEquals(0, harness.scheduler.cancelAllCallCount)
    }

    @Test
    fun `once-a-day interval skips capture when a fix already exists for today`() = runTest {
        val harness = Harness(syncIntervalMinutes = 1440, lastCaptureDate = today, capturedFix = fix)

        harness.runner.runOnce()

        assertTrue("no capture should be attempted", harness.capturer.requestedTiers.isEmpty())
    }

    @Test
    fun `once-a-day interval captures when nothing has been recorded yet today`() = runTest {
        val harness = Harness(syncIntervalMinutes = 1440, lastCaptureDate = today.minusDays(1), capturedFix = fix)
        harness.locationsApi.nextResult = ApiResult.Success(
            ReportLocationsResponseDto(1, 0, true, DeviceSettingsDto(1440, true), "\"0\""),
            features = null,
        )

        harness.runner.runOnce()

        assertEquals(1, harness.capturer.requestedTiers.size)
        assertEquals(today, harness.lastCaptureDateStore.lastCaptureDate())
    }

    @Test
    fun `a transient flush failure is retried`() = runTest {
        val harness = Harness(capturedFix = fix)
        harness.locationsApi.nextResult = ApiResult.Failure(ApiError.NetworkFailure(RuntimeException("offline")))

        val result = harness.runner.runOnce()

        assertEquals(RunResult.Retry, result)
    }

    @Test
    fun `a paused response applies the echoed settings`() = runTest {
        val harness = Harness(capturedFix = fix)
        harness.locationsApi.nextResult = ApiResult.Failure(
            ApiError.TrackingPaused(
                deviceSettings = DeviceSettingsSnapshot(60, false),
                message = "paused",
                requestId = null,
            ),
        )

        val result = harness.runner.runOnce()

        assertEquals(RunResult.Success, result)
        assertTrue("reschedule must not be called - trackingEnabled is false", harness.scheduler.rescheduleCalls.isEmpty())
        assertEquals(1, harness.scheduler.cancelAllCallCount)
        assertEquals(1, harness.geofenceRegistry.unregisterAllCallCount)
    }

    @Test
    fun `DEVICE_NOT_FOUND triggers re-registration`() = runTest {
        val harness = Harness(capturedFix = fix)
        harness.locationsApi.nextResult = ApiResult.Failure(ApiError.DeviceNotFound("gone", null))

        val result = harness.runner.runOnce()

        assertEquals(RunResult.Success, result)
        assertEquals(1, harness.reRegisterCalls.size)
    }

    @Test
    fun `a second AUTH_TOKEN_EXPIRED signs out`() = runTest {
        val harness = Harness(capturedFix = fix)
        harness.locationsApi.nextResult = ApiResult.Failure(ApiError.AuthTokenExpired("expired", null))

        val result = harness.runner.runOnce()

        assertEquals(RunResult.Success, result)
        assertEquals(1, harness.signedOutCalls.size)
    }

    @Test
    fun `no fix obtained and nothing queued - still a clean success`() = runTest {
        val harness = Harness(capturedFix = null)

        val result = harness.runner.runOnce()

        assertEquals(RunResult.Success, result)
        assertNull(harness.queueStore.nextBatch())
    }

    // ---- geofence-event flush (specs/009-device-runtime.md §6.3: "Events are flushed like
    // fixes... on the same cadence") ----

    @Test
    fun `queued geofence events are flushed after the fix queue drains`() = runTest {
        val harness = Harness(capturedFix = null)
        harness.geofenceEventQueueStore.enqueue(
            QueuedGeofenceEvent(eventId = "evt-1", geofenceId = "gf_home", transition = "enter", recordedAt = "2026-07-19T09:00:00Z"),
        )
        harness.geofenceApi.reportGeofenceEventsResult = ApiResult.Success(
            GeofenceEventsResponseDto(accepted = 1, duplicates = 0, deviceSettings = DeviceSettingsDto(15, true), geofenceEtag = "\"0\""),
            features = null,
        )

        val result = harness.runner.runOnce()

        assertEquals(RunResult.Success, result)
        assertEquals(0, harness.geofenceEventQueueStore.pendingCount())
        assertEquals("device-1", harness.geofenceApi.reportGeofenceEventsCalls.single().first)
    }

    @Test
    fun `an observed geofenceEtag mismatch on the fix-flush piggyback triggers a geofence config re-sync`() = runTest {
        val harness = Harness(capturedFix = fix)
        harness.locationsApi.nextResult = ApiResult.Success(
            ReportLocationsResponseDto(1, 0, true, DeviceSettingsDto(15, true), "\"new-etag\""),
            features = null,
        )

        harness.runner.runOnce()

        assertEquals(1, harness.geofenceApi.getGeofencesCalls.size)
    }

    @Test
    fun `a geofenceEtag that matches the cache never triggers a config re-fetch`() = runTest {
        val harness = Harness(capturedFix = fix)
        // Pre-seed the cache to the same etag the flush will echo back, via a first sync.
        harness.geofenceApi.getGeofencesResult = ApiResult.Success(
            com.findly.android.network.ETagged(
                com.findly.android.network.dto.GeofenceConfigResponseDto(version = 1, geofences = emptyList()),
                "\"same\"",
            ),
            features = defaultFeatures(),
        )
        harness.geofenceConfigSyncCoordinator.sync()
        harness.geofenceApi.getGeofencesCalls.clear()

        harness.locationsApi.nextResult = ApiResult.Success(
            ReportLocationsResponseDto(1, 0, true, DeviceSettingsDto(15, true), "\"same\""),
            features = null,
        )

        harness.runner.runOnce()

        assertTrue(harness.geofenceApi.getGeofencesCalls.isEmpty())
    }

    @Test
    fun `a paused response on the geofence-event flush applies the echoed settings and stops the run`() = runTest {
        val harness = Harness(capturedFix = null)
        harness.geofenceEventQueueStore.enqueue(
            QueuedGeofenceEvent(eventId = "evt-1", geofenceId = "gf_home", transition = "exit", recordedAt = "2026-07-19T09:00:00Z"),
        )
        harness.geofenceApi.reportGeofenceEventsResult = ApiResult.Failure(
            ApiError.TrackingPaused(DeviceSettingsSnapshot(60, false), "paused", null),
        )

        val result = harness.runner.runOnce()

        assertEquals(RunResult.Success, result)
        assertEquals(1, harness.scheduler.cancelAllCallCount)
        assertEquals(1, harness.geofenceRegistry.unregisterAllCallCount)
    }

    @Test
    fun `a transient geofence-event flush failure retries`() = runTest {
        val harness = Harness(capturedFix = null)
        harness.geofenceEventQueueStore.enqueue(
            QueuedGeofenceEvent(eventId = "evt-1", geofenceId = "gf_home", transition = "enter", recordedAt = "2026-07-19T09:00:00Z"),
        )
        harness.geofenceApi.reportGeofenceEventsResult = ApiResult.Failure(ApiError.NetworkFailure(RuntimeException("offline")))

        val result = harness.runner.runOnce()

        assertEquals(RunResult.Retry, result)
    }
}
