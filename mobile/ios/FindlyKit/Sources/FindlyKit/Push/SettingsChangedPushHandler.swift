import Foundation

/// `SETTINGS_CHANGED` (specs/001-api-contract.md §8.3; specs/009-device-runtime.md §5.2/§3.5).
/// Always carries the complete current values of both fields — full state, never a delta — so this
/// is applied idempotently and reorder-safe by forwarding straight into `DeviceSettingsApplying`
/// (the single settings-application entry point, `DeviceSettingsCoordinator`'s own doc), exactly
/// like the wire contract requires. A malformed or partial payload (missing/non-numeric
/// `syncIntervalMinutes`, missing/non-boolean `trackingEnabled`) is dropped silently rather than
/// applied partially (009 §5 intro). Mirrors Android's `SettingsChangedPushHandler`.
public final class SettingsChangedPushHandler: SettingsChangedHandling {
    private let settingsApplying: DeviceSettingsApplying

    public init(settingsApplying: DeviceSettingsApplying) {
        self.settingsApplying = settingsApplying
    }

    public func handle(_ data: [String: String]) async {
        guard let syncIntervalMinutes = data["syncIntervalMinutes"].flatMap(Int.init) else { return }
        guard let trackingEnabled = data["trackingEnabled"].flatMap(Self.parseStrictBool) else { return }
        await settingsApplying.applySettings(DeviceSettingsSnapshot(syncIntervalMinutes: syncIntervalMinutes, trackingEnabled: trackingEnabled))
    }

    /// Only the exact strings "true"/"false" parse (matches Android's `toBooleanStrictOrNull()`) —
    /// anything else (empty, "1", "True", garbage) is treated as malformed, not coerced.
    private static func parseStrictBool(_ raw: String) -> Bool? {
        switch raw {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }
}
