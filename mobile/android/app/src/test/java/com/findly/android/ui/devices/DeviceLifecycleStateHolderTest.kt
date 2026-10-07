package com.findly.android.ui.devices

import com.findly.android.fakes.FakeDevicesApi
import com.findly.android.fakes.defaultFeatures
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.DeviceDto
import com.findly.android.network.dto.FamilyDeviceDto
import com.findly.android.network.dto.ListDevicesResponseDto
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** A61 — [DevicesStateHolder]'s device-lifecycle behavior (specs/011 §1.1, §2, §4.4). */
class DeviceLifecycleStateHolderTest {

    private fun device(
        id: String,
        owner: String = "u-other",
        dormant: Boolean = false,
        nudge: Boolean = true,
    ) = FamilyDeviceDto(
        deviceId = id,
        ownerUserId = owner,
        platform = "android",
        deviceName = "Name $id",
        model = "M",
        appVersion = "1",
        syncIntervalMinutes = 15,
        trackingEnabled = true,
        pushInvalid = false,
        ownerDisplayName = "Someone",
        lastSeenAt = "2026-07-19T09:00:00Z",
        isDormant = dormant,
        staleNudgeEnabled = nudge,
    )

    private fun api(vararg devices: FamilyDeviceDto) = FakeDevicesApi().apply {
        listDevicesResult = ApiResult.Success(ListDevicesResponseDto(devices.toList()), defaultFeatures())
    }

    private fun notFound() = ApiResult.Failure(ApiError.DeviceNotFound("x", null))
    private fun forbidden() = ApiResult.Failure(ApiError.AuthForbidden("x", null))

    private fun cards(holder: DevicesStateHolder) = (holder.state.value as DevicesUiState.Content).devices

    @Test
    fun `cards carry dormant and ownership flags and the remove capability`() = runTest {
        val a = api(device("d1", owner = "me"), device("d2", owner = "u-other", dormant = true), device("d3", owner = "me"))
        val holder = DevicesStateHolder(a, isParent = false, scope = backgroundScope, localDeviceId = { "d3" }, localUserId = { "me" })
        runCurrent()

        val byId = cards(holder).associateBy { it.deviceId }
        assertTrue(byId.getValue("d1").isOwnedByCaller)
        assertTrue(byId.getValue("d1").canRemove) // owned, not this device
        assertFalse(byId.getValue("d3").canRemove) // this device
        assertFalse(byId.getValue("d2").canRemove) // not parent, not owner
        assertTrue(byId.getValue("d2").isDormant)
        assertFalse(byId.getValue("d1").isDormant)
    }

    @Test
    fun `a parent can remove any other device but not this one`() = runTest {
        val a = api(device("d1"), device("d2"))
        val holder = DevicesStateHolder(a, isParent = true, scope = backgroundScope, localDeviceId = { "d2" }, localUserId = { "me" })
        runCurrent()

        assertTrue(cards(holder).single { it.deviceId == "d1" }.canRemove)
        assertFalse(cards(holder).single { it.deviceId == "d2" }.canRemove)
    }

    @Test
    fun `requestRemove opens the confirmation and cancelRemove closes it without a network call`() = runTest {
        val a = api(device("d1"))
        val holder = DevicesStateHolder(a, isParent = true, scope = backgroundScope, localUserId = { "me" })
        runCurrent()

        holder.requestRemove("d1")
        assertTrue(cards(holder).single().isConfirmingRemoval)
        holder.cancelRemove("d1")
        assertFalse(cards(holder).single().isConfirmingRemoval)
        assertTrue(a.deleteDeviceCalls.isEmpty())
    }

    @Test
    fun `requestRemove is ignored when the action is not available`() = runTest {
        val a = api(device("d1", owner = "u-other"))
        val holder = DevicesStateHolder(a, isParent = false, scope = backgroundScope, localUserId = { "me" })
        runCurrent()

        holder.requestRemove("d1")
        assertFalse(cards(holder).single().isConfirmingRemoval)
    }

    @Test
    fun `confirmRemove on 204 drops the card`() = runTest {
        val a = api(device("d1"), device("d2"))
        val holder = DevicesStateHolder(a, isParent = true, scope = backgroundScope, localUserId = { "me" })
        runCurrent()
        holder.requestRemove("d1")

        holder.confirmRemove("d1")

        assertEquals(listOf("d1"), a.deleteDeviceCalls)
        assertEquals(listOf("d2"), cards(holder).map { it.deviceId })
    }

    @Test
    fun `confirmRemove with DEVICE_NOT_FOUND counts as success - no error and the list is refreshed`() = runTest {
        val a = api(device("d1"), device("d2")).apply { deleteDeviceResult = notFound() }
        val holder = DevicesStateHolder(a, isParent = true, scope = backgroundScope, localUserId = { "me" })
        runCurrent()
        val loadsBefore = a.listDevicesCallCount
        holder.requestRemove("d1")

        holder.confirmRemove("d1")

        assertEquals(loadsBefore + 1, a.listDevicesCallCount)
        assertTrue(cards(holder).all { it.error == null })
    }

    @Test
    fun `confirmRemove with AUTH_FORBIDDEN renders the card error and keeps the card`() = runTest {
        val a = api(device("d1")).apply { deleteDeviceResult = forbidden() }
        val holder = DevicesStateHolder(a, isParent = true, scope = backgroundScope, localUserId = { "me" })
        runCurrent()
        holder.requestRemove("d1")

        holder.confirmRemove("d1")

        val card = cards(holder).single()
        assertEquals("Only a parent can remove another member's device.", card.error)
        assertFalse(card.isConfirmingRemoval)
        assertFalse(card.isMutating)
    }

    @Test
    fun `confirmRemove without permission sends nothing`() = runTest {
        val a = api(device("d1", owner = "u-other"))
        val holder = DevicesStateHolder(a, isParent = false, scope = backgroundScope, localUserId = { "me" })
        runCurrent()

        holder.confirmRemove("d1")

        assertTrue(a.deleteDeviceCalls.isEmpty())
    }

    @Test
    fun `nudge toggle on an owned device commits one PATCH with only staleNudgeEnabled, even for non-parents`() = runTest {
        val a = api(device("d1", owner = "me")).apply {
            updateDeviceResult = ApiResult.Success(
                DeviceDto("d1", "me", "android", "Name d1", "M", "1", 15, true, false, staleNudgeEnabled = false),
                features = null,
            )
        }
        val holder = DevicesStateHolder(a, isParent = false, scope = backgroundScope, localUserId = { "me" })
        runCurrent()

        holder.setStaleNudge("d1", false)

        assertEquals(1, a.updateDeviceCalls.size)
        val (id, request) = a.updateDeviceCalls.single()
        assertEquals("d1", id)
        assertEquals(false, request.staleNudgeEnabled)
        assertNull(request.trackingEnabled)
        assertNull(request.syncIntervalMinutes)
        assertNull(request.deviceName)
        assertNull(request.pushToken)
        assertFalse(cards(holder).single().staleNudgeEnabled)
    }

    @Test
    fun `nudge toggle on someone else's device sends nothing - a parent cannot set it for others`() = runTest {
        val a = api(device("d1", owner = "u-other"))
        val holder = DevicesStateHolder(a, isParent = true, scope = backgroundScope, localUserId = { "me" })
        runCurrent()

        holder.setStaleNudge("d1", false)

        assertTrue(a.updateDeviceCalls.isEmpty())
        assertTrue(cards(holder).single().staleNudgeEnabled)
    }

    @Test
    fun `nudge toggle failure renders on the card and leaves the value unchanged`() = runTest {
        val a = api(device("d1", owner = "me")).apply { updateDeviceResult = forbidden() }
        val holder = DevicesStateHolder(a, isParent = false, scope = backgroundScope, localUserId = { "me" })
        runCurrent()

        holder.setStaleNudge("d1", false)

        val card = cards(holder).single()
        assertTrue(card.staleNudgeEnabled)
        assertTrue(card.error != null)
    }
}
