package com.findly.android.location.geofence

import com.findly.android.fakes.FakeLocationCapturer
import com.findly.android.location.FixCaptureCoordinator
import com.findly.android.queue.FixSource
import com.findly.android.queue.InMemoryFixQueueStore
import com.findly.android.queue.InMemoryGeofenceEventQueueStore
import java.time.Instant
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [GeofenceTransitionHandler] — the tested decision logic behind a `GeofencingClient` enter/exit
 * callback (specs/009-device-runtime.md §6.3), independent of any real `GeofencingEvent`/
 * `BroadcastReceiver` (those live in the untested [GeofenceTransitionReceiver]).
 */
private fun sequenceIdGenerator(): () -> String {
    var counter = 0
    return { "evt-${counter++}" }
}

class GeofenceTransitionHandlerTest {

    private class Harness(
        paused: Boolean = false,
        batteryPct: Int = 55,
        now: () -> Instant = { Instant.parse("2026-07-27T09:00:00Z") },
    ) {
        val eventQueueStore = InMemoryGeofenceEventQueueStore()
        val fixQueueStore = InMemoryFixQueueStore()
        val capturer = FakeLocationCapturer(fixToReturn = null) // must never be invoked - hint short-circuits it
        val fixCaptureCoordinator = FixCaptureCoordinator(
            capturer = capturer,
            queueStore = fixQueueStore,
            pauseState = { paused },
            permissionState = { true },
        )
        val handler = GeofenceTransitionHandler(
            eventQueueStore = eventQueueStore,
            fixCaptureCoordinator = fixCaptureCoordinator,
            batteryLevelProvider = { batteryPct },
            pauseState = { paused },
            eventIdGenerator = sequenceIdGenerator(),
            now = now,
        )
    }

    @Test
    fun `an enter callback queues one event per triggering geofence`() = runTest {
        val harness = Harness()
        val event = GeofenceTransitionEvent(
            geofenceIds = listOf("gf_home", "gf_work"),
            transition = GeofenceTransitionType.Enter,
            lat = 51.05,
            lon = 3.71,
            accuracyM = 12.0,
        )

        harness.handler.handle(event)

        val batch = requireNotNull(harness.eventQueueStore.nextBatch())
        assertEquals(listOf("gf_home", "gf_work"), batch.events.map { it.geofenceId })
        assertTrue(batch.events.all { it.transition == "enter" })
        assertEquals(listOf("evt-0", "evt-1"), batch.events.map { it.eventId })
    }

    @Test
    fun `an exit callback records the exit transition`() = runTest {
        val harness = Harness()
        val event = GeofenceTransitionEvent(listOf("gf_home"), GeofenceTransitionType.Exit, 51.05, 3.71, 12.0)

        harness.handler.handle(event)

        val batch = requireNotNull(harness.eventQueueStore.nextBatch())
        assertEquals("exit", batch.events.single().transition)
    }

    @Test
    fun `additionally queues exactly one source geofence fix using the transition's own coordinates`() = runTest {
        val harness = Harness(batteryPct = 42)
        val event = GeofenceTransitionEvent(listOf("gf_home", "gf_work"), GeofenceTransitionType.Enter, 51.05, 3.71, 12.0)

        harness.handler.handle(event)

        val fixBatch = requireNotNull(harness.fixQueueStore.nextBatch())
        val queuedFix = fixBatch.fixes.single() // one fix per CALLBACK, not per geofence id
        assertEquals(FixSource.Geofence, queuedFix.source)
        assertEquals(51.05, queuedFix.lat, 0.0)
        assertEquals(3.71, queuedFix.lon, 0.0)
        assertEquals(12.0, queuedFix.accuracyM, 0.0)
        assertEquals(42, queuedFix.batteryPct)
        assertTrue("the real LocationCapturer must never be invoked - the hint short-circuits it", harness.capturer.requestedTiers.isEmpty())
    }

    @Test
    fun `a transition detected while paused is dropped, not queued (009 §4)`() = runTest {
        val harness = Harness(paused = true)
        val event = GeofenceTransitionEvent(listOf("gf_home"), GeofenceTransitionType.Enter, 51.05, 3.71, 12.0)

        harness.handler.handle(event)

        assertEquals(0, harness.eventQueueStore.pendingCount())
        assertEquals(0, harness.fixQueueStore.pendingCount())
    }

    @Test
    fun `recordedAt is shared between the queued event(s) and the fix hint from the same callback`() = runTest {
        val harness = Harness(now = { Instant.parse("2026-07-27T10:15:00Z") })
        val event = GeofenceTransitionEvent(listOf("gf_home"), GeofenceTransitionType.Enter, 51.05, 3.71, 12.0)

        harness.handler.handle(event)

        val queuedEvent = requireNotNull(harness.eventQueueStore.nextBatch()).events.single()
        val queuedFix = requireNotNull(harness.fixQueueStore.nextBatch()).fixes.single()
        assertEquals("2026-07-27T10:15:00Z", queuedEvent.recordedAt)
        assertEquals("2026-07-27T10:15:00Z", queuedFix.recordedAt)
    }
}
