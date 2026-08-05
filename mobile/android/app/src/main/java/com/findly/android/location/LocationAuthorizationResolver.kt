package com.findly.android.location

/**
 * specs/009-device-runtime.md §7 — collapses Android's two independent permission booleans onto the
 * four states [PermissionFlowPolicy] reasons about.
 *
 * **Why "never asked" vs "refused" needs solving at all:** only one of the two can still be
 * prompted. Re-prompting a refusal cannot succeed and reads as nagging; failing to prompt someone
 * who was never asked leaves the app permanently unable to report. 003 §11.5 sends the refused
 * case to system settings via the banner instead.
 *
 * **Why acknowledgement is the signal:** Android exposes no API for the distinction —
 * `checkSelfPermission` returns DENIED in both cases, and `shouldShowRequestPermissionRationale`
 * is false both before the first ask *and* after a permanent denial. Rather than add a second
 * persisted "have we asked yet" flag that could drift, this reuses the one piece of state that
 * already gates prompting: the app never prompts before the disclosure is acknowledged, so
 * "acknowledged but still not granted" can only mean the dialog was shown and refused.
 *
 * Pure Kotlin — no `android.*` — so it is unit-testable without an emulator.
 */
object LocationAuthorizationResolver {

    fun resolve(
        fineGranted: Boolean,
        backgroundGranted: Boolean,
        foregroundDisclosureAcknowledged: Boolean,
    ): LocationAuthorization = when {
        // Fine location is the prerequisite: background alone is not reachable through the UI, but
        // the OS can report it after a settings change. Treating that as ALWAYS would let the app
        // believe it can report in the background while the platform refuses every fix.
        fineGranted && backgroundGranted -> LocationAuthorization.ALWAYS
        fineGranted -> LocationAuthorization.WHEN_IN_USE
        // What is actually granted outranks acknowledgement state, so a user who granted from
        // system settings without ever seeing the disclosure is never reported as NOT_DETERMINED.
        foregroundDisclosureAcknowledged -> LocationAuthorization.DENIED
        else -> LocationAuthorization.NOT_DETERMINED
    }
}
