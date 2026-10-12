package com.findly.android.network.dto

import org.junit.Assert.assertThrows
import org.junit.Test

class RequestValidationTest {

    @Test
    fun `UpdateMemberRequestDto requires at least one field`() {
        assertThrows(IllegalArgumentException::class.java) {
            UpdateMemberRequestDto(role = null, displayName = null).requireAtLeastOneField()
        }
        // Does not throw when at least one field is set.
        UpdateMemberRequestDto(role = "parent", displayName = null).requireAtLeastOneField()
        UpdateMemberRequestDto(role = null, displayName = "Noor W.").requireAtLeastOneField()
    }

    @Test
    fun `UpdateDeviceRequestDto requires at least one field`() {
        assertThrows(IllegalArgumentException::class.java) {
            UpdateDeviceRequestDto().requireAtLeastOneField()
        }
        UpdateDeviceRequestDto(pushToken = "new-token").requireAtLeastOneField()
    }

    @Test
    fun `CreateLocateRequestRequestDto requires exactly one target`() {
        assertThrows(IllegalArgumentException::class.java) {
            CreateLocateRequestRequestDto(targetUserId = null, targetDeviceId = null).requireExactlyOneTarget()
        }
        assertThrows(IllegalArgumentException::class.java) {
            CreateLocateRequestRequestDto(targetUserId = "u2", targetDeviceId = "d1").requireExactlyOneTarget()
        }
        CreateLocateRequestRequestDto(targetUserId = "u2", targetDeviceId = null).requireExactlyOneTarget()
        CreateLocateRequestRequestDto(targetUserId = null, targetDeviceId = "d1").requireExactlyOneTarget()
    }

    @Test
    fun `UpdateGroupRequestDto requires at least one field`() {
        assertThrows(IllegalArgumentException::class.java) {
            UpdateGroupRequestDto().requireAtLeastOneField()
        }
        // Does not throw when at least one field is set — including an explicit "remove the end date".
        UpdateGroupRequestDto.rename("Festival crew 2026").requireAtLeastOneField()
        UpdateGroupRequestDto.setEndsAt("2026-08-03T22:00:00Z").requireAtLeastOneField()
        UpdateGroupRequestDto.removeEndDate().requireAtLeastOneField()
    }
}
