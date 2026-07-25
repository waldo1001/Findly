package com.findly.android.ui.groups

/**
 * Builds the canonical public join link (specs/007-public-join-links.md §1):
 * `https://{JOIN_LINK_HOST}/g#{CODE}`. A single pure function feeds both the A6 call sites that
 * need this exact string — [GroupDetailScreen]'s share-sheet text and the on-device QR payload
 * ([GroupQrCodeGenerator]) — so the two can never drift apart or accidentally diverge from §1's
 * format (in particular: the code MUST stay in the URL **fragment**, never a query parameter,
 * since fragments are never sent to a server/CDN/proxy — the load-bearing privacy property of the
 * whole design, 007 §1).
 *
 * [code] MUST already be a valid, sanitized join code (specs/003-android-client.md §12.2's
 * [GroupJoinCodeSanitizer]) — this function does not re-validate it, since its only callers pass a
 * group's own server-issued `code` (specs/001-api-contract.md §12.3's `GroupDetailDto`), never
 * untrusted external input.
 */
object GroupJoinLinkBuilder {
    fun buildHttpsLink(joinLinkHost: String, code: String): String = "https://$joinLinkHost/g#$code"
}
