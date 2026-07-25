package com.findly.android.network.ports

import com.findly.android.network.ApiResult
import com.findly.android.network.dto.GroupDetailDto
import com.findly.android.network.dto.GroupDto
import com.findly.android.network.dto.GroupLatestLocationsResponseDto
import com.findly.android.network.dto.ListGroupsResponseDto
import com.findly.android.network.dto.RotateGroupCodeResponseDto
import com.findly.android.network.dto.UpdateGroupRequestDto

/** 001-api-contract.md §12 — Groups (temporary; product model in specs/005-temporary-groups.md). */
interface GroupsApi {

    /** Bootstraps a profile if the caller has none (§1.5.3) — [displayName] is REQUIRED then,
     * optional otherwise (defaults server-side to the profile's). */
    suspend fun createGroup(
        name: String,
        endsAt: String,
        expiryPolicy: String,
        displayName: String? = null,
    ): ApiResult<GroupDto>

    /** Expired groups are filtered out server-side; `ended`/`archived` ones appear with their
     * state (§12.2). */
    suspend fun listGroups(): ApiResult<ListGroupsResponseDto>

    /** §12.3 — the caller must be a group member; non-membership is masked as `GROUP_NOT_FOUND`
     * (§12), same as a nonexistent `groupId`. */
    suspend fun getGroup(groupId: String): ApiResult<GroupDetailDto>

    /** Owner-only; [request] must set at least one of `name`/`endsAt` (§12.4). */
    suspend fun updateGroup(groupId: String, request: UpdateGroupRequestDto): ApiResult<GroupDto>

    /** Bare 204 (§12.5) — see [ApiResult.Success.features] doc for why it's `null` here. Owner-
     * only; immediate hard delete regardless of state/policy. */
    suspend fun deleteGroup(groupId: String): ApiResult<Unit>

    /** Bootstraps a profile if the caller has none (§1.5.3) — [displayName] is REQUIRED then,
     * optional otherwise; becomes the caller's per-group display name (005 §1). */
    suspend fun joinGroup(code: String, displayName: String? = null): ApiResult<GroupDto>

    /** Owner-only. The old code stops working instantly (§12.7). */
    suspend fun rotateGroupCode(groupId: String): ApiResult<RotateGroupCodeResponseDto>

    /** Bare 204 (§12.8). The owner cannot leave (`400 VALIDATION_FAILED`, `details.reason:
     * "ownerCannotLeave"`) — they end (§12.4) or delete (§12.5) instead. */
    suspend fun leaveGroup(groupId: String): ApiResult<Unit>

    /** Bare 204 (§12.9). Owner-only. Unknown/non-member `userId` → `404 MEMBER_NOT_FOUND`; the
     * owner cannot kick themselves → `400 VALIDATION_FAILED`, `details.reason:
     * "ownerCannotLeave"`. */
    suspend fun removeGroupMember(groupId: String, userId: String): ApiResult<Unit>

    /** §12.10 — position-only (005 §3); only on `active` groups, else `410 GROUP_EXPIRED`. */
    suspend fun getGroupLatestLocations(groupId: String): ApiResult<GroupLatestLocationsResponseDto>
}
