package com.findly.android.ui.groups

import com.findly.android.network.ApiResult
import com.findly.android.network.PlanLimits
import com.findly.android.network.dto.GroupDto
import com.findly.android.network.ports.GroupsApi
import com.findly.android.network.userMessage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.time.Instant

/**
 * The create-group screen's pure state machine (001-api-contract.md §12.1). No constructor
 * [kotlinx.coroutines.CoroutineScope] is needed — like
 * [com.findly.android.ui.invites.InvitesStateHolder] — since there is nothing to eagerly
 * load, only a user-initiated form submission.
 *
 * [limits] is the caller's own [PlanLimits] (threaded in from [GroupsListStateHolder]'s most
 * recent `GET /groups` response, avoiding a second round trip — specs/003-android-client.md
 * §12.2) so [validate] can bound `endsAt` by `maxGroupDurationDays` (001 §9/§12.1) **without ever
 * hardcoding that number** — only the fixed, plan-independent "+1h" floor (001 §12.1) is a
 * literal here, mirroring [com.findly.android.ui.geofences.GeofencesStateHolder.validate]'s
 * existing convention of a client-side mirror of server validation (server remains authoritative
 * regardless — `402 LIMIT_EXCEEDED`/`400 VALIDATION_FAILED` are still handled if this client-side
 * gate is ever stale, e.g. an expired [limits] snapshot).
 *
 * [clock] is a constructor-injected `() -> Long` (epoch millis) — same seam as
 * [com.findly.android.auth.DevAuthProvider]'s `clock` — so `now`-relative bounds are
 * deterministic under test.
 */
class CreateGroupStateHolder(
    private val groupsApi: GroupsApi,
    private val limits: PlanLimits?,
    private val needsDisplayName: Boolean,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val _state = MutableStateFlow(CreateGroupUiState())
    val state: StateFlow<CreateGroupUiState> = _state.asStateFlow()

    /** `now + 1h` (001 §12.1's fixed floor, every plan). */
    val minEndsAtMillis: Long get() = clock() + MIN_DURATION_MILLIS

    /** `now + limits.maxGroupDurationDays`, or `null` if [limits] is unavailable (defensive —
     * the server remains the authority either way). */
    val maxEndsAtMillis: Long?
        get() = limits?.maxGroupDurationDays?.let { clock() + it * DAY_MILLIS }

    /** Client-side mirror of 001 §12.1's validation. Returns a user-facing message, or `null` if
     * valid. */
    fun validate(name: String, endsAtMillis: Long?, expiryPolicy: String, displayName: String?): String? {
        val max = maxEndsAtMillis
        return when {
            name.isBlank() || name.length > 50 -> "Name must be 1-50 characters"
            endsAtMillis == null -> "Pick an end date and time"
            endsAtMillis < minEndsAtMillis -> "End time must be at least 1 hour from now"
            max != null && endsAtMillis > max -> "That end date is further out than your plan allows"
            expiryPolicy !in GroupPolicyCopy.ALL_POLICIES -> "Choose a group type"
            needsDisplayName && displayName.isNullOrBlank() -> "Enter a display name"
            else -> null
        }
    }

    /** Validates, then — only if valid — calls `POST /groups` (§12.1). A validation failure never
     * reaches the network, mirroring [com.findly.android.ui.settings.SettingsStateHolder]'s
     * "gate before any network call" convention. */
    suspend fun createGroup(name: String, endsAtMillis: Long?, expiryPolicy: String, displayName: String?) {
        val problem = validate(name, endsAtMillis, expiryPolicy, displayName)
        if (problem != null) {
            _state.value = _state.value.copy(validationError = problem)
            return
        }

        _state.value = _state.value.copy(isCreating = true, validationError = null, submitError = null)
        val endsAtIso = Instant.ofEpochMilli(endsAtMillis!!).toString()
        when (val result = groupsApi.createGroup(name, endsAtIso, expiryPolicy, displayName)) {
            is ApiResult.Success -> _state.value = _state.value.copy(isCreating = false, created = result.data.toUi())
            is ApiResult.Failure -> _state.value = _state.value.copy(isCreating = false, submitError = result.error.userMessage())
        }
    }

    companion object {
        private const val MIN_DURATION_MILLIS = 60L * 60 * 1000
        private const val DAY_MILLIS = 24L * 60 * 60 * 1000
    }
}

private fun GroupDto.toUi(): GroupSummaryUi = GroupSummaryUi(
    groupId = groupId,
    name = name,
    endsAt = endsAt,
    expiryPolicy = expiryPolicy,
    state = state,
    role = role,
    memberCount = memberCount,
    code = code,
)
