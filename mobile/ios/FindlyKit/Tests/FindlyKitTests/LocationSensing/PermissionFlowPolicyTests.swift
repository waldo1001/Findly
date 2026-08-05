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
            backgroundDisclosureAcknowledged: false,
            requiresBackground: false
        )

        #expect(step == .showDisclosure(.foreground))
    }

    @Test func afterForegroundDisclosure_requestsForegroundPermission() {
        let step = PermissionFlowPolicy.nextStep(
            authorization: .notDetermined,
            foregroundDisclosureAcknowledged: true,
            backgroundDisclosureAcknowledged: false,
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
            backgroundDisclosureAcknowledged: false,
            requiresBackground: true
        )

        #expect(step == .showDisclosure(.background))
    }

    @Test func afterBackgroundDisclosure_requestsTheUpgrade() {
        let step = PermissionFlowPolicy.nextStep(
            authorization: .whenInUse,
            foregroundDisclosureAcknowledged: true,
            backgroundDisclosureAcknowledged: true,
            requiresBackground: true
        )

        #expect(step == .requestBackgroundUpgrade)
    }

    @Test func whenInUseIsEnough_whenTheIntervalDoesNotNeedBackground() {
        let step = PermissionFlowPolicy.nextStep(
            authorization: .whenInUse,
            foregroundDisclosureAcknowledged: true,
            backgroundDisclosureAcknowledged: false,
            requiresBackground: false
        )

        #expect(step == .none)
    }

    @Test func alwaysAuthorized_asksForNothing() {
        let step = PermissionFlowPolicy.nextStep(
            authorization: .always,
            foregroundDisclosureAcknowledged: true,
            backgroundDisclosureAcknowledged: true,
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
            backgroundDisclosureAcknowledged: false,
            requiresBackground: true
        )

        #expect(step == .none)
    }

    // MARK: - The degraded-state banner (009 §7: persistent, dismissible-per-session)

    @Test func deniedForeground_showsCannotReportBanner() {
        let banner = PermissionFlowPolicy.banner(
            authorization: .denied, requiresBackground: false, dismissedThisSession: false
        )

        #expect(banner == .cannotReport)
    }

    @Test func whenInUseButBackgroundNeeded_showsForegroundOnlyBanner() {
        // 003 §11.5: background denied falls back to foreground-only reporting, WITH a banner —
        // otherwise the app silently stops reporting the moment it is backgrounded.
        let banner = PermissionFlowPolicy.banner(
            authorization: .whenInUse, requiresBackground: true, dismissedThisSession: false
        )

        #expect(banner == .foregroundOnly)
    }

    @Test func whenInUseAndBackgroundNotNeeded_showsNoBanner() {
        let banner = PermissionFlowPolicy.banner(
            authorization: .whenInUse, requiresBackground: false, dismissedThisSession: false
        )

        #expect(banner == .none)
    }

    @Test func alwaysAuthorized_showsNoBanner() {
        let banner = PermissionFlowPolicy.banner(
            authorization: .always, requiresBackground: true, dismissedThisSession: false
        )

        #expect(banner == .none)
    }

    @Test func dismissingSuppressesTheBannerForThisSessionOnly() {
        // "dismissible-per-session" (009 §7): dismissal is deliberately NOT persisted — a user who
        // dismisses it once should still be told next launch that this device cannot report.
        let dismissed = PermissionFlowPolicy.banner(
            authorization: .denied, requiresBackground: false, dismissedThisSession: true
        )
        let freshSession = PermissionFlowPolicy.banner(
            authorization: .denied, requiresBackground: false, dismissedThisSession: false
        )

        #expect(dismissed == .none)
        #expect(freshSession == .cannotReport)
    }

    @Test func cannotReportOutranksForegroundOnly() {
        // Both conditions can be true at once; the more severe state is the one worth surfacing.
        let banner = PermissionFlowPolicy.banner(
            authorization: .denied, requiresBackground: true, dismissedThisSession: false
        )

        #expect(banner == .cannotReport)
    }
}
