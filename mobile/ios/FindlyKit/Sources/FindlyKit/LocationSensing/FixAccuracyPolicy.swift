import Foundation

/// specs/009-device-runtime.md §1.1 — accuracy tier requested for a single fix capture. `balanced`
/// is CoreLocation's ~100 m-class accuracy (never continuous GPS); `high` is best-available.
public enum LocationAccuracyTier: Equatable {
    case balanced
    case high
}

/// Pure `source` → (accuracy tier, timeout) mapping (specs/009-device-runtime.md §1.1's table) —
/// deliberately free of CoreLocation so it's reachable from both the real `SystemLocationProvider`
/// and any pure test. Mirrors Android's `FixCaptureCoordinator` companion object
/// (`accuracyFor`/`timeoutMillisFor`), split into its own file here since iOS's `FixCaptureCoordinator`
/// (I10) needs the same table from two call sites (capture-and-queue, and background-monitoring
/// hint suppression) without duplicating it.
public enum FixAccuracyPolicy {
    public static func tier(for source: FixSource) -> LocationAccuracyTier {
        switch source {
        case .manual, .locate: return .high
        case .periodic, .geofence: return .balanced
        }
    }

    /// Timeout in seconds. `geofence`'s shorter 15 s is the only reason this isn't folded into
    /// `LocationAccuracyTier` itself — `periodic` and `geofence` share `.balanced` but not the
    /// timeout.
    public static func timeout(for source: FixSource) -> TimeInterval {
        switch source {
        case .geofence: return 15
        case .periodic, .locate, .manual: return 30
        }
    }
}
