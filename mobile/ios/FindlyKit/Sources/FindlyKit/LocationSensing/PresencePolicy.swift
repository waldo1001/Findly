import Foundation

/// specs/009-device-runtime.md §1.3 (amended 2026-09-06, 000 §D19) — "For `syncIntervalMinutes` ∈
/// {5, 10, 15, 30} a device MUST keep a low-power presence while tracking is enabled and
/// background-location permission is granted, so that (a) the cadence timer actually fires, and
/// (b) the process is alive to receive a `LOCATE_REQUEST` push... Intervals 60, 120 and 1440 keep
/// the original opportunistic path... with NO presence — this is the battery-first option and MUST
/// stay selectable."
///
/// Pure, CoreLocation-free decision logic — the single seam `LocationRuntimeContainer` (cold
/// start, every foreground, resume from pause, an authorization change, and every settings-arrival
/// path via `DeviceSettingsCoordinator`) calls to decide whether `LocationProviding.startPresence`
/// or `.stopPresence()` is the right action right now. "Background-location permission is granted"
/// means iOS **Always** specifically — the same gate `BackgroundLocationPolicy` already uses for
/// significant-location-change/visit monitoring and background one-shot delivery, since When-In-Use
/// cannot sustain a background session any more than it can wake a suspended app.
///
/// Mirrors Android's `PresenceRequirementPolicy`/`SyncStrategySelector` split in spirit, collapsed
/// into one function here: iOS has no "ideal vs. effective" distinction to layer on top (Android
/// falls back to WorkManager without background permission; iOS has no fallback presence
/// mechanism at all — it simply isn't required).
public enum PresencePolicy {
    /// The exact four "live" intervals of 009 §1.3's table — 001 §1.4's set restricted to the
    /// values ≤ 30.
    public static let presenceIntervalMinutes: Set<Int> = [5, 10, 15, 30]

    public static func isRequired(syncIntervalMinutes: Int, authorization: LocationAuthorization, trackingEnabled: Bool) -> Bool {
        trackingEnabled && authorization == .always && presenceIntervalMinutes.contains(syncIntervalMinutes)
    }
}
