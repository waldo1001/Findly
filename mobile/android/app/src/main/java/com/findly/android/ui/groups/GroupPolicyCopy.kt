package com.findly.android.ui.groups

/**
 * The plain-language privacy promise per `expiryPolicy`, verbatim from
 * specs/005-temporary-groups.md §2.1 ("clients MUST show this at creation, 003/004"). Rendered by
 * [CreateGroupScreen]'s 3-way policy selector — a pure, framework-free mapping so it's trivially
 * unit-testable and can't drift from the copy the reviewer signed off on.
 */
object GroupPolicyCopy {

    /** The three `expiryPolicy` values, in the order 005 §2.1's table presents them — the order a
     * picker should offer them in. */
    val ALL_POLICIES: List<String> = listOf("delete", "grace", "archive")

    /** Returns the 005 §2.1 copy for [policy], or `""` for anything outside [ALL_POLICIES] —
     * defensive; the create screen never lets the user select an unrecognized policy in the
     * first place. */
    fun forPolicy(policy: String): String = when (policy) {
        "delete" -> "When the group ends, everything about it disappears."
        "grace" -> "When the group ends it goes read-only for a few days so the owner can revive it; " +
            "then everything disappears."
        "archive" -> "When the group ends, everyone's locations are deleted; the member list stays as a keepsake."
        else -> ""
    }
}
