import Foundation

/// specs/001-api-contract.md §8 — the `data.type` discriminator of every FCM data message. Parsing
/// lives here, decoupled from any `UIApplicationDelegate`/Firebase-SDK glue, so
/// `PushMessageDispatcher` (specs/009-device-runtime.md §5) has a typed `switch` instead of
/// comparing raw strings — and so it's unit-testable without Firebase/APNs/a simulator. Mirrors
/// Android's `PushMessageType` exactly.
public enum PushMessageType: Equatable {
    case locateRequest
    case settingsChanged
    case geofenceEvent
    case geofenceConfigChanged
    case unrecognized(String)

    /// `data` is the raw FCM data payload (all string values, per 001 §8: "all `data` values are
    /// strings — clients parse"). A missing or unrecognized `type` yields `.unrecognized` rather
    /// than throwing — forward-compatible with future message types (001 §1.1), including the
    /// §8.7 reserved group types.
    public static func from(_ data: [String: String]) -> PushMessageType {
        switch data["type"] {
        case "LOCATE_REQUEST": return .locateRequest
        case "SETTINGS_CHANGED": return .settingsChanged
        case "GEOFENCE_EVENT": return .geofenceEvent
        case "GEOFENCE_CONFIG_CHANGED": return .geofenceConfigChanged
        default: return .unrecognized(data["type"] ?? "")
        }
    }
}
