package com.findly.android.ui.invites

import com.findly.android.joincode.JoinCodeAlphabet

/**
 * The accept-invite screen's "smart code field" pure logic (specs/010-app-shell-and-screen-ux.md
 * §5.2: "auto-uppercases; accepts and strips hyphens/spaces; renders as `XXXX-XXXX` while typing;
 * whitelist-filters to the Crockford-base32 charset... shared pure formatter logic, unit-tested").
 * Deliberately separate from [FamilyInviteCodeSanitizer]: that gate rejects a whole string that
 * isn't already a complete, valid 8-char code (used once, at submit time); this one progressively
 * *reformats* live-typing/pasted input, filtering out anything not in
 * [JoinCodeAlphabet.ALPHABET] and re-inserting the display hyphen — a partial code is never
 * rejected, only reformatted.
 *
 * A controlled `TextField` wires `value = toDisplayForm(code)` and
 * `onValueChange = { code = filterToCode(it) }`, where `code` is the backing state (canonical, no
 * hyphen, ≤ 8 chars) — so typing, backspacing, or pasting a hyphenated/lowercase/garbage-laced
 * string all converge on the same normalized value.
 */
object InviteCodeFieldFormatter {

    private const val CODE_LENGTH = 8
    private const val GROUP_SIZE = 4

    /** Upper-cases, drops every non-alphabet character (including hyphens/spaces), and caps at
     * [CODE_LENGTH] — never submits more than the normalized 8 chars. */
    fun filterToCode(raw: String): String = JoinCodeAlphabet.filterToAlphabet(raw).take(CODE_LENGTH)

    /** `XXXX-XXXX` grouping once more than [GROUP_SIZE] characters exist; shorter/empty [code]
     * renders as-is, with no hyphen inserted prematurely. */
    fun toDisplayForm(code: String): String =
        if (code.length > GROUP_SIZE) "${code.substring(0, GROUP_SIZE)}-${code.substring(GROUP_SIZE)}" else code
}
