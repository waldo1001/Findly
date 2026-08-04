import Foundation

/// I15 — the `Findly Notification Service` app-extension target (`com.apple.usernotifications.
/// service`) calls this from its `didReceive(_:withContentHandler:)` to re-render the alert's
/// title from the push's own `data` fields, before the OS displays it (specs/001-api-contract.md
/// §8.2's `mutable-content: 1` exists specifically to enable this; specs/000-overview.md §O8).
///
/// Only `GEOFENCE_EVENT` pushes carry `mutable-content: 1` (001 §8) — the extension is never
/// invoked for the data-only types at all — but this still checks `data["type"]` defensively
/// rather than assuming, so a future message type that also sets `mutable-content: 1` doesn't
/// silently get today's geofence title glued onto it. Reuses `GeofenceEventNotificationTemplate`
/// (the same title logic `GeofenceEventPushHandler` uses for the in-app dispatch path) rather than
/// duplicating it — the whole reason that template lives in this package instead of the app
/// target is so both call sites share one implementation.
///
/// Returns `nil` for anything that isn't a well-formed `GEOFENCE_EVENT` payload — not a type, not
/// an error — so the caller's fallback is simply "leave `bestAttemptContent` as the untouched copy
/// of the server's original content" (specs/009-device-runtime.md §5 intro: a malformed payload is
/// dropped silently, never crashed on).
public enum GeofenceEventServiceExtensionRendering {
    public static func title(for data: [String: String]) -> String? {
        guard PushMessageType.from(data) == .geofenceEvent else { return nil }
        return GeofenceEventNotificationTemplate.title(for: data)
    }
}
