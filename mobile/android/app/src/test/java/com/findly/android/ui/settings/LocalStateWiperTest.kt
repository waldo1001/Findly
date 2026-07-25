package com.findly.android.ui.settings

import com.findly.android.fakes.InMemoryDeviceIdStore
import com.findly.android.queue.FixSource
import com.findly.android.queue.InMemoryFixQueueStore
import com.findly.android.queue.QueuedFix
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** [DefaultLocalStateWiper] — specs/008-privacy-endpoints.md §4.4/§3.1 / specs/003-android-
 * client.md §12.4's "clear all local state — fix queue, deviceId, any cached config/ETags, and
 * the export artifacts of 008 §3.1" after a successful account deletion. */
class LocalStateWiperTest {

    private fun wiper(
        fixQueueStore: InMemoryFixQueueStore = InMemoryFixQueueStore(),
        deviceIdStore: InMemoryDeviceIdStore = InMemoryDeviceIdStore(),
        exportArtifactCleaner: ExportArtifactCleaner = ExportArtifactCleaner {},
    ) = DefaultLocalStateWiper(fixQueueStore, deviceIdStore, exportArtifactCleaner)

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
}
