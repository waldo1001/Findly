package com.findly.android.ui.invites

/**
 * Builds the canonical public family-invite link (specs/007-public-join-links.md §1 as amended
 * 2026-08-26): `https://{JOIN_LINK_HOST}/f#{CODE}` — the family twin of
 * [com.findly.android.ui.groups.GroupJoinLinkBuilder]. A single pure function feeds both call
 * sites that need this exact string — the create-invite screen's share-sheet text
 * ([FamilyInviteShareTextBuilder]) and the on-device QR payload
 * ([com.findly.android.ui.groups.GroupQrCodeGenerator]) — so the two can never drift apart or
 * accidentally diverge from §1's format. **The code MUST stay in the URL fragment, never a query
 * parameter** — fragments are never sent to a server/CDN/proxy, the load-bearing privacy property
 * of the whole design (007 §1), doubly so for family invites since they're single-use.
 *
 * [code] MUST already be a valid, sanitized invite code
 * ([FamilyInviteCodeSanitizer]) — this function does not re-validate it, since its only callers
 * pass a server-issued `inviteCode` (001-api-contract.md §3.3's create-invite response), never
 * untrusted external input.
 */
object FamilyInviteLinkBuilder {
    fun buildHttpsLink(joinLinkHost: String, code: String): String = "https://$joinLinkHost/f#$code"
}
