import SwiftUI
import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §3.1 (I35) — "Dragging between detents MUST NOT unmount
/// the list or re-create view models (the I16 `@StateObject` ownership rule)." This is the I18
/// rendering-harness worked example for THAT specific shape, generalizing
/// `LiveMapScreenOwnershipTests`' technique (which proves the `@StateObject`/`@ObservedObject`
/// split survives an *external cache mutation*) to a *detent change* instead.
///
/// `FindlyBottomSheet` itself has no view-model concerns — it only re-invokes whatever `content`
/// closure the caller supplies on every detent change (see that component's own doc). The actual
/// obligation lives in the caller (`LiveMapScreen`): its `.findlyBottomSheet` content closure
/// MUST capture the screen's own `@StateObject` view model, never construct a fresh one. This test
/// proves the general mechanism that guarantee rests on: a `@StateObject` living in a view whose
/// body is re-evaluated because a detent-selection value it reads changed still reports the SAME
/// instance on every one of those re-evaluations — exactly the property `LiveMapScreen` depends
/// on to keep its roster's view model alive across a sheet drag.
///
/// Not the real `LiveMapScreen` — which is MapKit-dependent and, per I18's own note on production
/// views, has no injectable `body` hook to record through (same documented boundary
/// `LiveMapScreenOwnershipTests` already accepted). `DetentHolder` stands in for the plain
/// `@State private var sheetDetent` a real screen would own; modeling it as an `@ObservedObject`
/// here (rather than `@State`, which cannot be mutated from outside the hosted view under test)
/// is what lets this test simulate "the user dragged to a different detent" from the test body,
/// the same substitution `LiveMapScreenOwnershipTests` makes for `FamilyContextCache`.
@MainActor
struct FindlyBottomSheetDetentOwnershipTests {

    final class DetentHolder: ObservableObject {
        @Published var detent: FindlyBottomSheetDetent
        init(_ detent: FindlyBottomSheetDetent) { self.detent = detent }
    }

    final class ProbeViewModel: ObservableObject {
        let token: Int
        init(token: Int) { self.token = token }
    }

    struct ShellProbe: View {
        @StateObject private var viewModel: ProbeViewModel
        @ObservedObject var detentHolder: DetentHolder
        private let log: ObservationLog<(token: Int, detent: FindlyBottomSheetDetent)>

        init(
            viewModel: @autoclosure @escaping () -> ProbeViewModel,
            detentHolder: DetentHolder,
            log: ObservationLog<(token: Int, detent: FindlyBottomSheetDetent)>
        ) {
            _viewModel = StateObject(wrappedValue: viewModel())
            self.detentHolder = detentHolder
            self.log = log
        }

        var body: some View {
            // Stands in for `LiveMapScreen`'s `.findlyBottomSheet(selection:) { detent in ... }`
            // content closure: it reads the current detent AND the outer `@StateObject`, exactly
            // the capture shape that must survive a detent change unbroken.
            log.record((token: viewModel.token, detent: detentHolder.detent))
            return Color.clear
        }
    }

    @Test func stateObjectViewModel_survivesDetentChanges_whileTheDetentValueItselfUpdatesLive() {
        let log = ObservationLog<(token: Int, detent: FindlyBottomSheetDetent)>()
        var nextToken = 0
        func freshViewModel() -> ProbeViewModel {
            nextToken += 1
            return ProbeViewModel(token: nextToken)
        }
        let detentHolder = DetentHolder(.standard)

        // Simulates `RootView.body` re-evaluating `LiveMapScreen` on every in-app navigation, PLUS
        // the sheet re-invoking its content closure on every detent change — both would, if this
        // screen used `@ObservedObject` instead of `@StateObject` (the I16 mistake), silently
        // swap in whatever a fresh factory call produces.
        let harness = SwiftUIRenderingHarness(ShellProbe(viewModel: freshViewModel(), detentHolder: detentHolder, log: log))
        for _ in 0..<3 {
            harness.update(ShellProbe(viewModel: freshViewModel(), detentHolder: detentHolder, log: log))
        }

        // Now drag to a different detent — the exact user action 010 §3.1 says MUST NOT unmount
        // anything — and render once more.
        detentHolder.detent = .minimized
        harness.update(ShellProbe(viewModel: freshViewModel(), detentHolder: detentHolder, log: log))
        detentHolder.detent = .expanded
        harness.update(ShellProbe(viewModel: freshViewModel(), detentHolder: detentHolder, log: log))

        // Independent proof re-renders actually happened (I18 review finding #1's convention).
        #expect(log.observed.count > 1)
        // The @StateObject view model: every render observed token 1 — the SAME instance the
        // FIRST factory produced, never one of the later ones `harness.update` supplied, and
        // never disturbed by either detent change.
        #expect(log.observed.map(\.token).allSatisfy { $0 == 1 })
        // The detent value itself: the roster content DOES see each live drag, in order — proving
        // the harness is actually observing the detent changes, not just ignoring them.
        #expect(log.observed.map(\.detent) == [.standard, .standard, .standard, .standard, .minimized, .expanded])
    }
}
