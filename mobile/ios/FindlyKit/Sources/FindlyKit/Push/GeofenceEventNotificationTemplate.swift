import Foundation

/// Builds the `GEOFENCE_EVENT` notification title (specs/001-api-contract.md §8.2 — normative
/// template, no time text: "the notification's own timestamp conveys the time in the recipient's
/// locale/zone"). Returns `nil` on any malformed/missing field (specs/009-device-runtime.md §5
/// intro: a malformed payload is dropped silently, never crashed on) rather than throwing. Mirrors
/// Android's `GeofenceEventNotificationTemplate` exactly, so both platforms show identical wording.
public enum GeofenceEventNotificationTemplate {
    public static func title(for data: [String: String]) -> String? {
        guard let displayName = data["displayName"], !displayName.isEmpty else { return nil }
        guard let geofenceName = data["geofenceName"], !geofenceName.isEmpty else { return nil }
        let verb: String
        switch data["transition"] {
        case "enter": verb = "arrived at"
        case "exit": verb = "left"
        default: return nil
        }
        return "\(displayName) \(verb) \(geofenceName)"
    }
}
