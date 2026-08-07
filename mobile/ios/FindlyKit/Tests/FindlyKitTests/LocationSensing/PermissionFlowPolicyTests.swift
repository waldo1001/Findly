import Testing
@testable import FindlyKit

/// specs/009-device-runtime.md §7, specs/003-android-client.md §11 — the permission flow's decision
/// logic, kept pure so both the disclosure gate and the degraded-state banner are testable without
/// CoreLocation, a device, or a rendering harness.
///
/// This exists because §7's "a prominent disclosure precedes the OS prompt" was normative from the
/// start and never implemented on either platform — `SystemLocationProvider` even documents the gap
/// ("no onboarding screen exists yet to host that explanation"). It is a Play policy requirement for
/// background location, and the review additionally wants a video of the flow, so it cannot be
/// hand-waved at submission time.
@Suite struct PermissionFlowPolicyTests {

    // MARK: - The disclosure gate (009 §7: disclosure BEFORE the OS prompt)

    @Test func undisclosed_andUndetermined_showsDisclosureBeforeAnyOSPrompt() {
        let step = PermissionFlowPolicy.nextStep(
            authorization: .notDetermined,
            foregroundDisclosureAcknowledged: false,
            foregroundDisclosureDeclined: false,
            backgroundDisclosureAcknowledged: false,
            backgroundDisclosureDeclined: false,
            requiresBackground: false
        )

        #expect(step == .showDisclosure(.foreground))
    }

    @Test func afterForegroundDisclosure_requestsForegroundPermission() {
        let step = PermissionFlowPolicy.nextStep(
            authorization: .notDetermined,
            foregroundDisclosureAcknowledged: true,
            foregroundDisclosureDeclined: false,
            backgroundDisclosureAcknowledged: false,
            backgroundDisclosureDeclined: false,
            requiresBackground: false
        )

        #expect(step == .requestForeground)
    }

    @Test func backgroundUpgrade_isGatedBehindItsOwnDisclosure() {
        // 003 §11.2: background is a SEPARATE, later request, after a dedicated rationale —
        // Android 11+ forbids bundling it with the foreground prompt, and iOS mirrors the staging.
        let step = PermissionFlowPolicy.nextStep(
            authorization: .whenInUse,
            foregroundDisclosureAcknowledged: true,
            foregroundDisclosureDeclined: false,
            backgroundDisclosureAcknowledged: false,
            backgroundDisclosureDeclined: false,
            requiresBackground: true
        )

        #expect(step == .showDisclosure(.background))
    }

    @Test func afterBackgroundDisclosure_requestsTheUpgrade() {
        let step = PermissionFlowPolicy.nextStep(
            authorization: .whenInUse,
            foregroundDisclosureAcknowledged: true,
            foregroundDisclosureDeclined: false,
            backgroundDisclosureAcknowledged: true,
            backgroundDisclosureDeclined: false,
            requiresBackground: true
        )

        #expect(step == .requestBackgroundUpgrade)
    }

    @Test func whenInUseIsEnough_whenTheIntervalDoesNotNeedBackground() {
        let step = PermissionFlowPolicy.nextStep(
            authorization: .whenInUse,
            foregroundDisclosureAcknowledged: true,
            foregroundDisclosureDeclined: false,
            backgroundDisclosureAcknowledged: false,
            backgroundDisclosureDeclined: false,
            requiresBackground: false
        )

        #expect(step == .none)
    }

    @Test func alwaysAuthorized_asksForNothing() {
        let step = PermissionFlowPolicy.nextStep(
            authorization: .always,
            foregroundDisclosureAcknowledged: true,
            foregroundDisclosureDeclined: false,
            backgroundDisclosureAcknowledged: true,
            backgroundDisclosureDeclined: false,
            requiresBackground: true
        )

        #expect(step == .none)
    }

    @Test func denied_neverRePromptsAndNeverReShowsDisclosure() {
        // Once denied, the OS will not show the dialog again; re-asking is nagging that cannot
        // succeed. 003 §11.5 routes the user to system settings via the banner instead.
        let step = PermissionFlowPolicy.nextStep(
            authorization: .denied,
            foregroundDisclosureAcknowledged: false,
            foregroundDisclosureDeclined: false,
            backgroundDisclosureAcknowledged: false,
            backgroundDisclosureDeclined: false,
            requiresBackground: true
        )

        #expect(step == .none)
    }

    // MARK: - "Not now" is answered too (009 §7, I31/mirrors A25)

    @Test func declinedForeground_neverAutoReShowsTheDisclosure() {
        // The crux of I31: once "Not now" has been answered, nextStep() itself must gate it — not a
        // session-only filter one layer up, which is exactly what let the pre-I31 client re-present
        // the interstitial on every cold launch.
        let step = PermissionFlowPolicy.nextStep(
            authorization: .notDetermined,
            foregroundDisclosureAcknowledged: false,
            foregroundDisclosureDeclined: true,
            backgroundDisclosureAcknowledged: false,
            backgroundDisclosureDeclined: false,
            requiresBackground: false
        )

        #expect(step == .none)
    }

    @Test func declinedForeground_alsoDoesNotSilentlyPromoteIntoAnOSPrompt() {
        // A declined disclosure must not become `.requestForeground` either — that would invert
        // §7's "disclosure precedes the OS prompt" ordering just as badly as skipping the
        // disclosure would (the user said "not now", not "yes").
        let step = PermissionFlowPolicy.nextStep(
            authorization: .notDetermined,
            foregroundDisclosureAcknowledged: false,
            foregroundDisclosureDeclined: true,
            backgroundDisclosureAcknowledged: false,
            backgroundDisclosureDeclined: false,
            requiresBackground: false
        )

        #expect(step != .requestForeground)
    }

    @Test func declinedBackground_neverAutoReShowsTheDisclosure() {
        let step = PermissionFlowPolicy.nextStep(
            authorization: .whenInUse,
            foregroundDisclosureAcknowledged: true,
            foregroundDisclosureDeclined: false,
            backgroundDisclosureAcknowledged: false,
            backgroundDisclosureDeclined: true,
            requiresBackground: true
        )

        #expect(step == .none)
    }

    // MARK: - The degraded-state banner (009 §7: persistent, dismissible-per-session)

    @Test func deniedForeground_showsCannotReportBanner() {
        let banner = PermissionFlowPolicy.banner(
            authorization: .denied, requiresBackground: false,
            foregroundDisclosureDeclined: false, dismissedThisSession: false
        )

        #expect(banner == .cannotReport)
    }

    @Test func whenInUseButBackgroundNeeded_showsForegroundOnlyBanner() {
        // 003 §11.5: background denied falls back to foreground-only reporting, WITH a banner —
        // otherwise the app silently stops reporting the moment it is backgrounded.
        let banner = PermissionFlowPolicy.banner(
            authorization: .whenInUse, requiresBackground: true,
            foregroundDisclosureDeclined: false, dismissedThisSession: false
        )

        #expect(banner == .foregroundOnly)
    }

    @Test func whenInUseAndBackgroundNotNeeded_showsNoBanner() {
        let banner = PermissionFlowPolicy.banner(
            authorization: .whenInUse, requiresBackground: false,
            foregroundDisclosureDeclined: false, dismissedThisSession: false
        )

        #expect(banner == .none)
    }

    @Test func alwaysAuthorized_showsNoBanner() {
        let banner = PermissionFlowPolicy.banner(
            authorization: .always, requiresBackground: true,
            foregroundDisclosureDeclined: false, dismissedThisSession: false
        )

        #expect(banner == .none)
    }

    @Test func dismissingSuppressesTheBannerForThisSessionOnly() {
        // "dismissible-per-session" (009 §7): dismissal is deliberately NOT persisted — a user who
        // dismisses it once should still be told next launch that this device cannot report.
        let dismissed = PermissionFlowPolicy.banner(
            authorization: .denied, requiresBackground: false,
            foregroundDisclosureDeclined: false, dismissedThisSession: true
        )
        let freshSession = PermissionFlowPolicy.banner(
            authorization: .denied, requiresBackground: false,
            foregroundDisclosureDeclined: false, dismissedThisSession: false
        )

        #expect(dismissed == .none)
        #expect(freshSession == .cannotReport)
    }

    @Test func cannotReportOutranksForegroundOnly() {
        // Both conditions can be true at once; the more severe state is the one worth surfacing.
        let banner = PermissionFlowPolicy.banner(
            authorization: .denied, requiresBackground: true,
            foregroundDisclosureDeclined: false, dismissedThisSession: false
        )

        #expect(banner == .cannotReport)
    }

    @Test func declinedForeground_stillNotDetermined_showsCannotReportBanner() {
        // I31: once nextStep() stops auto-showing a declined foreground disclosure, a
        // `.notDetermined` authorization with no disclosure on screen would otherwise show
        // *nothing at all* — worse than the nagging this task fixes, since the device genuinely
        // cannot report and the banner is the only thing left saying so. Reuses `.cannotReport`
        // rather than a new state: from the user's point of view, "declined the explanation" and
        // "asked the OS and was refused" are the same degraded fact.
        let banner = PermissionFlowPolicy.banner(
            authorization: .notDetermined, requiresBackground: false,
            foregroundDisclosureDeclined: true, dismissedThisSession: false
        )

        #expect(banner == .cannotReport)
    }

    @Test func notDetermined_undeclined_showsNoBanner() {
        // The user has not refused anything yet — the disclosure/prompt flow should be running
        // instead, not the banner.
        let banner = PermissionFlowPolicy.banner(
            authorization: .notDetermined, requiresBackground: false,
            foregroundDisclosureDeclined: false, dismissedThisSession: false
        )

        #expect(banner == .none)
    }

    // MARK: - bannerReopenKind (009 §7, I31/mirrors A25 round-1 Major 1)
    //
    // The acknowledged/declined distinction is load-bearing here: `authorization` alone cannot tell
    // "the OS was never actually asked" (reopening the disclosure can still lead to a real prompt)
    // from "the OS was asked and refused" (only system settings can fix it). A25's round-1 Major 1
    // was exactly a dead-end banner button caused by conflating these.

    @Test func notDetermined_foregroundNeverAcknowledged_reopensTheForegroundDisclosure() {
        // OS never asked (the user only declined the in-app explanation) — reopening it can still
        // lead to a real prompt.
        let kind = PermissionFlowPolicy.bannerReopenKind(
            authorization: .notDetermined,
            foregroundDisclosureAcknowledged: false,
            backgroundDisclosureAcknowledged: false
        )

        #expect(kind == .foreground)
    }

    @Test func notDetermined_foregroundAcknowledged_routesToSettingsInstead() {
        // Accepted defensively even though `LocationAuthorizationResolver`-equivalent logic on iOS
        // maps "acknowledged but not granted" straight to `.denied` in practice — this function must
        // not silently depend on that as an invariant it trusts unchecked (mirrors Android's own
        // documented defensive stance on this exact case).
        let kind = PermissionFlowPolicy.bannerReopenKind(
            authorization: .notDetermined,
            foregroundDisclosureAcknowledged: true,
            backgroundDisclosureAcknowledged: false
        )

        #expect(kind == nil)
    }

    @Test func whenInUse_backgroundNeverAcknowledged_reopensTheBackgroundDisclosure() {
        let kind = PermissionFlowPolicy.bannerReopenKind(
            authorization: .whenInUse,
            foregroundDisclosureAcknowledged: true,
            backgroundDisclosureAcknowledged: false
        )

        #expect(kind == .background)
    }

    @Test func whenInUse_backgroundAcknowledged_meansTheOSAlreadyRefused_routesToSettingsInstead() {
        // On iOS this is the "When-In-Use granted but Always refused" state the task calls out
        // explicitly: acknowledging the background disclosure fires the real OS upgrade prompt, and
        // staying at `.whenInUse` afterward means the OS was asked and said no — reopening the
        // disclosure here would compute `.requestBackgroundUpgrade` again from `nextStep`, a step
        // nothing would actually re-fire a live prompt from, silently re-rendering with no forward
        // progress (the regression A25's round-1 Major 1 caught on Android).
        let kind = PermissionFlowPolicy.bannerReopenKind(
            authorization: .whenInUse,
            foregroundDisclosureAcknowledged: true,
            backgroundDisclosureAcknowledged: true
        )

        #expect(kind == nil)
    }

    @Test func denied_outrightRefused_routesToSettingsInstead() {
        let kind = PermissionFlowPolicy.bannerReopenKind(
            authorization: .denied,
            foregroundDisclosureAcknowledged: true,
            backgroundDisclosureAcknowledged: true
        )

        #expect(kind == nil)
    }

    @Test func always_needsNoReopenAtAll() {
        let kind = PermissionFlowPolicy.bannerReopenKind(
            authorization: .always,
            foregroundDisclosureAcknowledged: true,
            backgroundDisclosureAcknowledged: true
        )

        #expect(kind == nil)
    }
}
