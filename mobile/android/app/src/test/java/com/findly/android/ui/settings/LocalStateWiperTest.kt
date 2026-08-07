package com.findly.android.ui.settings

import com.findly.android.fakes.InMemoryDeviceIdStore
import com.findly.android.fakes.InMemoryGeofenceConfigStateStore
import com.findly.android.location.InMemoryPermissionDisclosureStore
import com.findly.android.location.PermissionDisclosureKind
import com.findly.android.location.settings.CachedGeofenceConfig
import com.findly.android.queue.FixBatch
import com.findly.android.queue.FixQueueStore
import com.findly.android.queue.FixSource
import com.findly.android.queue.InMemoryFixQueueStore
import com.findly.android.queue.InMemoryGeofenceEventQueueStore
import com.findly.android.queue.QueuedFix
import com.findly.android.queue.QueuedGeofenceEvent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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
        permissionDisclosureStore: InMemoryPermissionDisclosureStore = InMemoryPermissionDisclosureStore(),
    ) = DefaultLocalStateWiper(
        fixQueueStore,
        deviceIdStore,
        exportArtifactCleaner,
        geofenceEventQueueStore,
        geofenceConfigStateStore,
        permissionDisclosureStore,
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

    /** Code-review fix (A25 round 1, Major 2): `permissionDisclosureStore.clear()` previously had
     * NO caller in production code at all — the spec's own MUST ("a different user on the same
     * device MUST see the disclosure again", specs/009 §7 A25 paragraph) was unenforced. Same shape
     * as the iOS I26 mistake ("a documented clear that nothing calls"). */
    @Test
    fun `wipeAll also clears both acknowledgement and decline state from the permission disclosure store`() = runTest {
        val permissionDisclosureStore = InMemoryPermissionDisclosureStore()
        permissionDisclosureStore.acknowledge(PermissionDisclosureKind.FOREGROUND)
        permissionDisclosureStore.decline(PermissionDisclosureKind.BACKGROUND)

        wiper(permissionDisclosureStore = permissionDisclosureStore).wipeAll("uid-1")

        assertFalse(permissionDisclosureStore.isAcknowledged(PermissionDisclosureKind.FOREGROUND))
        assertFalse(permissionDisclosureStore.isDeclined(PermissionDisclosureKind.BACKGROUND))
    }

    /** Security-review fix (post-A11 review): five unguarded sequential suspend calls meant one
     * throwing (e.g. a Room `deleteAll()` disk I/O error) skipped everything after it - worst case,
     * the family's named places (home, school, ...) stayed cached on disk after an account
     * deletion that otherwise appeared to complete. Each step is now independently resilient
     * (`runCatching`), not reordered - reordering alone wouldn't fix "a failure anywhere still
     * skips everything after it". */
    @Test
    fun `a throwing store does not block the rest of the wipe - every other step still runs`() = runTest {
        val throwingFixQueueStore = ThrowingFixQueueStore()
        val deviceIdStore = InMemoryDeviceIdStore()
        deviceIdStore.put("uid-1", "device-abc")
        var exportCleanerCallCount = 0
        val exportArtifactCleaner = ExportArtifactCleaner { exportCleanerCallCount++ }
        val geofenceEventQueueStore = InMemoryGeofenceEventQueueStore()
        geofenceEventQueueStore.enqueue(
            QueuedGeofenceEvent(eventId = "evt-1", geofenceId = "gf_home", transition = "enter", recordedAt = "2026-07-19T09:00:00Z"),
        )
        val geofenceConfigStateStore = InMemoryGeofenceConfigStateStore(CachedGeofenceConfig("\"1\"", emptyList()))
        val permissionDisclosureStore = InMemoryPermissionDisclosureStore()
        permissionDisclosureStore.acknowledge(PermissionDisclosureKind.FOREGROUND)

        DefaultLocalStateWiper(
            throwingFixQueueStore,
            deviceIdStore,
            exportArtifactCleaner,
            geofenceEventQueueStore,
            geofenceConfigStateStore,
            permissionDisclosureStore,
        ).wipeAll("uid-1")

        assertTrue("the throwing step was actually attempted", throwingFixQueueStore.clearAllCallCount > 0)
        assertNull("deviceId is cleared even though the fix-queue step (which runs before it) threw", deviceIdStore.get("uid-1"))
        assertEquals("export artifacts are cleared too", 1, exportCleanerCallCount)
        assertEquals("the geofence-event queue is cleared too", 0, geofenceEventQueueStore.pendingCount())
        assertNull("the geofence config cache is cleared too - the most sensitive of the new stores", geofenceConfigStateStore.current())
        assertFalse(
            "the permission disclosure store is cleared too",
            permissionDisclosureStore.isAcknowledged(PermissionDisclosureKind.FOREGROUND),
        )
    }

    @Test
    fun `every store is attempted even when an earlier one throws, regardless of which one throws`() = runTest {
        // A second scenario with the throw on the LAST step, proving no step is silently skipped
        // regardless of position - the fix isn't "make the first step resilient", it's "every step".
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
        val throwingConfigStore = object : com.findly.android.location.settings.GeofenceConfigStateStore {
            override suspend fun current(): CachedGeofenceConfig? = null
            override suspend fun update(config: CachedGeofenceConfig) = Unit
            override suspend fun clear(): Nothing = throw IllegalStateException("disk I/O error")
        }

        DefaultLocalStateWiper(
            fixQueueStore,
            InMemoryDeviceIdStore(),
            ExportArtifactCleaner {},
            InMemoryGeofenceEventQueueStore(),
            throwingConfigStore,
            InMemoryPermissionDisclosureStore(),
        ).wipeAll("uid-1")

        assertEquals("the fix queue - which runs BEFORE the throwing step - still gets cleared", 0, fixQueueStore.pendingCount())
    }
}

/** Throws from [clearAll] every time (simulating a Room `deleteAll()` disk I/O error) while
 * tracking that it was actually invoked; every other method is unused by [DefaultLocalStateWiper]
 * and just delegates to a real in-memory store. */
private class ThrowingFixQueueStore : FixQueueStore {
    private val delegate = InMemoryFixQueueStore()
    var clearAllCallCount = 0
        private set

    override suspend fun enqueue(fix: QueuedFix) = delegate.enqueue(fix)
    override suspend fun pendingCount(): Int = delegate.pendingCount()
    override suspend fun nextBatch(maxSize: Int): FixBatch? = delegate.nextBatch(maxSize)
    override suspend fun markBatchAccepted(batchId: String) = delegate.markBatchAccepted(batchId)
    override suspend fun markBatchFailedTransient(batchId: String) = delegate.markBatchFailedTransient(batchId)
    override suspend fun markBatchRejected(batchId: String, offendingFixIds: Set<String>) =
        delegate.markBatchRejected(batchId, offendingFixIds)

    override suspend fun clearAll(): Nothing {
        clearAllCallCount++
        throw IllegalStateException("disk I/O error")
    }
}
