import SwiftUI

/// specs/010 §3.6 (I59) — the one SwiftUI → pure-policy translation, so `MapRefreshPolicy` never
/// imports SwiftUI. Only `.active` counts as foregrounded: `.inactive` is the app covered (app
/// switcher, notification centre, a system dialog), and a phase a future SDK adds is treated the
/// same way — an unrecognised phase must never be read as licence to poll.
extension MapRefreshPolicy.ScenePhase {
    public init(_ phase: SwiftUI.ScenePhase) {
        switch phase {
        case .active: self = .active
        case .inactive: self = .inactive
        case .background: self = .background
        @unknown default: self = .inactive
        }
    }
}
