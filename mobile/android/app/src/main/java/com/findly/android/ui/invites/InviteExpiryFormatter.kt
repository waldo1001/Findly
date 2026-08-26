package com.findly.android.ui.invites

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Renders the create-invite success view's "Expires {local date/time}" line (specs/010-app-
 * shell-and-screen-ux.md §5.1) from the server's `expiresAt` response field (001-api-contract.md
 * §3.3) — **never** a client-computed `now + 72h`. The task's own caution applies literally here:
 * the adjacent static caption ("It works once and expires in 72 hours.") quotes the server's
 * fixed policy (001 §3.3) as design copy, but the actual moment shown by this function is always
 * a pure conversion of the wire timestamp into [zoneId] (the phone's own local time zone by
 * default) — this function has no notion of "72" anywhere in it.
 *
 * A fixed, locale-invariant pattern (day, short month name, year, 24h time) is used rather than
 * [DateTimeFormatter.ofLocalizedDateTime] — the "local" in "local date/time" refers to the
 * device's local *time zone*, which this converts to; a locale-specific rendering style is an
 * orthogonal concern the spec doesn't ask for, and a fixed pattern keeps this deterministic under
 * test independent of the JVM's bundled locale data.
 */
object InviteExpiryFormatter {

    private val FORMATTER: DateTimeFormatter = DateTimeFormatter.ofPattern("d MMM yyyy, HH:mm", Locale.US)

    fun formatExpiresAt(expiresAtIso: String, zoneId: ZoneId = ZoneId.systemDefault()): String {
        val instant = Instant.parse(expiresAtIso)
        return FORMATTER.withZone(zoneId).format(instant)
    }
}
