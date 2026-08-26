import SwiftUI
import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §1.2/§3.1 (I34) — `LiveMapScreen` introduces a property-
/// wrapper shape `ViewModelOwnershipContractTests` (I18) doesn't cover on its own: a `@StateObject`
/// view model (its own, autoclosure-fed, exactly the I16 pattern) PLUS an `@ObservedObject`
/// `FamilyContextCache` — a long-lived instance `RootView` builds once and hands in unchanged
/// across every navigation, never reconstructed per-screen the way a per-screen view model is.
///
/// This is a worked example of that exact shape, not the real `LiveMapScreen` — which is MapKit-
/// dependent and (per I18's own note on production views) has no injectable `body` hook to record
/// through — proving BOTH halves hold at once in a single render sequence: (1) the `@StateObject`
/// child survives simulated re-render exactly like `ScreenOwnershipProbe` (I16); (2) the
/// `@ObservedObject` shared cache correctly reflects a live external mutation, which a
/// (mis-applied) `@StateObject` would NOT — it would freeze at whatever the first-installed
/// instance held, which is precisely why `LiveMapScreen` uses `@ObservedObject` for
/// `familyContext` rather than copying the view-model pattern onto it.
@MainActor
struct LiveMapScreenOwnershipTests {

    final class ProbeCache: ObservableObject {
        @Published var value: String
        init(_ value: String) { self.value = value }
    }

    final class ProbeViewModel: ObservableObject {
        let token: Int
        init(token: Int) { self.token = token }
    }

    struct ShellProbe: View {
        @StateObject private var viewModel: ProbeViewModel
        @ObservedObject var cache: ProbeCache
        private let log: ObservationLog<(token: Int, cacheValue: String)>

        init(
            viewModel: @autoclosure @escaping () -> ProbeViewModel,
            cache: ProbeCache,
            log: ObservationLog<(token: Int, cacheValue: String)>
        ) {
            _viewModel = StateObject(wrappedValue: viewModel())
            self.cache = cache
            self.log = log
        }

        var body: some View {
            log.record((token: viewModel.token, cacheValue: cache.value))
            return Color.clear
        }
    }

    @Test func stateObjectViewModel_survivesReRender_whileObservedObjectCache_reflectsLiveMutation() {
        let log = ObservationLog<(token: Int, cacheValue: String)>()
        var nextToken = 0
        func freshViewModel() -> ProbeViewModel {
            nextToken += 1
            return ProbeViewModel(token: nextToken)
        }
        let cache = ProbeCache("Wauters")

        // Simulates `RootView.body` re-evaluating on every in-app navigation: a brand new
        // `ShellProbe` struct value, with its own freshly-minted view-model factory, each time —
        // exactly what `RootView` does when it re-constructs `LiveMapScreen` on every navigation.
        let harness = SwiftUIRenderingHarness(ShellProbe(viewModel: freshViewModel(), cache: cache, log: log))
        for _ in 0..<3 {
            harness.update(ShellProbe(viewModel: freshViewModel(), cache: cache, log: log))
        }
        // Now mutate the SHARED cache externally (what `AppLaunchResolver`/`FamilyMembersViewModel`
        // do to the real `FamilyContextCache`) and render once more.
        cache.value = "Renamed Family"
        harness.update(ShellProbe(viewModel: freshViewModel(), cache: cache, log: log))

        // Independent proof a re-render actually happened (I18 review finding #1's convention).
        #expect(log.observed.count > 1)
        // The @StateObject view model: every render observed token 1 — the SAME instance the
        // FIRST factory produced, never one of the later ones `harness.update` supplied.
        #expect(log.observed.map(\.token).allSatisfy { $0 == 1 })
        // The @ObservedObject cache: the LAST render observed the mutated value — proving it is
        // the live, externally-owned instance, not a value frozen at first render.
        #expect(log.observed.last?.cacheValue == "Renamed Family")
    }
}
