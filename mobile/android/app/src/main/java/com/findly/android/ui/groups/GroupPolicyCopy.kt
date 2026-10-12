package com.findly.android.ui.groups

/**
 * The plain-language privacy promise per `expiryPolicy`, verbatim from
 * specs/005-temporary-groups.md §2.1 ("clients MUST show this at creation, 003/004"). Rendered by
 * [CreateGroupScreen]'s 3-way policy selector — a pure, framework-free mapping so it's trivially
 * unit-testable and can't drift from the copy the reviewer signed off on.
 */
object GroupPolicyCopy {

    /** 005 §2.5 item 2 — the bold lead of the no-end-date warning. */
    const val NO_END_DATE_WARNING_LEAD = "This group has no end date."

    /** 005 §2.5 item 2 — the rest of the no-end-date warning. */
    const val NO_END_DATE_WARNING_BODY =
        "Everyone in it keeps seeing each other's live location until you end or delete the group, or they leave it."

    /** 005 §2.5 item 2, verbatim — shown under the "No end date" choice and in the "Remove end
     * date" confirmation dialog. */
    const val NO_END_DATE_WARNING = "$NO_END_DATE_WARNING_LEAD $NO_END_DATE_WARNING_BODY"

    /** 005 §2.5 item 3 — one-line note under the policy promise. */
    const val NO_END_DATE_POLICY_NOTE = "Applies only if you set an end date later."

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
