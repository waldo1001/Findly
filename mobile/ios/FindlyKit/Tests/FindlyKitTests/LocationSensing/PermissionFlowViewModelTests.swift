import Testing
@testable import FindlyKit

/// specs/009-device-runtime.md §7 — the wiring between `PermissionFlowPolicy` and the UI.
///
/// This type exists so the **ordering** requirement is testable at all. "A prominent disclosure
/// precedes the OS prompt" is a statement about what must NOT happen yet, and if the sequencing
/// lives in a SwiftUI view it is unverifiable in this project (no rendering harness — I18; and the
/// simulator's own permission alert is drawn by SpringBoard and ignores injected taps). Held here,
/// "no OS prompt while a disclosure is pending" is a plain assertion about a spy.
@MainActor
@Suite struct PermissionFlowViewModelTests {

    /// Records whether the OS-level prompts were asked for — the thing Play's review is actually
    /// checking the ordering of.
    final class PromptSpy {
        var foregroundRequests = 0
        var backgroundRequests = 0
    }

    private func makeViewModel(
        authorization: LocationAuthorization,
        requiresBackground: Bool = false,
        store: PermissionDisclosureStateStoring = InMemoryPermissionDisclosureStore()
    ) -> (PermissionFlowViewModel, PromptSpy, PermissionDisclosureStateStoring) {
        let spy = PromptSpy()
        var current = authorization
        let viewModel = PermissionFlowViewModel(
            authorization: { current },
            requiresBackground: { requiresBackground },
            disclosureStore: store,
            requestForeground: { spy.foregroundRequests += 1; current = .whenInUse },
            requestBackgroundUpgrade: { spy.backgroundRequests += 1; current = .always }
        )
        return (viewModel, spy, store)
    }

    // MARK: - The ordering guarantee (the whole point of 009 §7)

    @Test func refresh_withNothingAcknowledged_showsDisclosureAndPromptsNothing() {
        let (viewModel, spy, _) = makeViewModel(authorization: .notDetermined)

        viewModel.refresh()

        #expect(viewModel.disclosure == .foreground)
        #expect(spy.foregroundRequests == 0, "the OS prompt must not fire while the disclosure is pending")
        #expect(spy.backgroundRequests == 0)
    }

    @Test func acknowledging_dismissesDisclosureAndThenPrompts() {
        let (viewModel, spy, store) = makeViewModel(authorization: .notDetermined)
        viewModel.refresh()

        viewModel.acknowledgeDisclosure()

        #expect(viewModel.disclosure == nil)
        #expect(spy.foregroundRequests == 1)
        #expect(store.isAcknowledged(.foreground), "acknowledgement must persist so it is not re-shown next launch")
    }

    @Test func decliningLeavesTheOSPromptUnfired() {
        // "Not now" is a real choice (009 §7's disclosure is consent, not a formality): it must not
        // secretly fire the prompt anyway, and it must not record acknowledgement.
        let (viewModel, spy, store) = makeViewModel(authorization: .notDetermined)
        viewModel.refresh()

        viewModel.declineDisclosure()

        #expect(viewModel.disclosure == nil)
        #expect(spy.foregroundRequests == 0)
        #expect(store.isAcknowledged(.foreground) == false)
    }

    @Test func decliningDoesNotReopenTheDisclosureOnTheNextRefresh() {
        // Otherwise "Not now" becomes a loop the user cannot escape — refusing would re-present the
        // same screen every time the app foregrounds.
        let (viewModel, _, _) = makeViewModel(authorization: .notDetermined)
        viewModel.refresh()
        viewModel.declineDisclosure()

        viewModel.refresh()

        #expect(viewModel.disclosure == nil)
    }

    // MARK: - I31 (mirrors A25, 009 §7): decline is persisted, not session-only

    @Test func decliningPersistsToTheStore() {
        // The crux of I31: the old behaviour tracked "Not now" in an in-memory Set private to the
        // view model, which reset on every relaunch. It must now be written through to the durable
        // store, exactly like acknowledgement already is.
        let (viewModel, _, store) = makeViewModel(authorization: .notDetermined)
        viewModel.refresh()

        viewModel.declineDisclosure()

        #expect(store.isDeclined(.foreground), "\"Not now\" must persist so it survives a relaunch, not just the rest of this session")
    }

    @Test func aFreshViewModelInstanceAgainstTheSameStore_doesNotReShowADeclinedDisclosure() {
        // Simulates a cold relaunch: a brand-new `PermissionFlowViewModel` (nothing in-memory
        // carried over) backed by the SAME durable store that recorded a prior decline. This is
        // exactly the bug report (A25/I31): "the background disclosure re-appears on every single
        // launch after Not now" — verified here without needing an actual process restart.
        let store = InMemoryPermissionDisclosureStore()
        let (firstLaunch, _, _) = makeViewModel(authorization: .notDetermined, store: store)
        firstLaunch.refresh()
        firstLaunch.declineDisclosure()

        let (secondLaunch, spy, _) = makeViewModel(authorization: .notDetermined, store: store)
        secondLaunch.refresh()

        #expect(secondLaunch.disclosure == nil, "a declined disclosure must not auto-re-present on a fresh launch")
        #expect(spy.foregroundRequests == 0, "declining must never silently promote into the OS prompt either")
    }

    @Test func declineSurvivesMultipleForegroundRefreshesAcrossTheSameSession() {
        // Not just "not on the very next refresh" — 009 §7 says never auto-re-present once
        // answered, and refresh() is called on every foreground for the lifetime of the session.
        let (viewModel, _, _) = makeViewModel(authorization: .notDetermined)
        viewModel.refresh()
        viewModel.declineDisclosure()

        viewModel.refresh()
        viewModel.refresh()
        viewModel.refresh()

        #expect(viewModel.disclosure == nil)
    }

    // MARK: - bannerReopenKind + reopenDisclosure() (009 §7, I31/mirrors A25 round-1 Major 1)

    @Test func afterDeclining_theBannerReopenKindTargetsTheDeclinedKind() {
        // The OS was never actually asked — the banner's action should be able to bring the
        // disclosure back, not dead-end.
        let (viewModel, _, _) = makeViewModel(authorization: .notDetermined)
        viewModel.refresh()
        viewModel.declineDisclosure()

        viewModel.refresh()

        #expect(viewModel.bannerReopenKind == .foreground)
    }

    @Test func reopenDisclosure_forgetsTheDeclineAndReShowsIt() {
        let (viewModel, spy, store) = makeViewModel(authorization: .notDetermined)
        viewModel.refresh()
        viewModel.declineDisclosure()
        viewModel.refresh()
        #expect(viewModel.disclosure == nil)

        viewModel.reopenDisclosure()

        #expect(viewModel.disclosure == .foreground, "the explicit banner action must bring the disclosure back")
        #expect(store.isDeclined(.foreground) == false, "reopening forgets the decline it is reopening")
        #expect(store.isAcknowledged(.foreground) == false, "reopening must not fabricate an acknowledgement")
        #expect(spy.foregroundRequests == 0, "reopening shows the disclosure again — it does not skip straight to the OS prompt")
    }

    @Test func reopenDisclosure_whenNothingToReopen_isANoOp() {
        let (viewModel, _, _) = makeViewModel(authorization: .always, requiresBackground: true)
        viewModel.refresh()
        #expect(viewModel.bannerReopenKind == nil)

        viewModel.reopenDisclosure()

        #expect(viewModel.disclosure == nil)
    }

    @Test func osAlreadyRefusedTheBackgroundUpgrade_bannerReopenKindRoutesToSettingsNotReopen() {
        // A25's round-1 Major 1, mirrored: acknowledging the background disclosure fires the real
        // OS prompt; if the OS then refuses, authorization stays `.whenInUse` — the acknowledged
        // flag is what distinguishes this from "never asked", so the banner action must route to
        // system settings (bannerReopenKind == nil), not silently re-render the same disclosure.
        let store = InMemoryPermissionDisclosureStore()
        store.acknowledge(.foreground)
        store.acknowledge(.background)
        let (viewModel, _, _) = makeViewModel(
            authorization: .whenInUse, requiresBackground: true, store: store
        )

        viewModel.refresh()

        #expect(viewModel.bannerReopenKind == nil)
    }

    @Test func backgroundUpgrade_isAlsoGatedBehindItsOwnDisclosure() {
        let store = InMemoryPermissionDisclosureStore()
        store.acknowledge(.foreground)
        let (viewModel, spy, _) = makeViewModel(
            authorization: .whenInUse, requiresBackground: true, store: store
        )

        viewModel.refresh()

        #expect(viewModel.disclosure == .background)
        #expect(spy.backgroundRequests == 0, "the Always upgrade must not fire before its own explanation")
    }

    @Test func acknowledgingBackground_firesTheUpgrade() {
        let store = InMemoryPermissionDisclosureStore()
        store.acknowledge(.foreground)
        let (viewModel, spy, _) = makeViewModel(
            authorization: .whenInUse, requiresBackground: true, store: store
        )
        viewModel.refresh()

        viewModel.acknowledgeDisclosure()

        #expect(spy.backgroundRequests == 1)
        #expect(spy.foregroundRequests == 0, "the foreground prompt is spent; only the upgrade is asked for")
    }

    @Test func alreadyAuthorized_showsNothingAndAsksNothing() {
        let (viewModel, spy, _) = makeViewModel(authorization: .always, requiresBackground: true)

        viewModel.refresh()

        #expect(viewModel.disclosure == nil)
        #expect(viewModel.banner == .none)
        #expect(spy.foregroundRequests == 0)
        #expect(spy.backgroundRequests == 0)
    }

    // MARK: - Banner

    @Test func denied_surfacesTheBannerWithoutRePrompting() {
        let (viewModel, spy, _) = makeViewModel(authorization: .denied)

        viewModel.refresh()

        #expect(viewModel.banner == .cannotReport)
        #expect(viewModel.disclosure == nil)
        #expect(spy.foregroundRequests == 0, "re-prompting after denial cannot succeed and is nagging")
    }

    @Test func dismissingTheBanner_hidesItForThisSession() {
        let (viewModel, _, _) = makeViewModel(authorization: .denied)
        viewModel.refresh()

        viewModel.dismissBanner()

        #expect(viewModel.banner == .none)
    }

    @Test func aDismissedBannerStaysHiddenAcrossForegroundRefreshes() {
        // 009 §7 requires a re-check on every foreground; that re-check must not resurrect a banner
        // the user just dismissed, or dismissal is meaningless.
        let (viewModel, _, _) = makeViewModel(authorization: .denied)
        viewModel.refresh()
        viewModel.dismissBanner()

        viewModel.refresh()

        #expect(viewModel.banner == .none)
    }

    @Test func revokingPermissionWhileRunning_surfacesTheBannerOnTheNextForeground() {
        // The revocation path 009 §7 calls out: the user turns location off in system settings and
        // comes back. The foreground re-check is what notices.
        var current = LocationAuthorization.always
        let viewModel = PermissionFlowViewModel(
            authorization: { current },
            requiresBackground: { false },
            disclosureStore: InMemoryPermissionDisclosureStore(),
            requestForeground: {},
            requestBackgroundUpgrade: {}
        )
        viewModel.refresh()
        #expect(viewModel.banner == .none)

        current = .denied
        viewModel.refresh()

        #expect(viewModel.banner == .cannotReport)
    }
}
