package com.findly.android.ui.groups

/** A roster entry (001-api-contract.md §12.3). */
data class GroupMemberUi(
    val userId: String,
    val displayName: String,
    val role: String,
    val joinedAt: String,
)

/**
 * State surfaced by [GroupDetailStateHolder] (specs/003-android-client.md §12.2's
 * `GroupDetailScreen`).
 */
sealed class GroupDetailUiState {
    data object Loading : GroupDetailUiState()
    data class Error(val message: String) : GroupDetailUiState()

    /** `GROUP_EXPIRED` on this screen (005 §2.3's lazy-enforcement matrix) — the screen SHOULD
     * bounce back to the groups list with a notice (specs/003 §12.2), not render an inline error,
     * since the group is simply gone from the caller's perspective now. */
    data class Expired(val message: String = "This group has ended.") : GroupDetailUiState()

    data class Content(
        val groupId: String,
        val name: String,
        val endsAt: String,
        val expiryPolicy: String,
        val state: String,
        val role: String,
        val memberCount: Int,
        val code: String?,
        val createdAt: String,
        /** `null` for a non-owner member during `grace` (`state == "ended"`) — roster hidden per
         * 005 §2.3; the owner and `archived` groups always get the full roster (001 §12.3). */
        val members: List<GroupMemberUi>?,
        val isMutating: Boolean = false,
        val mutationError: String? = null,
        val rotatedCode: String? = null,
        /** Set once the caller has left, been removed, or deleted the group — the screen SHOULD
         * navigate away when this flips true (specs/003 §12.2). */
        val left: Boolean = false,
    ) : GroupDetailUiState() {
        val isOwner: Boolean get() = role == "owner"
    }
}
