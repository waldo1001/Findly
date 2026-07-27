package com.findly.android.location

import com.findly.android.fakes.FakeLocationCapturer
import com.findly.android.queue.FixSource
import com.findly.android.queue.InMemoryFixQueueStore
import java.time.Instant
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Verifies specs/009-device-runtime.md §1.2's capture-suppression rules and the capture-and-queue
 * pipeline of §1, independent of any real `FusedLocationProviderClient`/Android framework. */
class FixCaptureCoordinatorTest {

    private fun fix(
        lat: Double = 51.0,
        lon: Double = 3.7,
        recordedAt: String = "2026-07-19T09:00:00Z",
        batteryPct: Int = 77,
    ) = CapturedFix(lat = lat, lon = lon, accuracyM = 10.0, recordedAt = recordedAt, batteryPct = batteryPct)

    private fun coordinator(
        capturer: FakeLocationCapturer,
        queueStore: InMemoryFixQueueStore = InMemoryFixQueueStore(),
        paused: Boolean = false,
        permissionGranted: Boolean = true,
        clock: () -> Instant = { Instant.parse("2026-07-19T09:00:00Z") },
    ) = FixCaptureCoordinator(
        capturer = capturer,
        queueStore = queueStore,
        pauseState = { paused },
        permissionState = { permissionGranted },
        fixIdGenerator = sequenceIdGenerator(),
        now = clock,
    )

    private fun sequenceIdGenerator(): () -> String {
        var counter = 0
        return { "fix-${counter++}" }
    }

    @Test
    fun `a successful capture is enqueued under the given source, battery carried straight from the fix`() = runTest {
        val capturer = FakeLocationCapturer(fixToReturn = fix())
        val queueStore = InMemoryFixQueueStore()
        val coordinator = coordinator(capturer, queueStore)

        val result = coordinator.captureAndQueue(FixSource.Periodic)

        assertEquals(fix(), result)
        assertEquals(1, queueStore.pendingCount())
        val queued = requireNotNull(queueStore.nextBatch())
        assertEquals(FixSource.Periodic, queued.fixes.single().source)
        assertEquals(77, queued.fixes.single().batteryPct)
    }

    @Test
    fun `manual capture requests HIGH accuracy`() = runTest {
        val capturer = FakeLocationCapturer(fixToReturn = fix())
        val coordinator = coordinator(capturer)

        coordinator.captureAndQueue(FixSource.Manual)

        assertEquals(LocationAccuracyTier.HIGH, capturer.requestedTiers.single())
    }

    @Test
    fun `periodic capture requests BALANCED accuracy with the default 30s timeout`() = runTest {
        val capturer = FakeLocationCapturer(fixToReturn = fix())
        val coordinator = coordinator(capturer)

        coordinator.captureAndQueue(FixSource.Periodic)

        assertEquals(LocationAccuracyTier.BALANCED, capturer.requestedTiers.single())
        assertEquals(30_000L, capturer.requestedTimeouts.single())
    }

    @Test
    fun `geofence capture requests BALANCED accuracy with the shorter 15s timeout`() = runTest {
        val capturer = FakeLocationCapturer(fixToReturn = fix())
        val coordinator = coordinator(capturer)

        coordinator.captureAndQueue(FixSource.Geofence)

        assertEquals(LocationAccuracyTier.BALANCED, capturer.requestedTiers.single())
        assertEquals(15_000L, capturer.requestedTimeouts.single())
    }

    @Test
    fun `a geofence hint short-circuits the capturer entirely - reused, never a fresh request`() = runTest {
        val capturer = FakeLocationCapturer(fixToReturn = fix())
        val queueStore = InMemoryFixQueueStore()
        val coordinator = coordinator(capturer, queueStore)
        val hint = fix(lat = 12.0, lon = 34.0)

        val result = coordinator.captureAndQueue(FixSource.Geofence, hint = hint)

        assertEquals(hint, result)
        assertTrue("the capturer must never be invoked when a hint is supplied", capturer.requestedTiers.isEmpty())
        val queued = requireNotNull(queueStore.nextBatch())
        assertEquals(12.0, queued.fixes.single().lat, 0.0)
    }

    @Test
    fun `a timeout (null fix) is not queued and not an error`() = runTest {
        val capturer = FakeLocationCapturer(fixToReturn = null)
        val queueStore = InMemoryFixQueueStore()
        val coordinator = coordinator(capturer, queueStore)

        val result = coordinator.captureAndQueue(FixSource.Periodic)

        assertNull(result)
        assertEquals(0, queueStore.pendingCount())
    }

    @Test
    fun `paused - capture is never even attempted`() = runTest {
        val capturer = FakeLocationCapturer(fixToReturn = fix())
        val coordinator = coordinator(capturer, paused = true)

        val result = coordinator.captureAndQueue(FixSource.Periodic)

        assertNull(result)
        assertTrue("no GPS request should happen while paused", capturer.requestedTiers.isEmpty())
    }

    @Test
    fun `permission absent - capture is never even attempted`() = runTest {
        val capturer = FakeLocationCapturer(fixToReturn = fix())
        val coordinator = coordinator(capturer, permissionGranted = false)

        val result = coordinator.captureAndQueue(FixSource.Periodic)

        assertNull(result)
        assertTrue(capturer.requestedTiers.isEmpty())
    }

    @Test
    fun `an identical-position fix within 60s of the last one is dropped, not queued`() = runTest {
        val capturer = FakeLocationCapturer(fixToReturn = fix(recordedAt = "2026-07-19T09:00:00Z"))
        val queueStore = InMemoryFixQueueStore()
        var clock = Instant.parse("2026-07-19T09:00:00Z")
        val coordinator = coordinator(capturer, queueStore, clock = { clock })

        coordinator.captureAndQueue(FixSource.Periodic)
        clock = clock.plusSeconds(30)
        capturer.fixToReturn = fix(recordedAt = "2026-07-19T09:00:30Z") // identical lat/lon
        val second = coordinator.captureAndQueue(FixSource.Periodic)

        assertNull(second)
        assertEquals(1, queueStore.pendingCount())
    }

    @Test
    fun `an identical-position fix 60s or later is not suppressed`() = runTest {
        val capturer = FakeLocationCapturer(fixToReturn = fix())
        val queueStore = InMemoryFixQueueStore()
        var clock = Instant.parse("2026-07-19T09:00:00Z")
        val coordinator = coordinator(capturer, queueStore, clock = { clock })

        coordinator.captureAndQueue(FixSource.Periodic)
        clock = clock.plusSeconds(60)
        val second = coordinator.captureAndQueue(FixSource.Periodic)

        assertEquals(fix(), second)
        assertEquals(2, queueStore.pendingCount())
    }

    @Test
    fun `a different position within 60s is not suppressed`() = runTest {
        val capturer = FakeLocationCapturer(fixToReturn = fix(lat = 1.0, lon = 1.0))
        val queueStore = InMemoryFixQueueStore()
        val coordinator = coordinator(capturer, queueStore)

        coordinator.captureAndQueue(FixSource.Periodic)
        capturer.fixToReturn = fix(lat = 2.0, lon = 2.0)
        val second = coordinator.captureAndQueue(FixSource.Periodic)

        assertEquals(fix(lat = 2.0, lon = 2.0), second)
        assertEquals(2, queueStore.pendingCount())
    }

    @Test
    fun `pause landing mid-capture drops the result instead of queuing it`() = runTest {
        var paused = false
        val capturer = FakeLocationCapturer(fixToReturn = fix())
        val queueStore = InMemoryFixQueueStore()
        // A capturer that flips `paused` true as a side effect of "being slow" - simulating a
        // pause landing while the (up to 30s) GPS request was in flight.
        val slowCapturer = object : LocationCapturer {
            override suspend fun captureFix(accuracy: LocationAccuracyTier, timeoutMillis: Long): CapturedFix? {
                val result = capturer.captureFix(accuracy, timeoutMillis)
                paused = true
                return result
            }
        }
        val coordinator = FixCaptureCoordinator(
            capturer = slowCapturer,
            queueStore = queueStore,
            pauseState = { paused },
            permissionState = { true },
        )

        val result = coordinator.captureAndQueue(FixSource.Periodic)

        assertNull(result)
        assertEquals(0, queueStore.pendingCount())
    }
}
