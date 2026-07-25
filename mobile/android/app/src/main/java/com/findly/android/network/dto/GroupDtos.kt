package com.findly.android.network.dto

import kotlinx.serialization.Serializable

// 001-api-contract.md §12 — Groups (temporary; product model in specs/005-temporary-groups.md).

/** §12.1 request. `displayName` is REQUIRED only when the caller has no profile yet (§1.5.3
 * bootstrap) — optional otherwise, defaulting server-side to the profile's own (001 §12.1). */
@Serializable
data class CreateGroupRequestDto(
    val name: String,
    val endsAt: String,
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
    val endsAt: String,
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
    val endsAt: String,
    val expiryPolicy: String,
    val state: String,
    val role: String,
    val memberCount: Int,
    val code: String? = null,
    val createdAt: String,
    val members: List<GroupMemberDto>? = null,
)

/** §12.4 request — at least one field. [requireAtLeastOneField] enforces this client-side before
 * the call is made, mirroring [UpdateMemberRequestDto]/[UpdateDeviceRequestDto]. */
@Serializable
data class UpdateGroupRequestDto(
    val name: String? = null,
    val endsAt: String? = null,
) {
    fun requireAtLeastOneField(): UpdateGroupRequestDto = apply {
        require(name != null || endsAt != null) {
            "UpdateGroupRequestDto requires at least one of name/endsAt (001 §12.4)"
        }
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
