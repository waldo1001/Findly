package com.findly.android.ui.invites

import com.findly.android.joincode.JoinCodeAlphabet

/**
 * Pure family-invite-code normalizer/validator (001-api-contract.md §1.4, §3.3/§3.4) — the family
 * twin of [com.findly.android.ui.groups.GroupJoinCodeSanitizer] (specs/010-app-shell-and-screen-
 * ux.md §5: "a family twin of `GroupJoinCodeSanitizer`, sharing the pure logic rather than
 * copy-pasting it"). Applied to every incoming code before it is used — the manual entry field on
 * the accept-invite screen, the `findly://family-join?code=…` deep link's `code` query parameter,
 * and the `https://{JOIN_LINK_HOST}/f#{CODE}` fragment ([FamilyInviteHttpsLinkParser]) — all of
 * which are untrusted external input (specs/007-public-join-links.md §4). Delegates to
 * [JoinCodeAlphabet], the one shared spelling of the 001 §1.4 alphabet/strip/uppercase rule, so
 * this and [com.findly.android.ui.groups.GroupJoinCodeSanitizer] can never silently drift apart.
 */
object FamilyInviteCodeSanitizer {
    fun sanitize(input: String): String? = JoinCodeAlphabet.sanitize(input)
}
