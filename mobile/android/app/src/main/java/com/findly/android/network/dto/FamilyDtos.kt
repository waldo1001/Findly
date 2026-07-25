package com.findly.android.network.dto

import kotlinx.serialization.Serializable

// 001-api-contract.md §3 — Family management.

@Serializable
data class CreateFamilyRequestDto(
    val familyName: String,
    val displayName: String,
)

@Serializable
data class CreateFamilyResponseDto(
    val familyId: String,
    val familyName: String,
    val member: MemberDto,
)

/** Shared member shape (§3.1's `member` and §3.2/§3.5's roster entries). `joinedAt` is absent
 * from §3.1's response and present in §3.2/§3.5 — nullable covers both without two data classes. */
@Serializable
data class MemberDto(
    val userId: String,
    val role: String,
    val displayName: String,
    val joinedAt: String? = null,
)

@Serializable
data class CallerRoleDto(
    val userId: String,
    val role: String,
)

@Serializable
data class FamilyMeResponseDto(
    val familyId: String,
    val familyName: String,
    val createdAt: String,
    val me: CallerRoleDto,
    val members: List<MemberDto>,
)

@Serializable
data class CreateInviteRequestDto(
    val role: String,
    val emailHint: String? = null,
)

@Serializable
data class CreateInviteResponseDto(
    val inviteCode: String,
    val role: String,
    val expiresAt: String,
)

@Serializable
data class AcceptInviteRequestDto(
    val inviteCode: String,
    val displayName: String,
)

@Serializable
data class AcceptInviteResponseDto(
    val familyId: String,
    val familyName: String,
    val role: String,
)

/** §3.5 — "request: at least one field". Both nullable; [requireAtLeastOneField] enforces the
 * rule client-side before the call is made (the server enforces it regardless). */
@Serializable
data class UpdateMemberRequestDto(
    val role: String? = null,
    val displayName: String? = null,
) {
    fun requireAtLeastOneField(): UpdateMemberRequestDto = apply {
        require(role != null || displayName != null) {
            "UpdateMemberRequestDto requires at least one of role/displayName (001 §3.5)"
        }
    }
}
