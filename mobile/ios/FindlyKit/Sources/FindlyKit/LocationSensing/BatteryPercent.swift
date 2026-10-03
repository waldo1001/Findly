import Foundation

/// specs/004-ios-client.md §7 "Battery level — how `batteryPct` is read" (I57), specs/001 §1.4
/// (`batteryPct`: required integer 0-100 on every fix, with no "unknown" value).
///
/// Pure, `Foundation`-only mapping from `UIDevice.batteryLevel` (a `Float`, 0.0-1.0, `-1.0` when
/// unknown; granularity is OS-dependent — 1 % steps on iOS 16, 5 % on iOS 17+) to the wire's
/// integer percent, so it is unit-testable on any host (`swift test` runs under AppKit, specs/004
/// §2.3); its one real caller is the UIKit-backed reader (`BatteryLevelMonitor`).
public enum BatteryPercent {
    /// What the client sends when iOS cannot say. 001 gives `batteryPct` no "unknown" value, so the
    /// field cannot be omitted or sent as `-1`/`0`; `100` is the placeholder the backend has always
    /// received from iOS (and it never raises a false "low battery" signal).
    public static let unknown = 100

    /// - Parameter uiDeviceLevel: `UIDevice.current.batteryLevel`.
    /// - Returns: the level **rounded** (never truncated — a `Float` level can sit one ulp below its
    ///   whole percent: `Float(0.53) * 100` is 52.999996, which `Int(_:)` would turn into 52) to the
    ///   nearest percent and clamped to 0...100. A negative level
    ///   (`-1.0`, i.e. unknown: monitoring off, or the Simulator) or a non-finite one returns
    ///   ``unknown``.
    public static func from(uiDeviceLevel: Float) -> Int {
        // `.isNaN` first: NaN fails every comparison below, and `Int(Float.nan)` traps.
        if uiDeviceLevel.isNaN || uiDeviceLevel < 0 { return unknown }
        // `+infinity` (and anything else above 1.0) clamps; checking before the multiply also keeps
        // `Int(...)` from ever seeing a value outside 0...100.
        if uiDeviceLevel >= 1 { return 100 }
        return Int((uiDeviceLevel * 100).rounded())
    }
}
