package com.findly.android.location

import android.content.Context
import android.content.SharedPreferences

/**
 * Whether the user has already been shown each explanation (specs/009-device-runtime.md §7).
 *
 * **Persisted, unlike the banner's dismissal.** The two look alike and are deliberately opposite:
 * acknowledgement survives relaunch, while banner dismissal is session-only so a device that cannot
 * report is re-surfaced next launch rather than staying silently broken.
 *
 * **Decline is persisted too (A25).** "Not now" used to live only in in-memory Compose state, so a
 * fresh process (any cold launch) always saw an empty decline set and re-showed the full-screen
 * disclosure — exactly the nagging pattern store review discourages. 009 §7 now says a disclosure
 * MUST NOT auto-re-present once *answered*, and declining counts as answered exactly like
 * acknowledging does. [isDeclined]/[decline] are tracked as a separate flag from
 * [isAcknowledged]/[acknowledge] (never conflated) so [clearDeclined] can forget only the decline
 * when the banner's explicit "reopen the disclosure" action fires, without also fabricating an
 * acknowledgement that was never given.
 *
 * The two kinds are tracked separately because 003 §11.2 makes the background ask a **separate,
 * later** request with its own rationale — one shared flag would silently skip the background
 * disclosure, which is the screen Play's background-location review is looking for.
 *
 * Pure Kotlin interface (no `android.*`) so the flow is unit-testable without an emulator;
 * [SharedPreferencesPermissionDisclosureStore] is the real implementation.
 */
interface PermissionDisclosureStore {
    fun isAcknowledged(kind: PermissionDisclosureKind): Boolean
    fun acknowledge(kind: PermissionDisclosureKind)

    /** Whether the user has already answered "Not now" to this kind's disclosure (A25, 009 §7). */
    fun isDeclined(kind: PermissionDisclosureKind): Boolean
    fun decline(kind: PermissionDisclosureKind)

    /**
     * Forgets a prior decline for this kind only — used when an explicit user action on the
     * degraded-state banner re-opens the full-screen disclosure (A25, 009 §7), so the flow gate
     * presents it again instead of staying suppressed.
     */
    fun clearDeclined(kind: PermissionDisclosureKind)

    /**
     * Drops both acknowledgements and both declines — part of the account-deletion local wipe
     * (specs/008 §4.4). A different user on the same device must see the explanation again: this
     * is consent, not a device-level preference.
     */
    fun clear()
}

/** Test/default in-memory implementation. */
class InMemoryPermissionDisclosureStore : PermissionDisclosureStore {
    private val acknowledged = mutableSetOf<PermissionDisclosureKind>()
    private val declined = mutableSetOf<PermissionDisclosureKind>()

    override fun isAcknowledged(kind: PermissionDisclosureKind) = kind in acknowledged
    override fun acknowledge(kind: PermissionDisclosureKind) { acknowledged += kind }
    override fun isDeclined(kind: PermissionDisclosureKind) = kind in declined
    override fun decline(kind: PermissionDisclosureKind) { declined += kind }
    override fun clearDeclined(kind: PermissionDisclosureKind) { declined -= kind }
    override fun clear() {
        acknowledged.clear()
        declined.clear()
    }
}

/**
 * The real, `SharedPreferences`-backed implementation.
 *
 * Plain preferences rather than encrypted storage on purpose: this is a boolean about what a user
 * has read, carrying no location data and no identifier. The worst a tampered value achieves is
 * showing or skipping an explanation screen.
 */
class SharedPreferencesPermissionDisclosureStore(
    private val prefs: SharedPreferences,
) : PermissionDisclosureStore {

    constructor(context: Context) : this(
        context.getSharedPreferences("findly.permission_disclosure", Context.MODE_PRIVATE),
    )

    private fun key(kind: PermissionDisclosureKind) = when (kind) {
        PermissionDisclosureKind.FOREGROUND -> "disclosure.foreground"
        PermissionDisclosureKind.BACKGROUND -> "disclosure.background"
    }

    private fun declinedKey(kind: PermissionDisclosureKind) = when (kind) {
        PermissionDisclosureKind.FOREGROUND -> "disclosure.foreground.declined"
        PermissionDisclosureKind.BACKGROUND -> "disclosure.background.declined"
    }

    override fun isAcknowledged(kind: PermissionDisclosureKind) = prefs.getBoolean(key(kind), false)

    override fun acknowledge(kind: PermissionDisclosureKind) {
        prefs.edit().putBoolean(key(kind), true).apply()
    }

    override fun isDeclined(kind: PermissionDisclosureKind) = prefs.getBoolean(declinedKey(kind), false)

    override fun decline(kind: PermissionDisclosureKind) {
        prefs.edit().putBoolean(declinedKey(kind), true).apply()
    }

    override fun clearDeclined(kind: PermissionDisclosureKind) {
        prefs.edit().remove(declinedKey(kind)).apply()
    }

    override fun clear() {
        prefs.edit()
            .remove(key(PermissionDisclosureKind.FOREGROUND))
            .remove(key(PermissionDisclosureKind.BACKGROUND))
            .remove(declinedKey(PermissionDisclosureKind.FOREGROUND))
            .remove(declinedKey(PermissionDisclosureKind.BACKGROUND))
            .apply()
    }
}
