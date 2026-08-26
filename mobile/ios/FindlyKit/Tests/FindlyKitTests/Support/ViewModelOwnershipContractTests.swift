import SwiftUI
import Testing
@testable import FindlyKit

/// I18 — regression coverage for the `@StateObject`/`@ObservedObject` property-wrapper ownership
/// contract that specs/010-app-shell-and-screen-ux.md §3.1 makes normative ("detent changes MUST
/// NOT ... re-create view models — the I16 `@StateObject` ownership rule") and specs/004 §2.4
/// assumes every screen honors. This is the class of bug found 2026-08-05 (docs/implementation-
/// handoff.md, I16): `RootView.body` constructs each screen's view model inline and re-evaluates
/// on every in-app navigation; a screen holding that view model as `@ObservedObject` observes a
/// brand-new, still-loading instance on every re-evaluation, while `@StateObject` (fed via an
/// `@autoclosure` init, exactly like `HomeScreen.init`) keeps the first instance for the view's
/// lifetime and never re-invokes the factory after the first installation.
///
/// These probes are deliberately generic/self-contained (not `HomeScreen`/any real screen) so this
/// file tests the *contract itself* — reusable by I34-I37's view-layer work — without coupling to
/// screens the 010 batch is actively changing/retiring in parallel.
@MainActor
struct ViewModelOwnershipContractTests {

    /// A minimal `ObservableObject` used only by these probes. `token` identifies WHICH instance a
    /// probe view is currently observing, so a test can tell first-instance-preserved from
    /// swapped-to-latest without inspecting any rendered pixels.
    final class ProbeModel: ObservableObject {
        let token: Int
        @Published var tick: Int = 0
        init(token: Int) { self.token = token }
    }

    /// Appends, in render order, the `token` of whichever `ProbeModel` a probe view's `body`
    /// observed. A `@StateObject`-owned probe should record the SAME token on every render no
    /// matter how many freshly-constructed models its parent hands it; an `@ObservedObject`-owned
    /// one records a NEW token every time — that difference IS the I16 bug, reproduced under test.
    final class ObservationLog {
        private(set) var observedTokens: [Int] = []
        func record(_ token: Int) { observedTokens.append(token) }
    }

    /// The probe view under test. `@StateObject` fed via `@autoclosure`, mirroring
    /// `HomeScreen.init`'s post-I16 shape verbatim: the factory is invoked by the caller on every
    /// re-render, but `_model = StateObject(wrappedValue: model())` only actually installs that
    /// value the FIRST time this view's identity appears; later calls' factory results are
    /// discarded, matching real `@StateObject` semantics.
    struct ScreenOwnershipProbe: View {
        @StateObject private var model: ProbeModel
        private let log: ObservationLog

        init(model: @autoclosure @escaping () -> ProbeModel, log: ObservationLog) {
            _model = StateObject(wrappedValue: model())
            self.log = log
        }

        var body: some View {
            log.record(model.token)
            return Color.clear
        }
    }

    /// The I16 shape: `@ObservedObject` assigned directly from whatever the parent passes at
    /// `init` time — there is no persistent storage tied to view identity, so every fresh instance
    /// the parent constructs becomes the observed one.
    struct BrokenOwnershipProbe: View {
        @ObservedObject var model: ProbeModel
        let log: ObservationLog

        var body: some View {
            log.record(model.token)
            return Color.clear
        }
    }

    /// Simulates "`RootView.body` re-evaluates on every in-app navigation, constructing a fresh
    /// view model inline each time" (I16's exact root cause) against the CORRECT `@StateObject`
    /// ownership: the harness re-hosts a brand new `ScreenOwnershipProbe` struct value, each with
    /// its own freshly-minted `ProbeModel` factory, several times in a row — exactly what
    /// `RootView` does on navigation. The regression this guards: only the FIRST factory's model
    /// should ever be observed.
    @Test func stateObjectOwnership_survivesSimulatedReRender() {
        let log = ObservationLog()
        var nextToken = 0
        func freshModel() -> ProbeModel {
            nextToken += 1
            return ProbeModel(token: nextToken)
        }

        let harness = SwiftUIRenderingHarness(ScreenOwnershipProbe(model: freshModel(), log: log))
        for _ in 0..<4 {
            harness.update(ScreenOwnershipProbe(model: freshModel(), log: log))
        }

        #expect(!log.observedTokens.isEmpty)
        #expect(log.observedTokens.allSatisfy { $0 == 1 })
    }

    /// The contrast case, kept permanently green: proves the harness is not vacuous by showing it
    /// correctly detects the OPPOSITE outcome for the I16-shaped `@ObservedObject` ownership — the
    /// same simulated re-render sequence, but every later token IS observed, because
    /// `@ObservedObject` has no storage of its own tied to view identity. A harness that reported
    /// "identity preserved" no matter which ownership pattern it hosted would be worthless; this
    /// test is the proof that it does not.
    @Test func observedObjectOwnership_doesNotSurviveSimulatedReRender() {
        let log = ObservationLog()
        var nextToken = 0
        func freshModel() -> ProbeModel {
            nextToken += 1
            return ProbeModel(token: nextToken)
        }

        let harness = SwiftUIRenderingHarness(BrokenOwnershipProbe(model: freshModel(), log: log))
        for _ in 0..<4 {
            harness.update(BrokenOwnershipProbe(model: freshModel(), log: log))
        }

        #expect(log.observedTokens.count > 1)
        #expect(log.observedTokens.last == 5)
        #expect(Set(log.observedTokens).count > 1)
    }
}
