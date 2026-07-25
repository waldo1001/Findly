package com.findly.android.fakes

import com.findly.android.network.ApiResult
import com.findly.android.network.dto.GroupDetailDto
import com.findly.android.network.dto.GroupDto
import com.findly.android.network.dto.GroupLatestLocationsResponseDto
import com.findly.android.network.dto.GroupMemberDto
import com.findly.android.network.dto.ListGroupsResponseDto
import com.findly.android.network.dto.RotateGroupCodeResponseDto
import com.findly.android.network.dto.UpdateGroupRequestDto
import com.findly.android.network.ports.GroupsApi

/** Test fake — mirrors the backend's `test/fakes/` convention (backend/README.md), same shape as
 * [FakeFamilyApi]/[FakeGeofenceApi]. Used by A5's groups-screen StateHolder tests
 * (specs/003-android-client.md §12.2, §14/§16). */
class FakeGroupsApi : GroupsApi {

    data class CreateGroupCall(val name: String, val endsAt: String, val expiryPolicy: String, val displayName: String?)

    val createGroupCalls = mutableListOf<CreateGroupCall>()
    val getGroupCalls = mutableListOf<String>()
    val updateGroupCalls = mutableListOf<Pair<String, UpdateGroupRequestDto>>()
    val deleteGroupCalls = mutableListOf<String>()
    val joinGroupCalls = mutableListOf<Pair<String, String?>>()
    val rotateGroupCodeCalls = mutableListOf<String>()
    val leaveGroupCalls = mutableListOf<String>()
    val removeGroupMemberCalls = mutableListOf<Pair<String, String>>()
    val getGroupLatestLocationsCalls = mutableListOf<String>()
    var listGroupsCallCount = 0
        private set

    var createGroupResult: ApiResult<GroupDto> = ApiResult.Success(sampleGroupDto(), features = groupsFeatures())
    var listGroupsResult: ApiResult<ListGroupsResponseDto> =
        ApiResult.Success(ListGroupsResponseDto(groups = emptyList()), features = groupsFeatures())
    var getGroupResult: ApiResult<GroupDetailDto> = ApiResult.Success(sampleGroupDetailDto(), features = groupsFeatures())
    var updateGroupResult: ApiResult<GroupDto> = ApiResult.Success(sampleGroupDto(), features = groupsFeatures())
    var deleteGroupResult: ApiResult<Unit> = ApiResult.Success(Unit, features = null)
    var joinGroupResult: ApiResult<GroupDto> = ApiResult.Success(sampleGroupDto(role = "member"), features = groupsFeatures())
    var rotateGroupCodeResult: ApiResult<RotateGroupCodeResponseDto> =
        ApiResult.Success(RotateGroupCodeResponseDto("9XPT4WKA", "2026-07-21T10:05:00Z"), features = groupsFeatures())
    var leaveGroupResult: ApiResult<Unit> = ApiResult.Success(Unit, features = null)
    var removeGroupMemberResult: ApiResult<Unit> = ApiResult.Success(Unit, features = null)
    var getGroupLatestLocationsResult: ApiResult<GroupLatestLocationsResponseDto> =
        ApiResult.Success(GroupLatestLocationsResponseDto(members = emptyList()), features = groupsFeatures())

    override suspend fun createGroup(
        name: String,
        endsAt: String,
        expiryPolicy: String,
        displayName: String?,
    ): ApiResult<GroupDto> {
        createGroupCalls.add(CreateGroupCall(name, endsAt, expiryPolicy, displayName))
        return createGroupResult
    }

    override suspend fun listGroups(): ApiResult<ListGroupsResponseDto> {
        listGroupsCallCount++
        return listGroupsResult
    }

    override suspend fun getGroup(groupId: String): ApiResult<GroupDetailDto> {
        getGroupCalls.add(groupId)
        return getGroupResult
    }

    override suspend fun updateGroup(groupId: String, request: UpdateGroupRequestDto): ApiResult<GroupDto> {
        updateGroupCalls.add(groupId to request)
        return updateGroupResult
    }

    override suspend fun deleteGroup(groupId: String): ApiResult<Unit> {
        deleteGroupCalls.add(groupId)
        return deleteGroupResult
    }

    override suspend fun joinGroup(code: String, displayName: String?): ApiResult<GroupDto> {
        joinGroupCalls.add(code to displayName)
        return joinGroupResult
    }

    override suspend fun rotateGroupCode(groupId: String): ApiResult<RotateGroupCodeResponseDto> {
        rotateGroupCodeCalls.add(groupId)
        return rotateGroupCodeResult
    }

    override suspend fun leaveGroup(groupId: String): ApiResult<Unit> {
        leaveGroupCalls.add(groupId)
        return leaveGroupResult
    }

    override suspend fun removeGroupMember(groupId: String, userId: String): ApiResult<Unit> {
        removeGroupMemberCalls.add(groupId to userId)
        return removeGroupMemberResult
    }

    override suspend fun getGroupLatestLocations(groupId: String): ApiResult<GroupLatestLocationsResponseDto> {
        getGroupLatestLocationsCalls.add(groupId)
        return getGroupLatestLocationsResult
    }
}

fun sampleGroupDto(role: String = "owner"): GroupDto = GroupDto(
    groupId = "grp_9J2Kq7Lm3NpR5sTvWxYz",
    name = "Festival crew",
    endsAt = "2026-08-02T22:00:00Z",
    expiryPolicy = "delete",
    state = "active",
    role = role,
    memberCount = 1,
    code = "7F3K9QRZ",
    createdAt = "2026-07-21T10:00:00Z",
)

fun sampleGroupDetailDto(role: String = "owner", members: List<GroupMemberDto>? = null): GroupDetailDto = GroupDetailDto(
    groupId = "grp_9J2Kq7Lm3NpR5sTvWxYz",
    name = "Festival crew",
    endsAt = "2026-08-02T22:00:00Z",
    expiryPolicy = "delete",
    state = "active",
    role = role,
    memberCount = 1,
    code = "7F3K9QRZ",
    createdAt = "2026-07-21T10:00:00Z",
    members = members ?: listOf(GroupMemberDto("u1", "Eric", "owner", "2026-07-21T10:00:00Z")),
)
