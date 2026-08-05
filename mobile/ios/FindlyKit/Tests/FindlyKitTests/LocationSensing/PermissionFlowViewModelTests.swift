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
