import Foundation
#if os(iOS) && canImport(UIKit)
import UIKit

/// specs/004-ios-client.md §7 "Battery level — how `batteryPct` is read" (I57) — the one
/// `UIDevice`-backed source of `batteryPct` for every capture path. The app builds ONE of these in
/// `FindlyApp.init()` and passes `{ monitor.percent }` to both `SystemLocationProvider` and
/// `LocationRuntimeContainer` (→ `GeofenceTransitionHandler`). Thin UIKit glue (unit-untestable under
/// `swift test`, specs/004 §2.3 — the mapping it feeds, `BatteryPercent`, is the tested part);
/// verified by `xcodebuild`.
///
/// **Why a cache instead of reading `UIDevice` at the call site.** `UIDevice` is UIKit, i.e.
/// main-thread-only, but `percent` has a caller that is NOT on the main actor:
/// `GeofenceTransitionHandler.handle` is `async` and nonisolated, and `SystemGeofenceRegistrar` calls
/// it from a plain `Task`, so it runs on the global executor. (`SystemLocationProvider`'s callers are
/// `@MainActor`.) So the value is maintained on the main thread — seeded in `init`, refreshed on
/// `UIDevice.batteryLevelDidChangeNotification` — and any thread may read it through a lock.
///
/// **Staleness.** The notification only fires while the process runs, and the app is often woken
/// briefly from suspension (SLC, visit, BG refresh, geofence), so the cache can lag the real level by
/// the length of the suspension. Every read that happens on the main thread therefore reads
/// `UIDevice` directly and refreshes the cache (all of `SystemLocationProvider`'s paths, and the
/// wake-ups that begin on main); only the off-main geofence read can see a stale value, and it can be
/// as old as the last time the process was awake (the OS's reporting granularity bounds one reading's
/// precision, not how far the real level drifts between readings — a phone can lose 30 % in a few
/// hours). Possible follow-up, deliberately not done in I57: `GeofenceTransitionHandler.handle` is
/// already `async`, so it could read live with `await MainActor.run { … }` without changing the
/// `batteryLevelProvider` closure type.
public final class BatteryLevelMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedPercent = BatteryPercent.unknown
    private var observer: NSObjectProtocol?

    /// Enables `UIDevice.isBatteryMonitoringEnabled` (without it `batteryLevel` is always `-1.0`),
    /// seeds the cache and starts observing. Construct it before anything that can capture a fix
    /// (spec rule: monitoring on first, at launch).
    @MainActor
    public init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshFromDevice()
        observer = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue (`queue: .main`), so the main-actor assumption holds.
            MainActor.assumeIsolated { _ = self?.refreshFromDevice() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// The current battery percent (0...100, `BatteryPercent.unknown` when iOS can't say). Safe from
    /// any thread; see the type doc for what "current" means off the main thread.
    public var percent: Int {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { refreshFromDevice() }
        }
        lock.lock()
        defer { lock.unlock() }
        return cachedPercent
    }

    @discardableResult
    @MainActor
    private func refreshFromDevice() -> Int {
        let fresh = BatteryPercent.from(uiDeviceLevel: UIDevice.current.batteryLevel)
        lock.lock()
        cachedPercent = fresh
        lock.unlock()
        return fresh
    }
}
#endif
