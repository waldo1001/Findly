import Foundation
import Testing
@testable import FindlyKit

/// specs/011-device-lifecycle-and-staleness.md §3 + §6 (iOS explainer line) — I62.
struct ForceQuitExplainerTests {

    private func settings(interval: Int, tracking: Bool) -> DeviceSettingsSnapshot {
        DeviceSettingsSnapshot(syncIntervalMinutes: interval, trackingEnabled: tracking)
    }

    private func flaggedStore() -> InMemoryForceQuitExplainerStore {
        let store = InMemoryForceQuitExplainerStore()
        store.setTerminationFlag()
        return store
    }

    // MARK: copy (011 §3 verbatim)

    @Test func copy_isVerbatim() {
        #expect(ForceQuitExplainer.title == "Keep Findly open in the background")
        #expect(ForceQuitExplainer.body == "Swiping Findly away stops sharing your location until you open it again. To keep sharing, leave Findly in the app switcher — it uses very little battery.")
        #expect(ForceQuitExplainer.actionTitle == "Got it")
    }

    // MARK: show iff flag ∧ tracking ∧ interval ≤ 30 ∧ not yet shown

    @Test func shows_whenFlagTrackingAndIntervalQualify() {
        let store = flaggedStore()
        #expect(ForceQuitExplainerPresenter.evaluate(store: store, settings: settings(interval: 15, tracking: true)) == true)
    }

    @Test func shows_atIntervalBoundary30_notAbove() {
        let s30 = flaggedStore()
        #expect(ForceQuitExplainerPresenter.evaluate(store: s30, settings: settings(interval: 30, tracking: true)) == true)
        let s31 = flaggedStore()
        #expect(ForceQuitExplainerPresenter.evaluate(store: s31, settings: settings(interval: 31, tracking: true)) == false)
        let s60 = flaggedStore()
        #expect(ForceQuitExplainerPresenter.evaluate(store: s60, settings: settings(interval: 60, tracking: true)) == false)
    }

    @Test func doesNotShow_withoutFlag() {
        let store = InMemoryForceQuitExplainerStore()
        #expect(ForceQuitExplainerPresenter.evaluate(store: store, settings: settings(interval: 15, tracking: true)) == false)
        #expect(store.hasShownExplainer == false, "no flag, nothing consumed — the one-time slot stays open")
    }

    @Test func doesNotShow_whenTrackingPaused_andClearsFlagSilently() {
        let store = flaggedStore()
        #expect(ForceQuitExplainerPresenter.evaluate(store: store, settings: settings(interval: 15, tracking: false)) == false)
        #expect(store.isTerminationFlagSet == false)
        #expect(store.hasShownExplainer == false, "a silent clear must not burn the one-time explainer")
    }

    @Test func doesNotShow_whenIntervalTooLong_andClearsFlagSilently() {
        let store = flaggedStore()
        #expect(ForceQuitExplainerPresenter.evaluate(store: store, settings: settings(interval: 60, tracking: true)) == false)
        #expect(store.isTerminationFlagSet == false)
        #expect(store.hasShownExplainer == false)
    }

    @Test func shown_clearsFlagAndRecordsShown() {
        let store = flaggedStore()
        _ = ForceQuitExplainerPresenter.evaluate(store: store, settings: settings(interval: 15, tracking: true))
        #expect(store.isTerminationFlagSet == false)
        #expect(store.hasShownExplainer == true)
    }

    @Test func neverShownTwice_evenAfterLaterSwipes_andFlagIsStillCleared() {
        let store = flaggedStore()
        #expect(ForceQuitExplainerPresenter.evaluate(store: store, settings: settings(interval: 15, tracking: true)) == true)
        store.setTerminationFlag()
        #expect(ForceQuitExplainerPresenter.evaluate(store: store, settings: settings(interval: 15, tracking: true)) == false)
        #expect(store.isTerminationFlagSet == false, "flag cleared in every branch")
    }

    @Test func unknownCachedSettings_followRuntimeDefaults_trackingOnAndInterval15() {
        // `LocationRuntimeContainer` treats a missing cache as tracking on / 15 min (the presence
        // session runs under exactly that assumption), so the explainer agrees with it.
        let store = flaggedStore()
        #expect(ForceQuitExplainerPresenter.evaluate(store: store, settings: nil) == true)
    }

    // MARK: stores

    @Test func userDefaultsStore_roundTripsBothKeys_andClearRemovesBoth() {
        let suite = "ForceQuitExplainerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsForceQuitExplainerStore(defaults: defaults)

        #expect(store.isTerminationFlagSet == false)
        #expect(store.hasShownExplainer == false)
        store.setTerminationFlag()
        store.markExplainerShown()
        #expect(UserDefaultsForceQuitExplainerStore(defaults: defaults).isTerminationFlagSet == true)
        #expect(UserDefaultsForceQuitExplainerStore(defaults: defaults).hasShownExplainer == true)

        store.clear()
        #expect(store.isTerminationFlagSet == false)
        #expect(store.hasShownExplainer == false)
    }

    // MARK: end-of-session wipe

    @MainActor @Test func wipeLocalState_clearsBothKeys() async {
        let store = InMemoryForceQuitExplainerStore()
        store.setTerminationFlag()
        store.markExplainerShown()
        let container = LocationRuntimeContainer(
            apiClient: FakeAPIClient(), deviceId: { "device-1" },
            forceQuitExplainerStore: store
        )

        await container.wipeLocalState()

        #expect(store.isTerminationFlagSet == false)
        #expect(store.hasShownExplainer == false, "a different user on the phone sees the explainer once too")
    }
}
