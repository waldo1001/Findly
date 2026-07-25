package com.findly.android.ui.groups

/** State surfaced by [CreateGroupStateHolder] (001-api-contract.md §12.1, specs/003-android-
 * client.md §12.2's `CreateGroupScreen`). */
data class CreateGroupUiState(
    val isCreating: Boolean = false,
    val validationError: String? = null,
    val submitError: String? = null,
    val created: GroupSummaryUi? = null,
)
