package com.findly.android.fakes

import com.findly.android.network.ApiResult
import com.findly.android.network.dto.AcceptInviteResponseDto
import com.findly.android.network.dto.CallerRoleDto
import com.findly.android.network.dto.CreateFamilyResponseDto
import com.findly.android.network.dto.CreateInviteResponseDto
import com.findly.android.network.dto.FamilyMeResponseDto
import com.findly.android.network.dto.MemberDto
import com.findly.android.network.dto.UpdateMemberRequestDto
import com.findly.android.network.ports.FamilyApi

/** Test fake — mirrors the backend's `test/fakes/` convention (backend/README.md). Used by the
 * A2 settings/invites ViewModel tests. */
class FakeFamilyApi : FamilyApi {
    val createFamilyCalls = mutableListOf<Pair<String, String>>()
    val createInviteCalls = mutableListOf<Pair<String, String?>>()
    val acceptInviteCalls = mutableListOf<Pair<String, String>>()
    val updateMemberCalls = mutableListOf<Pair<String, UpdateMemberRequestDto>>()
    val removeMemberCalls = mutableListOf<String>()
    var getMyFamilyCallCount = 0
        private set

    /** A21: `POST /families` (001 §3.1) — previously unexercised ("not exercised by A2 tests"),
     * since no screen/ViewModel called [FamilyApi.createFamily] until [CreateFamilyStateHolder]. */
    var createFamilyResult: ApiResult<CreateFamilyResponseDto> = ApiResult.Success(
        CreateFamilyResponseDto(
            familyId = "fam_test",
            familyName = "Wauters",
            member = MemberDto("uid-parent", "parent", "Eric"),
        ),
        features = defaultFeatures(),
    )

    var getMyFamilyResult: ApiResult<FamilyMeResponseDto> = ApiResult.Success(
        FamilyMeResponseDto(
            familyId = "fam_test",
            familyName = "Wauters",
            createdAt = "2026-07-01T00:00:00Z",
            me = CallerRoleDto("uid-parent", "parent"),
            members = listOf(
                MemberDto("uid-parent", "parent", "Eric", "2026-07-01T00:00:00Z"),
                MemberDto("uid-member", "member", "Noor", "2026-07-02T00:00:00Z"),
            ),
        ),
        features = defaultFeatures(),
    )

    var createInviteResult: ApiResult<CreateInviteResponseDto> = ApiResult.Success(
        CreateInviteResponseDto(inviteCode = "7F3K9QRZ", role = "member", expiresAt = "2026-07-22T10:00:00Z"),
        features = defaultFeatures(),
    )

    var acceptInviteResult: ApiResult<AcceptInviteResponseDto> = ApiResult.Success(
        AcceptInviteResponseDto(familyId = "fam_test", familyName = "Wauters", role = "member"),
        features = defaultFeatures(),
    )

    var updateMemberResult: ApiResult<MemberDto> = ApiResult.Success(
        MemberDto("uid-member", "parent", "Noor W.", "2026-07-02T00:00:00Z"),
        features = defaultFeatures(),
    )

    var removeMemberResult: ApiResult<Unit> = ApiResult.Success(Unit, features = null)

    override suspend fun createFamily(familyName: String, displayName: String): ApiResult<CreateFamilyResponseDto> {
        createFamilyCalls.add(familyName to displayName)
        return createFamilyResult
    }

    override suspend fun getMyFamily(): ApiResult<FamilyMeResponseDto> {
        getMyFamilyCallCount++
        return getMyFamilyResult
    }

    override suspend fun createInvite(role: String, emailHint: String?): ApiResult<CreateInviteResponseDto> {
        createInviteCalls.add(role to emailHint)
        return createInviteResult
    }

    override suspend fun acceptInvite(inviteCode: String, displayName: String): ApiResult<AcceptInviteResponseDto> {
        acceptInviteCalls.add(inviteCode to displayName)
        return acceptInviteResult
    }

    override suspend fun updateMember(userId: String, request: UpdateMemberRequestDto): ApiResult<MemberDto> {
        updateMemberCalls.add(userId to request)
        return updateMemberResult
    }

    override suspend fun removeMember(userId: String): ApiResult<Unit> {
        removeMemberCalls.add(userId)
        return removeMemberResult
    }
}
