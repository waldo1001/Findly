package com.findly.android.network.dto

import com.findly.android.network.FindlyJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The `encodeDefaults = false` trap (A66, 001 §12.1/§12.4): a defaulted `null` would be dropped
 * from the wire, and the backend rejects a missing `endsAt` key on create (an omission must never
 * silently create a group that runs forever). */
class GroupDtosSerializationTest {

    @Test
    fun `create request with no end date encodes endsAt as an explicit null`() {
        val json = FindlyJson.encodeToString(
            CreateGroupRequestDto.serializer(),
            CreateGroupRequestDto(name = "Standing crew", endsAt = null, expiryPolicy = "delete"),
        )

        assertTrue("endsAt:null must be on the wire: $json", json.contains("\"endsAt\":null"))
    }

    @Test
    fun `create request with an end date encodes the ISO instant`() {
        val json = FindlyJson.encodeToString(
            CreateGroupRequestDto.serializer(),
            CreateGroupRequestDto(name = "Festival", endsAt = "2026-08-02T22:00:00Z", expiryPolicy = "grace"),
        )

        assertTrue(json, json.contains("\"endsAt\":\"2026-08-02T22:00:00Z\""))
    }

    @Test
    fun `PATCH remove-end-date serializes the endsAt key with null`() {
        val json = FindlyJson.encodeToString(UpdateGroupRequestDto.serializer(), UpdateGroupRequestDto.removeEndDate())

        assertEquals("{\"endsAt\":null}", json)
    }

    @Test
    fun `PATCH rename-only does not send an endsAt key (absent leaves it unchanged)`() {
        val json = FindlyJson.encodeToString(UpdateGroupRequestDto.serializer(), UpdateGroupRequestDto.rename("New name"))

        assertEquals("{\"name\":\"New name\"}", json)
        assertFalse(json.contains("endsAt"))
    }

    @Test
    fun `PATCH set-end-date serializes the instant and no name key`() {
        val json = FindlyJson.encodeToString(
            UpdateGroupRequestDto.serializer(),
            UpdateGroupRequestDto.setEndsAt("2026-08-03T22:00:00Z"),
        )

        assertEquals("{\"endsAt\":\"2026-08-03T22:00:00Z\"}", json)
    }

    @Test
    fun `group response with endsAt null decodes`() {
        val dto = FindlyJson.decodeFromString(
            GroupDto.serializer(),
            """{"groupId":"grp_1","name":"Standing","endsAt":null,"expiryPolicy":"delete","state":"active",
               "role":"owner","memberCount":1,"code":"7F3K9QRZ"}""",
        )
        assertNull(dto.endsAt)

        val detail = FindlyJson.decodeFromString(
            GroupDetailDto.serializer(),
            """{"groupId":"grp_1","name":"Standing","endsAt":null,"expiryPolicy":"delete","state":"active",
               "role":"owner","memberCount":1,"code":"7F3K9QRZ","createdAt":"2026-07-21T10:00:00Z"}""",
        )
        assertNull(detail.endsAt)
    }
}
