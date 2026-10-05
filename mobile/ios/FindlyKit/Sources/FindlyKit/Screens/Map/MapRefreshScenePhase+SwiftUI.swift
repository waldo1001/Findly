import SwiftUI

/// specs/010 §3.6 (I59) — RED STUB: maps everything to `.active`, which is wrong for two of the three
/// cases.
extension MapRefreshPolicy.ScenePhase {
    public init(_ phase: SwiftUI.ScenePhase) {
        self = .active
    }
}
