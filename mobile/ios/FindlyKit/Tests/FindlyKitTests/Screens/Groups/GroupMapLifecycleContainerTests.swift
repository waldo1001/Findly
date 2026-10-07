import SwiftUI
import Testing
@testable import FindlyKit

/// specs/010 §3.6 (I59 review F6) — `GroupMapScreen` swaps its body between the map and the
/// "This group has ended" card on `.expired`, while the §3.6 lifecycle modifiers (`.task` → first
/// appearance, `.onDisappear` → stop the timer) must keep describing the SCREEN, not whichever branch
/// is showing. The screen therefore hangs them on a `ZStack` — a real container whose own identity
/// survives the swap — rather than on a `Group`, whose modifiers SwiftUI distributes to its children
/// and whose behaviour on a conditional swap has varied between SwiftUI releases.
///
/// This probe pins the `ZStack` half of that: counting lifecycle callbacks across a branch swap,
/// hosted in the real hosting controller (`SwiftUIRenderingHarness`, I18), the swap does not read as
/// an appearance change. It deliberately does NOT assert what a `Group` does — measured here (the
/// macOS/AppKit host `swift test` runs on) a `Group` around a single `if`/`else` happened not to fire
/// either, so the hazard the review named could not be demonstrated on this host; the `ZStack` simply
/// removes the screen's dependence on it. Scope, stated plainly: this tests the container semantics,
/// not `GroupMapScreen.body` itself (which needs a renderer and a live scene) — the structural choice
/// in the screen is verified by review and `xcodebuild`.
@MainActor
struct GroupMapLifecycleContainerTests {

    final class Branch: ObservableObject {
        @Published var showsEndedCard = false
    }

    final class Counter {
        var appeared = 0
        var disappeared = 0
        /// The ended card's OWN appearance — proof the branch swap really rendered, so a quiet
        /// `appeared`/`disappeared` means "no lifecycle change", not "nothing happened".
        var endedCardAppeared = 0
    }

    struct ZStackContainerProbe: View {
        @ObservedObject var branch: Branch
        let counter: Counter
        var body: some View {
            ZStack {
                if branch.showsEndedCard {
                    Text("ended").onAppear { counter.endedCardAppeared += 1 }
                } else {
                    Text("map")
                }
            }
            .onAppear { counter.appeared += 1 }
            .onDisappear { counter.disappeared += 1 }
        }
    }

    @Test func zStackContainer_aBranchSwapIsNotAnAppearanceChange() {
        let branch = Branch()
        let counter = Counter()
        let harness = SwiftUIRenderingHarness(ZStackContainerProbe(branch: branch, counter: counter))
        #expect(counter.appeared == 1, "precondition: onAppear fires in this harness")

        branch.showsEndedCard = true
        harness.update(ZStackContainerProbe(branch: branch, counter: counter))

        #expect(counter.endedCardAppeared == 1, "the swap really rendered")
        #expect(counter.appeared == 1, "the screen did not 'appear' again")
        #expect(counter.disappeared == 0, "the screen did not 'disappear'")
    }
}
