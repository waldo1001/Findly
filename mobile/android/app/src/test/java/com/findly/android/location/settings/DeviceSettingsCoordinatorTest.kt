package com.findly.android.location.settings

import com.findly.android.fakes.FakeGeofenceRegistry
import com.findly.android.fakes.FakeSyncScheduler
import com.findly.android.fakes.InMemoryDeviceSettingsStateStore
import com.findly.android.network.DeviceSettingsSnapshot
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

/** [DeviceSettingsCoordinator] end to end against fakes — the orchestration half of
 * specs/009-device-runtime.md §3.5/§4 ([SettingsChangeDecisionTest] covers the decision logic
 * itself). */
class DeviceSettingsCoordinatorTest {

    @Test
    fun `interval change reschedules and does not touch geofences`() = runTest {
        val scheduler = FakeSyncScheduler()
        val geofenceRegistry = FakeGeofenceRegistry()
        val stateStore = InMemoryDeviceSettingsStateStore(DeviceSettingsSnapshot(15, true))
        val coordinator = DeviceSettingsCoordinator(scheduler, geofenceRegistry, stateStore)

        coordinator.applySettings(DeviceSettingsSnapshot(30, true))

        assertEquals(listOf(30), scheduler.rescheduleCalls)
        assertEquals(0, scheduler.cancelAllCallCount)
        assertEquals(0, geofenceRegistry.unregisterAllCallCount)
        assertEquals(DeviceSettingsSnapshot(30, true), stateStore.current())
    }

    @Test
    fun `trackingEnabled turning false cancels the schedule and unregisters geofences`() = runTest {
        val scheduler = FakeSyncScheduler()
        val geofenceRegistry = FakeGeofenceRegistry()
        val stateStore = InMemoryDeviceSettingsStateStore(DeviceSettingsSnapshot(15, true))
        val coordinator = DeviceSettingsCoordinator(scheduler, geofenceRegistry, stateStore)

        coordinator.applySettings(DeviceSettingsSnapshot(15, false))

        assertEquals(1, scheduler.cancelAllCallCount)
        assertEquals(1, geofenceRegistry.unregisterAllCallCount)
        assertEquals(emptyList<Int>(), scheduler.rescheduleCalls)
        // The cache is updated before cancelAll()/unregisterAll() are even called (verified
        // below) - so a capture racing this exact call already observes trackingEnabled=false
        // (specs/009 §1.2's "stop capturing" reads this same cache on every attempt).
        assertEquals(DeviceSettingsSnapshot(15, false), stateStore.current())
    }

    @Test
    fun `trackingEnabled turning true again rebuilds the schedule (resume)`() = runTest {
        val scheduler = FakeSyncScheduler()
        val geofenceRegistry = FakeGeofenceRegistry()
        val stateStore = InMemoryDeviceSettingsStateStore(DeviceSettingsSnapshot(15, false))
        val coordinator = DeviceSettingsCoordinator(scheduler, geofenceRegistry, stateStore)

        coordinator.applySettings(DeviceSettingsSnapshot(15, true))

        assertEquals(listOf(15), scheduler.rescheduleCalls)
        assertEquals(0, geofenceRegistry.unregisterAllCallCount)
    }

    @Test
    fun `applying identical settings twice is a no-op the second time`() = runTest {
        val scheduler = FakeSyncScheduler()
        val geofenceRegistry = FakeGeofenceRegistry()
        val stateStore = InMemoryDeviceSettingsStateStore()
        val coordinator = DeviceSettingsCoordinator(scheduler, geofenceRegistry, stateStore)

        coordinator.applySettings(DeviceSettingsSnapshot(15, true))
        coordinator.applySettings(DeviceSettingsSnapshot(15, true))

        assertEquals(listOf(15), scheduler.rescheduleCalls) // only the first application rebuilt
    }

    @Test
    fun `the very first settings application on a fresh install rebuilds the schedule`() = runTest {
        val scheduler = FakeSyncScheduler()
        val geofenceRegistry = FakeGeofenceRegistry()
        val stateStore = InMemoryDeviceSettingsStateStore(initial = null)
        val coordinator = DeviceSettingsCoordinator(scheduler, geofenceRegistry, stateStore)

        coordinator.applySettings(DeviceSettingsSnapshot(15, true))

        assertEquals(listOf(15), scheduler.rescheduleCalls)
    }

    @Test
    fun `settings cache is updated before any pause action, so a racing capture already observes it`() = runTest {
        val events = mutableListOf<String>()
        val geofenceRegistry = FakeGeofenceRegistry()
        val stateStore = object : DeviceSettingsStateStore {
            private var stored: DeviceSettingsSnapshot? = DeviceSettingsSnapshot(15, true)
            override suspend fun current(): DeviceSettingsSnapshot? = stored
            override suspend fun update(settings: DeviceSettingsSnapshot) {
                stored = settings
                events.add("update(trackingEnabled=${settings.trackingEnabled})")
            }
        }
        val recordingScheduler = object : SyncScheduler {
            override fun reschedule(syncIntervalMinutes: Int) {
                events.add("reschedule")
            }
            override fun cancelAll() {
                events.add("cancelAll")
            }
        }
        val coordinator = DeviceSettingsCoordinator(recordingScheduler, geofenceRegistry, stateStore)

        coordinator.applySettings(DeviceSettingsSnapshot(15, false))

        assertEquals(listOf("update(trackingEnabled=false)", "cancelAll"), events)
    }
}
