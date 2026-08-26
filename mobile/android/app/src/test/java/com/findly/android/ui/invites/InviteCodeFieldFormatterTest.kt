package com.findly.android.ui.invites

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * [InviteCodeFieldFormatter] is the "smart code field" pure logic behind the accept-invite screen
 * (specs/010-app-shell-and-screen-ux.md §5.2 — "Smart code field (MUST): auto-uppercases; accepts
 * and strips hyphens/spaces; renders as `XXXX-XXXX` while typing; whitelist-filters to the
 * Crockford-base32 charset... shared pure formatter logic, unit-tested"). Deliberately separate
 * from [FamilyInviteCodeSanitizer]: that gate rejects a whole string that isn't already a
 * complete, valid code; this one progressively *reformats* a live-typing/pasted string, filtering
 * out anything not in [com.findly.android.joincode.JoinCodeAlphabet.ALPHABET] and re-inserting the
 * display hyphen — it never rejects a partial code outright.
 *
 * The API is split: [filterToCode] is the backing state (canonical, no hyphen, ≤ 8 chars) an
 * `onValueChange` callback should store; [toDisplayForm] is what the field's `value` should show.
 * A controlled `TextField` wires `value = toDisplayForm(filterToCode(code))` and
 * `onValueChange = { code = filterToCode(it) }`.
 */
class InviteCodeFieldFormatterTest {

    @Test
    fun `lowercase input is upper-cased`() {
        assertEquals("7F3K", InviteCodeFieldFormatter.filterToCode("7f3k"))
    }

    @Test
    fun `hyphens are stripped, not preserved in the backing code`() {
        assertEquals("7F3K9QRZ", InviteCodeFieldFormatter.filterToCode("7f3k-9qrz"))
    }

    @Test
    fun `spaces are stripped`() {
        assertEquals("7F3K9QRZ", InviteCodeFieldFormatter.filterToCode("7f3k 9qrz"))
    }

    @Test
    fun `excluded Crockford letters (I, L, O, U) are silently dropped, not kept as garbage`() {
        assertEquals("7F3K9QRZ", InviteCodeFieldFormatter.filterToCode("7F3KIL9OQRUZ"))
    }

    @Test
    fun `arbitrary punctuation and symbols are dropped`() {
        assertEquals("7F3K9QRZ", InviteCodeFieldFormatter.filterToCode("7F3K!9@QR#Z$"))
    }

    @Test
    fun `never submits more than the normalized 8 chars -- excess input is truncated`() {
        assertEquals("7F3K9QRZ", InviteCodeFieldFormatter.filterToCode("7F3K9QRZEXTRACHARS"))
    }

    @Test
    fun `a short partial code is never padded or rejected`() {
        assertEquals("7F3", InviteCodeFieldFormatter.filterToCode("7f3"))
    }

    @Test
    fun `empty input yields an empty code`() {
        assertEquals("", InviteCodeFieldFormatter.filterToCode(""))
    }

    @Test
    fun `display form groups the first 4 and last 4 characters with a hyphen`() {
        assertEquals("7F3K-9QRZ", InviteCodeFieldFormatter.toDisplayForm("7F3K9QRZ"))
    }

    @Test
    fun `display form of a partial (5-7 char) code still splits at 4`() {
        assertEquals("7F3K-9", InviteCodeFieldFormatter.toDisplayForm("7F3K9"))
        assertEquals("7F3K-9QR", InviteCodeFieldFormatter.toDisplayForm("7F3K9QR"))
    }

    @Test
    fun `display form of 4 or fewer characters has no hyphen yet`() {
        assertEquals("7F3K", InviteCodeFieldFormatter.toDisplayForm("7F3K"))
        assertEquals("7", InviteCodeFieldFormatter.toDisplayForm("7"))
        assertEquals("", InviteCodeFieldFormatter.toDisplayForm(""))
    }

    @Test
    fun `re-filtering an already-hyphenated display string is idempotent`() {
        val code = InviteCodeFieldFormatter.filterToCode("7F3K9QRZ")
        val redisplayed = InviteCodeFieldFormatter.toDisplayForm(code)
        assertEquals(code, InviteCodeFieldFormatter.filterToCode(redisplayed))
    }
}
