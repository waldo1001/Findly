package com.findly.android.ui.family

/** The result of a successful `POST /families` (001-api-contract.md §3.1). */
data class CreatedFamilyUi(val familyId: String, val familyName: String, val role: String)

/**
 * State surfaced by [CreateFamilyStateHolder] (specs/003-android-client.md §12; A21). Same shape
 * as [com.findly.android.ui.groups.CreateGroupUiState] — a single user-initiated form, no eager
 * load.
 */
data class CreateFamilyUiState(
    val isCreating: Boolean = false,
    val validationError: String? = null,
    val submitError: String? = null,
    val created: CreatedFamilyUi? = null,
)
