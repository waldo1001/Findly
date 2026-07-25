package com.findly.android.device

import com.findly.android.fakes.InMemoryDeviceIdStore
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class DeviceIdProviderTest {

    @Test
    fun `generates a fresh UUIDv4 the first time a uid is seen`() {
        val provider = DeviceIdProvider(InMemoryDeviceIdStore())

        val id = provider.deviceIdFor("uid-1")

        val parsed = UUID.fromString(id) // throws if not a valid UUID
        assertEquals(4, parsed.version())
    }

    @Test
    fun `returns the same id for the same uid on subsequent calls`() {
        val provider = DeviceIdProvider(InMemoryDeviceIdStore())

        val first = provider.deviceIdFor("uid-1")
        val second = provider.deviceIdFor("uid-1")

        assertEquals(first, second)
    }

    @Test
    fun `generates a different id for a different uid`() {
        val provider = DeviceIdProvider(InMemoryDeviceIdStore())

        val idA = provider.deviceIdFor("uid-A")
        val idB = provider.deviceIdFor("uid-B")

        assertNotEquals(idA, idB)
    }

    @Test
    fun `store persists across provider instances (simulating an app restart)`() {
        val store = InMemoryDeviceIdStore()
        val first = DeviceIdProvider(store).deviceIdFor("uid-1")

        val second = DeviceIdProvider(store).deviceIdFor("uid-1")

        assertEquals(first, second)
    }
}
