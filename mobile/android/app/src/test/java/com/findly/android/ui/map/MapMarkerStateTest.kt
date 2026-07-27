package com.findly.android.ui.map

import com.findly.android.ui.designsystem.components.FindlyMapMarkerState
import com.findly.android.ui.groups.GroupMapMemberUi
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * A12 (specs/003-android-client.md §12; design/findly-design-system/README.md's `MapMarkerBubble`
 * spec: "Online = solid fill + success pointer tail; stale = desaturated + dashed ring;
 * no-location-yet = neutral '?' chip"). Pure derivation, no Compose/Android runtime needed —
 * [markerStateFor] must NOT recompute staleness itself, only render what the server already
 * decided (001-api-contract.md §5.2's `isStale` formula is computed server-side).
 */
class MapMarkerStateTest {

    @Test
    fun `no location yet yields NoLocation regardless of isStale`() {
        assertEquals(FindlyMapMarkerState.NoLocation, markerStateFor(hasLocation = false, isStale = null))
        assertEquals(FindlyMapMarkerState.NoLocation, markerStateFor(hasLocation = false, isStale = true))
        assertEquals(FindlyMapMarkerState.NoLocation, markerStateFor(hasLocation = false, isStale = false))
    }

    @Test
    fun `server isStale true yields Stale`() {
        assertEquals(FindlyMapMarkerState.Stale, markerStateFor(hasLocation = true, isStale = true))
    }

    @Test
    fun `server isStale false yields Online`() {
        assertEquals(FindlyMapMarkerState.Online, markerStateFor(hasLocation = true, isStale = false))
    }

    @Test
    fun `a null isStale alongside a known location defaults to Online without recomputing staleness`() {
        assertEquals(FindlyMapMarkerState.Online, markerStateFor(hasLocation = true, isStale = null))
    }

    @Test
    fun `RosterDeviceUi bridges to the same marker state as the family map roster`() {
        val device = RosterDeviceUi(
            deviceId = "d1",
            deviceName = "Pixel 8",
            lat = 51.0543,
            lon = 3.7174,
            recordedAt = "2026-07-19T09:05:12Z",
            batteryPct = 78,
            trackingEnabled = true,
            syncIntervalMinutes = 15,
            isStale = true,
        )
        assertEquals(FindlyMapMarkerState.Stale, device.markerState)

        val neverReported = device.copy(lat = null, lon = null, isStale = null)
        assertEquals(FindlyMapMarkerState.NoLocation, neverReported.markerState)

        val fresh = device.copy(isStale = false)
        assertEquals(FindlyMapMarkerState.Online, fresh.markerState)
    }

    @Test
    fun `GroupMapMemberUi bridges to the same marker state as the group map roster (001 §12,10, position-only)`() {
        val member = GroupMapMemberUi(
            userId = "u1",
            displayName = "Eric",
            role = "owner",
            lat = 51.0543,
            lon = 3.7174,
            accuracyM = 15.0,
            recordedAt = "2026-07-21T09:58:00Z",
            isStale = false,
        )
        assertEquals(FindlyMapMarkerState.Online, member.markerState)

        val noLocation = member.copy(lat = null, lon = null, isStale = null)
        assertEquals(FindlyMapMarkerState.NoLocation, noLocation.markerState)

        val stale = member.copy(isStale = true)
        assertEquals(FindlyMapMarkerState.Stale, stale.markerState)
    }
}
