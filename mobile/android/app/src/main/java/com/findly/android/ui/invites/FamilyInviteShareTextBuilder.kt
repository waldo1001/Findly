package com.findly.android.ui.invites

import com.findly.android.joincode.JoinCodeAlphabet

/**
 * Builds the exact, normative family-invite share text of specs/007-public-join-links.md §4 (as
 * amended 2026-08-26) — **reproduced byte-for-byte, never paraphrased or "improved"**:
 * ```
 * Join our family on Findly — invite code {XXXX-XXXX}
 * https://{JOIN_LINK_HOST}/f#{CODE}
 * ```
 * `{XXXX-XXXX}` is the hyphenated display form; the fragment `{CODE}` is canonical (uppercase, no
 * hyphen) — both derived from the same server-issued [code] via [JoinCodeAlphabet]/
 * [FamilyInviteLinkBuilder] so they can never disagree with each other. Deliberately no store
 * URL (007 §4: "the message stays short and never goes stale when store URLs change" — those
 * live on the `/f` landing page instead).
 */
object FamilyInviteShareTextBuilder {
    fun build(joinLinkHost: String, code: String): String {
        val sanitized = requireNotNull(FamilyInviteCodeSanitizer.sanitize(code)) {
            "FamilyInviteShareTextBuilder expects an already-valid, server-issued code, got \"$code\""
        }
        val displayForm = JoinCodeAlphabet.toDisplayForm(sanitized)
        val link = FamilyInviteLinkBuilder.buildHttpsLink(joinLinkHost, sanitized)
        return "Join our family on Findly — invite code $displayForm\n$link"
    }
}
