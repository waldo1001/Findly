package com.findly.android.location

/**
 * The location-authorization states this app distinguishes, collapsed from Android's two separate
 * permission checks (`ACCESS_FINE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`) so [PermissionFlowPolicy]
 * stays pure Kotlin — no `android.*` import, unit-testable without an emulator.
 */
enum class LocationAuthorization {
    /** Never asked; the OS dialog is still available. */
    NOT_DETERMINED,

    /** `ACCESS_FINE_LOCATION` granted, `ACCESS_BACKGROUND_LOCATION` not. */
    WHEN_IN_USE,

    /** Both granted. */
    ALWAYS,

    /** Refused. Android stops showing the dialog, so the only route back is system settings. */
    DENIED,
}

/**
 * Which explanation to show. Distinct screens for distinct asks — 003 §11.2 requires the background
 * rationale to be separate and later, because Android 11+ forbids bundling the two prompts.
 */
enum class PermissionDisclosureKind { FOREGROUND, BACKGROUND }

/** The one next action in the permission flow. */
sealed interface PermissionFlowStep {
    /**
     * Show the in-app explanation. **Nothing may trigger an OS prompt while this is pending** —
     * that ordering is the whole of 009 §7's "prominent disclosure precedes the OS prompt", and
     * what Play's background-location review checks for.
     */
    data class ShowDisclosure(val kind: PermissionDisclosureKind) : PermissionFlowStep

    data object RequestForeground : PermissionFlowStep
    data object RequestBackgroundUpgrade : PermissionFlowStep

    /** Fully authorized, sufficiently authorized for the current interval, or denied. */
    data object None : PermissionFlowStep
}

/**
 * The degraded-state banner (009 §7). Denial is never fatal — the family map still works, this
 * device simply stops contributing — so the app must say so rather than appear to work.
 */
enum class PermissionBanner {
    NONE,

    /** Location refused outright: this device cannot report its position at all. */
    CANNOT_REPORT,

    /** Foreground granted, background refused, interval needs background: reports only while open. */
    FOREGROUND_ONLY,
}

/**
 * specs/009-device-runtime.md §7 + specs/003-android-client.md §11 — the permission flow's
 * decisions, as pure functions.
 *
 * Mirrors iOS's `PermissionFlowPolicy` case for case. §7 is cross-platform normative, so the two
 * clients disagreeing about when to show the disclosure is exactly the drift a shared spec exists
 * to prevent.
 *
 * **Why a policy object rather than logic in a composable:** §7's requirements are behavioural
 * ("disclosure precedes the OS prompt", "dismissible-per-session", "re-checked on every
 * foreground") and were normative from A2 onward, yet went unimplemented on both platforms for the
 * whole project — precisely because they lived only in prose and in a `MainActivity` TODO.
 */
object PermissionFlowPolicy {

    /**
     * The single next action, given current authorization and what the user has already been told.
     *
     * [requiresBackground] is whether this device's configured `syncIntervalMinutes` needs
     * background reporting at all (003 §11.3). A device that only reports while open never asks
     * for the background upgrade, and never nags about lacking it.
     *
     * **A25 (009 §7): "Not now" is answered too.** [foregroundDisclosureDeclined]/
     * [backgroundDisclosureDeclined] gate `ShowDisclosure` exactly like the acknowledged flags do —
     * once a kind has been declined, this returns [PermissionFlowStep.None] rather than re-showing
     * the disclosure *or* silently promoting the decline into an OS prompt (that would invert §7's
     * "disclosure precedes the OS prompt" ordering just as badly as skipping the disclosure would).
     */
    fun nextStep(
        authorization: LocationAuthorization,
        foregroundDisclosureAcknowledged: Boolean,
        foregroundDisclosureDeclined: Boolean,
        backgroundDisclosureAcknowledged: Boolean,
        backgroundDisclosureDeclined: Boolean,
        requiresBackground: Boolean,
    ): PermissionFlowStep = when (authorization) {
        // The OS dialog is spent. Re-prompting cannot succeed and re-explaining is nagging;
        // 003 §11.5 routes the user to system settings through the banner instead.
        LocationAuthorization.DENIED -> PermissionFlowStep.None

        LocationAuthorization.ALWAYS -> PermissionFlowStep.None

        LocationAuthorization.NOT_DETERMINED ->
            when {
                foregroundDisclosureAcknowledged -> PermissionFlowStep.RequestForeground
                foregroundDisclosureDeclined -> PermissionFlowStep.None
                else -> PermissionFlowStep.ShowDisclosure(PermissionDisclosureKind.FOREGROUND)
            }

        LocationAuthorization.WHEN_IN_USE ->
            when {
                !requiresBackground -> PermissionFlowStep.None
                backgroundDisclosureAcknowledged -> PermissionFlowStep.RequestBackgroundUpgrade
                backgroundDisclosureDeclined -> PermissionFlowStep.None
                else -> PermissionFlowStep.ShowDisclosure(PermissionDisclosureKind.BACKGROUND)
            }
    }

    /**
     * The degraded-state banner to show, if any.
     *
     * [dismissedThisSession] is deliberately **not** persisted. 009 §7 says
     * "dismissible-per-session": a user who waves it away once should still be told, next launch,
     * that this device is not reporting. Persisting dismissal would let a silently broken device
     * stay silently broken forever.
     *
     * **A25 (009 §7): [foregroundDisclosureDeclined] closes the gap the auto-re-present fix would
     * otherwise leave.** Once [nextStep] stops auto-showing a declined foreground disclosure, a
     * NOT_DETERMINED authorization with no disclosure on screen would otherwise show *nothing at
     * all* — worse than the old nagging, since the device genuinely cannot report and the banner is
     * the only thing left saying so. Reuses [PermissionBanner.CANNOT_REPORT] rather than adding a
     * new state: from the user's point of view, "declined the explanation" and "asked the OS and
     * was refused" are the same degraded fact — this device is not sharing its location.
     */
    fun banner(
        authorization: LocationAuthorization,
        requiresBackground: Boolean,
        foregroundDisclosureDeclined: Boolean,
        dismissedThisSession: Boolean,
    ): PermissionBanner {
        if (dismissedThisSession) return PermissionBanner.NONE

        return when (authorization) {
            // Checked before FOREGROUND_ONLY on purpose: both can apply at once, and "this device
            // cannot report at all" is the more severe truth.
            LocationAuthorization.DENIED -> PermissionBanner.CANNOT_REPORT
            LocationAuthorization.WHEN_IN_USE ->
                if (requiresBackground) PermissionBanner.FOREGROUND_ONLY else PermissionBanner.NONE
            LocationAuthorization.NOT_DETERMINED ->
                if (foregroundDisclosureDeclined) PermissionBanner.CANNOT_REPORT else PermissionBanner.NONE
            LocationAuthorization.ALWAYS -> PermissionBanner.NONE
        }
    }

    /**
     * Which disclosure kind an explicit action on the banner should reopen, or `null` when the OS
     * itself has already been asked for that kind and system settings is the only route back
     * (A25, 009 §7).
     *
     * **Code-review fix (A25 round 1, Major 1): `authorization` alone conflates two different
     * WHEN_IN_USE states.** The FOREGROUND_ONLY banner (WHEN_IN_USE + `requiresBackground`) shows
     * for two different reasons: the background disclosure was declined (OS never asked — reopening
     * it can still lead to a real prompt), OR the disclosure was acknowledged and
     * `backgroundLocationLauncher.launch()` already fired and was refused (the OS was already
     * asked). Reopening the disclosure in the second case would compute `RequestBackgroundUpgrade`
     * from [nextStep] — a step [com.findly.android.MainActivity] never consumes (the actual
     * `launch()` call only happens from the disclosure's `onContinue`), so the banner would
     * silently re-render with no forward progress — a regression from the pre-A25 behaviour, where
     * that state's action was unconditionally "Open settings" and worked. [backgroundDisclosureAcknowledged]
     * disambiguates: acknowledged means the OS was already asked, so route to settings instead.
     *
     * The equivalent NOT_DETERMINED + [foregroundDisclosureAcknowledged] case is not reachable in
     * practice today — [LocationAuthorizationResolver.resolve] maps "acknowledged but not granted"
     * straight to DENIED, never NOT_DETERMINED — but is accepted here too rather than trusted as an
     * invariant this function silently depends on.
     */
    fun bannerReopenKind(
        authorization: LocationAuthorization,
        foregroundDisclosureAcknowledged: Boolean,
        backgroundDisclosureAcknowledged: Boolean,
    ): PermissionDisclosureKind? = when (authorization) {
        LocationAuthorization.NOT_DETERMINED ->
            if (foregroundDisclosureAcknowledged) null else PermissionDisclosureKind.FOREGROUND
        LocationAuthorization.WHEN_IN_USE ->
            if (backgroundDisclosureAcknowledged) null else PermissionDisclosureKind.BACKGROUND
        LocationAuthorization.DENIED, LocationAuthorization.ALWAYS -> null
    }
}
