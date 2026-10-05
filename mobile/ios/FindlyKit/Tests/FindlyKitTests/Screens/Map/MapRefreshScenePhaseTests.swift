import SwiftUI
import Testing
@testable import FindlyKit

/// specs/010 §3.6 (I59) — the one SwiftUI → pure-policy translation. `.inactive` and any phase added
/// in a future SDK must NOT be read as foregrounded: a map that polls in the background is the exact
/// defect §3.6 forbids.
struct MapRefreshScenePhaseTests {

    @Test func mapsEachSwiftUIScenePhase() {
        #expect(MapRefreshPolicy.ScenePhase(SwiftUI.ScenePhase.active) == .active)
        #expect(MapRefreshPolicy.ScenePhase(SwiftUI.ScenePhase.inactive) == .inactive)
        #expect(MapRefreshPolicy.ScenePhase(SwiftUI.ScenePhase.background) == .background)
    }
}
