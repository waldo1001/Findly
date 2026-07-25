package com.findly.android.queue

import com.findly.android.fakes.FakeLocationsApi
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.DeviceSettingsSnapshot
import com.findly.android.network.dto.DeviceSettingsDto
import com.findly.android.network.dto.ReportLocationsResponseDto
import java.io.IOException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LocationSyncCoordinatorTest {

    private fun fix(id: String) = QueuedFix(
        fixId = id,
        recordedAt = "2026-07-19T09:00:00Z",
        lat = 51.0,
        lon = 3.7,
        accuracyM = 10.0,
        batteryPct = 80,
        source = FixSource.Periodic,
    )

    @Test
    fun `NothingToSync when the queue is empty`() = runTest {
        val coordinator = LocationSyncCoordinator(InMemoryFixQueueStore(), FakeLocationsApi(), deviceId = "d1")

        val outcome = coordinator.syncOnce()

        assertTrue(outcome is SyncOutcome.NothingToSync)
    }

    @Test
    fun `success marks the batch accepted and reports the counts`() = runTest {
        val store = InMemoryFixQueueStore()
        store.enqueue(fix("a"))
        val api = FakeLocationsApi().apply {
            nextResult = ApiResult.Success(
                ReportLocationsResponseDto(
                    accepted = 1,
                    duplicates = 0,
                    lastKnownUpdated = true,
                    deviceSettings = DeviceSettingsDto(15, true),
                    geofenceEtag = "\"1\"",
                ),
                features = null,
            )
        }
        val coordinator = LocationSyncCoordinator(store, api, deviceId = "d1")

        val outcome = coordinator.syncOnce()

        assertTrue(outcome is SyncOutcome.Synced)
        assertEquals(1, (outcome as SyncOutcome.Synced).accepted)
        assertEquals(0, store.pendingCount())
    }

    @Test
    fun `transient failure keeps the batch frozen for an identical retry`() = runTest {
        val store = InMemoryFixQueueStore()
        store.enqueue(fix("a"))
        val api = FakeLocationsApi().apply {
            nextResult = ApiResult.Failure(ApiError.NetworkFailure(IOException("boom")))
        }
        val coordinator = LocationSyncCoordinator(store, api, deviceId = "d1")

        val outcome = coordinator.syncOnce()

        assertTrue(outcome is SyncOutcome.TransientFailure)
        val retryBatch = requireNotNull(store.nextBatch())
        assertEquals(listOf("a"), retryBatch.fixes.map { it.fixId })
    }

    @Test
    fun `validation failure drops only the offending fix and requeues the rest`() = runTest {
        val store = InMemoryFixQueueStore()
        store.enqueue(fix("a"))
        store.enqueue(fix("b"))
        val api = FakeLocationsApi().apply {
            nextResult = ApiResult.Failure(
                ApiError.ValidationFailed(
                    fields = listOf("fixes[0].recordedAt"),
                    reason = null,
                    message = "bad fix",
                    requestId = "r_1",
                ),
            )
        }
        val coordinator = LocationSyncCoordinator(store, api, deviceId = "d1")

        val outcome = coordinator.syncOnce()

        assertTrue(outcome is SyncOutcome.Rejected)
        assertEquals(setOf("a"), (outcome as SyncOutcome.Rejected).droppedFixIds)
        assertEquals(1, store.pendingCount())
        val nextBatch = requireNotNull(store.nextBatch())
        assertEquals(listOf("b"), nextBatch.fixes.map { it.fixId })
    }

    @Test
    fun `tracking-paused failure surfaces device settings without touching the queue`() = runTest {
        val store = InMemoryFixQueueStore()
        store.enqueue(fix("a"))
        val api = FakeLocationsApi().apply {
            nextResult = ApiResult.Failure(
                ApiError.TrackingPaused(
                    deviceSettings = DeviceSettingsSnapshot(syncIntervalMinutes = 30, trackingEnabled = false),
                    message = "paused",
                    requestId = "r_2",
                ),
            )
        }
        val coordinator = LocationSyncCoordinator(store, api, deviceId = "d1")

        val outcome = coordinator.syncOnce()

        assertTrue(outcome is SyncOutcome.Paused)
        assertEquals(30, (outcome as SyncOutcome.Paused).syncIntervalMinutes)
        assertEquals(1, store.pendingCount())
    }
}
