package com.findly.android.ui.groups

/** State surfaced by [GroupJoinStateHolder] (001-api-contract.md §12.6, specs/003-android-
 * client.md §12.2's `GroupJoinScreen` — also the `findly://group-join` deep-link target). */
data class GroupJoinUiState(
    val isJoining: Boolean = false,
    val validationError: String? = null,
    val joinError: String? = null,
    val joined: GroupSummaryUi? = null,
)
