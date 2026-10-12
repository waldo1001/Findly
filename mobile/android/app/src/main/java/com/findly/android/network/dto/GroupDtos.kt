package com.findly.android.network.dto

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive

// 001-api-contract.md §12 — Groups (temporary; product model in specs/005-temporary-groups.md).

/** §12.1 request. `displayName` is REQUIRED only when the caller has no profile yet (§1.5.3
 * bootstrap) — optional otherwise, defaulting server-side to the profile's own (001 §12.1).
 *
 * [endsAt] is `null` for a group without an end date (005 §2.5) and deliberately has **no default
 * value**: `FindlyJson` has `encodeDefaults = false`, so a defaulted `null` would be dropped from
 * the wire and the backend answers 400 for a missing `endsAt` key (an omission must never silently
 * create a group that runs forever). Without a default the key is always serialized. */
@Serializable
data class CreateGroupRequestDto(
    val name: String,
    val endsAt: String?,
    val expiryPolicy: String,
    val displayName: String? = null,
)

/** The §12.2 list-item shape, reused verbatim as the §12.1/§12.4/§12.6 response (create/update/
 * join — specs/003-android-client.md §5's mapping table). `createdAt` is present only on create
 * (§12.1); `null` on the update/join responses, which omit it. `code` is `null` once the group
 * is past `endsAt` (005 §2.3 — the join-code row is deleted). */
@Serializable
data class GroupDto(
    val groupId: String,
    val name: String,
    /** `null` = no end date (005 §2.5). */
    val endsAt: String?,
    val expiryPolicy: String,
    val state: String,
    val role: String,
    val memberCount: Int,
    val code: String? = null,
    val createdAt: String? = null,
)

@Serializable
data class ListGroupsResponseDto(
    val groups: List<GroupDto>,
)

/** A roster entry (§12.3). Always fully populated when present — unlike [GroupDto], there is no
 * partial-field variant of this one. */
@Serializable
data class GroupMemberDto(
    val userId: String,
    val displayName: String,
    val role: String,
    val joinedAt: String,
)

/** §12.3 — the §12.2 item plus the roster. `members` is `null` for non-owner members during
 * `grace` (`state: "ended"`) — roster hidden per 005 §2.3; the owner and `archived` groups always
 * get the full roster. */
@Serializable
data class GroupDetailDto(
    val groupId: String,
    val name: String,
    /** `null` = no end date (005 §2.5). */
    val endsAt: String?,
    val expiryPolicy: String,
    val state: String,
    val role: String,
    val memberCount: Int,
    val code: String? = null,
    val createdAt: String,
    val members: List<GroupMemberDto>? = null,
)

/** §12.4 request — at least one field. [requireAtLeastOneField] enforces this client-side before
 * the call is made, mirroring [UpdateMemberRequestDto]/[UpdateDeviceRequestDto].
 *
 * **Absent vs. present-null (001 §12.4):** an absent `endsAt` key leaves the end date unchanged, a
 * key present with `null` removes it (005 §2.5). A plain `String?` cannot express both, and with
 * `encodeDefaults = false` a defaulted null is never sent. So [endsAt] is a [JsonElement]?:
 * Kotlin `null` (the default) = key omitted; [JsonNull] = key sent as JSON `null`; a
 * [JsonPrimitive] string = an ISO instant. Build instances with [rename], [setEndsAt] and
 * [removeEndDate] rather than the constructor. */
@Serializable
data class UpdateGroupRequestDto(
    val name: String? = null,
    val endsAt: JsonElement? = null,
) {
    fun requireAtLeastOneField(): UpdateGroupRequestDto = apply {
        require(name != null || endsAt != null) {
            "UpdateGroupRequestDto requires at least one of name/endsAt (001 §12.4)"
        }
    }

    companion object {
        fun rename(name: String) = UpdateGroupRequestDto(name = name)
        fun setEndsAt(endsAtIso: String) = UpdateGroupRequestDto(endsAt = JsonPrimitive(endsAtIso))
        fun removeEndDate() = UpdateGroupRequestDto(endsAt = JsonNull)
    }
}

/** §12.6 request. `displayName` becomes the caller's **per-group** display name (005 §1) — same
 * REQUIRED-if-no-profile/optional-otherwise rule as [CreateGroupRequestDto.displayName]. */
@Serializable
data class JoinGroupRequestDto(
    val code: String,
    val displayName: String? = null,
)

/** §12.7 response. */
@Serializable
data class RotateGroupCodeResponseDto(
    val code: String,
    val rotatedAt: String,
)

/** §12.10 — position-only (005 §3): no `deviceId`/`deviceName`/`batteryPct`/`source`/altitude/
 * speed/bearing anywhere in this neighborhood, unlike §5.2's `LatestDeviceDto`. */
@Serializable
data class GroupPositionDto(
    val lat: Double,
    val lon: Double,
    val accuracyM: Double,
    val recordedAt: String,
    val receivedAt: String,
    val isStale: Boolean,
)

/** §12.10 — one entry per group member; `location` is `null` when the member has no position yet
 * (roster parity with §5.2 — every member appears, present or not). */
@Serializable
data class GroupMemberLocationDto(
    val userId: String,
    val displayName: String,
    val role: String,
    val location: GroupPositionDto? = null,
)

@Serializable
data class GroupLatestLocationsResponseDto(
    val members: List<GroupMemberLocationDto>,
)
