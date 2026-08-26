package com.findly.android.ui.map

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * specs/010-app-shell-and-screen-ux.md §3.4 (normative) — WHEN the camera policy re-runs, as pure
 * state independent of [MapCamera.target] (which decides WHERE). This is the regression this task
 * exists to prevent: today every marker-set change yanks the camera on both platforms; §10's test
 * checklist requires proving "a refresh with changed points yields *no* camera command" — see
 * `refresh after the initial load never runs again, even though the point set changed` below.
 */
class MapCameraPolicyTest {

    @Test
    fun `the very first load runs, even with zero located points`() {
        val decision = MapCameraPolicy.shouldRunOnLoadOrRefresh(CameraPolicyState.INITIAL, hasPoints = false)
        assertTrue(decision)
    }

    @Test
    fun `the very first load runs when it already has points`() {
        val decision = MapCameraPolicy.shouldRunOnLoadOrRefresh(CameraPolicyState.INITIAL, hasPoints = true)
        assertTrue(decision)
    }

    @Test
    fun `a refresh after an empty first load, still empty, does not run`() {
        val afterFirstLoad = MapCameraPolicy.nextState(CameraPolicyState.INITIAL, hasPoints = false)
        val decision = MapCameraPolicy.shouldRunOnLoadOrRefresh(afterFirstLoad, hasPoints = false)
        assertFalse(decision)
    }

    @Test
    fun `the first refresh that brings the first-ever point in from a zero-point open runs once`() {
        val afterEmptyFirstLoad = MapCameraPolicy.nextState(CameraPolicyState.INITIAL, hasPoints = false)
        val decision = MapCameraPolicy.shouldRunOnLoadOrRefresh(afterEmptyFirstLoad, hasPoints = true)
        assertTrue(decision)
    }

    @Test
    fun `refresh after the initial load never runs again, even though the point set changed`() {
        // First load already had a point (hasRunInitial=true, hadAnyPoint=true) — this is the
        // steady state every subsequent poll/manual refresh lands in.
        val steadyState = MapCameraPolicy.nextState(CameraPolicyState.INITIAL, hasPoints = true)

        // A refresh that changes the marker set (still non-empty, just different/more points)
        // MUST NOT re-run the policy — the exact bug 010 §3.4 exists to fix.
        val decision = MapCameraPolicy.shouldRunOnLoadOrRefresh(steadyState, hasPoints = true)
        assertFalse(decision)
    }

    @Test
    fun `refresh after the initial load never runs again even if points disappear`() {
        val steadyState = MapCameraPolicy.nextState(CameraPolicyState.INITIAL, hasPoints = true)
        val decision = MapCameraPolicy.shouldRunOnLoadOrRefresh(steadyState, hasPoints = false)
        assertFalse(decision)
    }

    @Test
    fun `nextState marks hasRunInitial true and remembers ever having had a point`() {
        val state = MapCameraPolicy.nextState(CameraPolicyState.INITIAL, hasPoints = true)
        assertEquals(CameraPolicyState(hasRunInitial = true, hadAnyPoint = true), state)
    }

    @Test
    fun `hadAnyPoint stays true once set, even across a later empty refresh`() {
        val withPoint = MapCameraPolicy.nextState(CameraPolicyState.INITIAL, hasPoints = true)
        val afterEmptyRefresh = MapCameraPolicy.nextState(withPoint, hasPoints = false)
        assertTrue(afterEmptyRefresh.hadAnyPoint)
    }

    // --- Freshest-device resolution (§3.5 / §10) ---

    @Test
    fun `freshest device is the one with the newest recordedAt`() {
        val older = device(id = "d1", recordedAt = "2026-08-26T09:00:00Z")
        val newer = device(id = "d2", recordedAt = "2026-08-26T10:30:00Z")
        val result = MapCameraPolicy.freshestLocatedDevice(listOf(older, newer))
        assertEquals("d2", result?.deviceId)
    }

    @Test
    fun `devices without a fix are never chosen even if present in the list`() {
        val noFix = device(id = "d1", recordedAt = null, hasLocationOverride = false)
        val withFix = device(id = "d2", recordedAt = "2026-08-26T09:00:00Z")
        val result = MapCameraPolicy.freshestLocatedDevice(listOf(noFix, withFix))
        assertEquals("d2", result?.deviceId)
    }

    @Test
    fun `no located device anywhere yields null, not a crash`() {
        val noFix = device(id = "d1", recordedAt = null, hasLocationOverride = false)
        val result = MapCameraPolicy.freshestLocatedDevice(listOf(noFix))
        assertNull(result)
    }

    @Test
    fun `an empty device list yields null`() {
        assertNull(MapCameraPolicy.freshestLocatedDevice(emptyList()))
    }

    private fun device(id: String, recordedAt: String?, hasLocationOverride: Boolean = true): RosterDeviceUi = RosterDeviceUi(
        deviceId = id,
        deviceName = "Device $id",
        lat = if (hasLocationOverride) 51.0 else null,
        lon = if (hasLocationOverride) 3.7 else null,
        recordedAt = recordedAt,
        batteryPct = null,
        trackingEnabled = true,
        syncIntervalMinutes = 15,
        isStale = false,
    )
}
