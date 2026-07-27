package com.findly.android.ui.settings

import com.findly.android.fakes.InMemoryDeviceIdStore
import com.findly.android.fakes.InMemoryGeofenceConfigStateStore
import com.findly.android.location.settings.CachedGeofenceConfig
import com.findly.android.queue.FixSource
import com.findly.android.queue.InMemoryFixQueueStore
import com.findly.android.queue.InMemoryGeofenceEventQueueStore
import com.findly.android.queue.QueuedFix
import com.findly.android.queue.QueuedGeofenceEvent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** [DefaultLocalStateWiper] — specs/008-privacy-endpoints.md §4.4/§3.1 / specs/003-android-
 * client.md §12.4's "clear all local state — fix queue, deviceId, any cached config/ETags, and
 * the export artifacts of 008 §3.1" after a successful account deletion. A11 adds the geofence-
 * event queue and the cached geofence config/ETag to the "any cached config/ETags" bucket that
 * doc comment always anticipated but had nothing concrete to wire until now. */
class LocalStateWiperTest {

    private fun wiper(
        fixQueueStore: InMemoryFixQueueStore = InMemoryFixQueueStore(),
        deviceIdStore: InMemoryDeviceIdStore = InMemoryDeviceIdStore(),
        exportArtifactCleaner: ExportArtifactCleaner = ExportArtifactCleaner {},
        geofenceEventQueueStore: InMemoryGeofenceEventQueueStore = InMemoryGeofenceEventQueueStore(),
        geofenceConfigStateStore: InMemoryGeofenceConfigStateStore = InMemoryGeofenceConfigStateStore(),
    ) = DefaultLocalStateWiper(
        fixQueueStore,
        deviceIdStore,
        exportArtifactCleaner,
        geofenceEventQueueStore,
        geofenceConfigStateStore,
    )

    @Test
    fun `wipeAll clears every pending fix and the wiped uid's stored deviceId`() = runTest {
        val fixQueueStore = InMemoryFixQueueStore()
        fixQueueStore.enqueue(
            QueuedFix(
                fixId = "f1",
                recordedAt = "2026-07-19T09:00:00Z",
                lat = 51.0,
                lon = 3.7,
                accuracyM = 10.0,
                batteryPct = 80,
                source = FixSource.Periodic,
            ),
        )
        val deviceIdStore = InMemoryDeviceIdStore()
        deviceIdStore.put("uid-1", "device-abc")

        wiper(fixQueueStore, deviceIdStore).wipeAll("uid-1")

        assertEquals(0, fixQueueStore.pendingCount())
        assertNull(deviceIdStore.get("uid-1"))
    }

    @Test
    fun `wipeAll only clears the deviceId of the wiped uid, leaving other users untouched`() = runTest {
        val deviceIdStore = InMemoryDeviceIdStore()
        deviceIdStore.put("uid-1", "device-abc")
        deviceIdStore.put("uid-2", "device-xyz")

        wiper(deviceIdStore = deviceIdStore).wipeAll("uid-1")

        assertNull(deviceIdStore.get("uid-1"))
        assertEquals("device-xyz", deviceIdStore.get("uid-2"))
    }

    @Test
    fun `wipeAll also clears any export artifact (specs 008 §3_1 rule 2 - must not outlive the account)`() = runTest {
        var clearCallCount = 0
        val cleaner = ExportArtifactCleaner { clearCallCount++ }

        wiper(exportArtifactCleaner = cleaner).wipeAll("uid-1")

        assertEquals(1, clearCallCount)
    }

    @Test
    fun `wipeAll also clears every pending geofence event`() = runTest {
        val geofenceEventQueueStore = InMemoryGeofenceEventQueueStore()
        geofenceEventQueueStore.enqueue(
            QueuedGeofenceEvent(eventId = "evt-1", geofenceId = "gf_home", transition = "enter", recordedAt = "2026-07-19T09:00:00Z"),
        )

        wiper(geofenceEventQueueStore = geofenceEventQueueStore).wipeAll("uid-1")

        assertEquals(0, geofenceEventQueueStore.pendingCount())
    }

    @Test
    fun `wipeAll also clears the cached geofence config and ETag`() = runTest {
        val geofenceConfigStateStore = InMemoryGeofenceConfigStateStore(CachedGeofenceConfig("\"1\"", emptyList()))

        wiper(geofenceConfigStateStore = geofenceConfigStateStore).wipeAll("uid-1")

        assertNull(geofenceConfigStateStore.current())
    }
}
