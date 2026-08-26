package com.findly.android.ui.family

import com.findly.android.network.ApiResult
import com.findly.android.network.dto.CreateFamilyResponseDto
import com.findly.android.network.ports.FamilyApi
import com.findly.android.network.userMessage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The create-family screen's pure state machine (001-api-contract.md §3.1). No constructor
 * [kotlinx.coroutines.CoroutineScope] is needed — same shape as
 * [com.findly.android.ui.groups.CreateGroupStateHolder]/[com.findly.android.ui.invites.InvitesStateHolder]
 * — a user-initiated form submission only.
 *
 * **A21**: this is the client's *only* entry point for `POST /families` — the endpoint existed
 * solely in the networking layer (`network/ports/FamilyApi.kt`) with no screen/ViewModel calling
 * it, leaving every brand-new user with no way to bootstrap a `Users` profile row (001 §1.5.3).
 * Reachable both from a signed-in user with a family already (rare — the server rejects with
 * `409 FAMILY_ALREADY_MEMBER`, surfaced as an ordinary [CreateFamilyUiState.submitError]) and,
 * more importantly, from the profile-less first-run flow
 * ([com.findly.android.ui.onboarding.OnboardingScreen], specs/010-app-shell-and-screen-ux.md §2.2
 * — the retired `GroupsListUiState.ProfileNeeded`'s replacement) where this is one of the four
 * 001 §1.5.3 bootstrap paths.
 */
class CreateFamilyStateHolder(private val familyApi: FamilyApi) {

    private val _state = MutableStateFlow(CreateFamilyUiState())
    val state: StateFlow<CreateFamilyUiState> = _state.asStateFlow()

    /** Client-side mirror of 001 §3.1's validation (`familyName` 1-50 chars, `displayName`
     * 1-30 chars). Returns a user-facing message, or `null` if valid — the server remains
     * authoritative regardless (defense in depth, same convention as every other
     * `<Feature>StateHolder.validate`). */
    fun validate(familyName: String, displayName: String): String? = when {
        familyName.isBlank() || familyName.length > 50 -> "Family name must be 1-50 characters"
        displayName.isBlank() || displayName.length > 30 -> "Enter a display name"
        else -> null
    }

    /** Validates, then — only if valid — calls `POST /families` (§3.1). A validation failure
     * never reaches the network, mirroring [com.findly.android.ui.groups.CreateGroupStateHolder.createGroup]'s
     * "gate before any network call" convention. */
    suspend fun createFamily(familyName: String, displayName: String) {
        val problem = validate(familyName, displayName)
        if (problem != null) {
            _state.value = _state.value.copy(validationError = problem)
            return
        }

        _state.value = _state.value.copy(isCreating = true, validationError = null, submitError = null)
        when (val result = familyApi.createFamily(familyName, displayName)) {
            is ApiResult.Success -> _state.value = _state.value.copy(isCreating = false, created = result.data.toUi())
            is ApiResult.Failure -> _state.value = _state.value.copy(isCreating = false, submitError = result.error.userMessage())
        }
    }
}

private fun CreateFamilyResponseDto.toUi(): CreatedFamilyUi = CreatedFamilyUi(
    familyId = familyId,
    familyName = familyName,
    role = member.role,
)
