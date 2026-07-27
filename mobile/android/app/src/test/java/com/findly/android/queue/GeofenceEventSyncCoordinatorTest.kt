package com.findly.android.queue

import com.findly.android.fakes.FakeGeofenceApi
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.DeviceSettingsSnapshot
import com.findly.android.network.dto.DeviceSettingsDto
import com.findly.android.network.dto.GeofenceEventsResponseDto
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** [GeofenceEventSyncCoordinator] ties [GeofenceEventQueueStore] + `GeofenceApi.reportGeofenceEvents`
 * together (001-api-contract.md §7.3), mirroring `LocationSyncCoordinatorTest`'s coverage of the
 * analogous fix-flush coordinator. */
class GeofenceEventSyncCoordinatorTest {

    private fun event(id: String) = QueuedGeofenceEvent(
        eventId = id,
        geofenceId = "gf_home",
        transition = "enter",
        recordedAt = "2026-07-27T09:00:00Z",
    )

    @Test
    fun `nothing pending returns NothingToSync without calling the api`() = runTest {
        val api = FakeGeofenceApi()
        val coordinator = GeofenceEventSyncCoordinator(InMemoryGeofenceEventQueueStore(), api, deviceId = "device-1")

        val outcome = coordinator.syncOnce()

        assertEquals(GeofenceEventSyncOutcome.NothingToSync, outcome)
        assertTrue(api.reportGeofenceEventsCalls.isEmpty())
    }

    @Test
    fun `a successful report removes the batch and surfaces the piggyback`() = runTest {
        val queueStore = InMemoryGeofenceEventQueueStore()
        queueStore.enqueue(event("a"))
        val api = FakeGeofenceApi().apply {
            reportGeofenceEventsResult = ApiResult.Success(
                GeofenceEventsResponseDto(accepted = 1, duplicates = 0, deviceSettings = DeviceSettingsDto(30, true), geofenceEtag = "\"7\""),
                features = null,
            )
        }
        val coordinator = GeofenceEventSyncCoordinator(queueStore, api, deviceId = "device-1")

        val outcome = coordinator.syncOnce()

        assertEquals(
            GeofenceEventSyncOutcome.Synced(1, 0, DeviceSettingsSnapshot(30, true), "\"7\""),
            outcome,
        )
        assertEquals(0, queueStore.pendingCount())
        assertEquals("device-1", api.reportGeofenceEventsCalls.single().first)
        assertEquals(listOf("a"), api.reportGeofenceEventsCalls.single().second.map { it.eventId })
    }

    @Test
    fun `a paused response keeps the batch queued and surfaces the echoed settings`() = runTest {
        val queueStore = InMemoryGeofenceEventQueueStore()
        queueStore.enqueue(event("a"))
        val api = FakeGeofenceApi().apply {
            reportGeofenceEventsResult = ApiResult.Failure(
                ApiError.TrackingPaused(DeviceSettingsSnapshot(60, false), "paused", null),
            )
        }
        val coordinator = GeofenceEventSyncCoordinator(queueStore, api, deviceId = "device-1")

        val outcome = coordinator.syncOnce()

        assertEquals(GeofenceEventSyncOutcome.Paused(60, false), outcome)
        assertEquals(1, queueStore.pendingCount()) // pre-pause events stay queued for after resume
    }

    @Test
    fun `a network failure is a transient retry - the batch stays frozen`() = runTest {
        val queueStore = InMemoryGeofenceEventQueueStore()
        queueStore.enqueue(event("a"))
        val api = FakeGeofenceApi().apply {
            reportGeofenceEventsResult = ApiResult.Failure(ApiError.NetworkFailure(RuntimeException("offline")))
        }
        val coordinator = GeofenceEventSyncCoordinator(queueStore, api, deviceId = "device-1")
        val firstBatch = queueStore.nextBatch()

        val outcome = coordinator.syncOnce()

        assertEquals(GeofenceEventSyncOutcome.TransientFailure, outcome)
        assertEquals(firstBatch, queueStore.nextBatch()) // identical retry
    }

    @Test
    fun `DEVICE_NOT_FOUND is surfaced as OtherFailure and keeps the batch queued for retry`() = runTest {
        val queueStore = InMemoryGeofenceEventQueueStore()
        queueStore.enqueue(event("a"))
        val api = FakeGeofenceApi().apply {
            reportGeofenceEventsResult = ApiResult.Failure(ApiError.DeviceNotFound("gone", null))
        }
        val coordinator = GeofenceEventSyncCoordinator(queueStore, api, deviceId = "device-1")

        val outcome = coordinator.syncOnce()

        assertTrue(outcome is GeofenceEventSyncOutcome.OtherFailure)
        assertEquals(1, queueStore.pendingCount())
    }

    @Test
    fun `nextBatch respects the endpoint's 1-20 cap`() = runTest {
        val queueStore = InMemoryGeofenceEventQueueStore()
        repeat(25) { queueStore.enqueue(event("evt-$it")) }
        val api = FakeGeofenceApi()
        val coordinator = GeofenceEventSyncCoordinator(queueStore, api, deviceId = "device-1")

        coordinator.syncOnce()

        assertEquals(20, api.reportGeofenceEventsCalls.single().second.size)
    }
}
