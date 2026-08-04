import Testing
@testable import FindlyKit

/// I15 (specs/001-api-contract.md §8.2, specs/000-overview.md §O8) — the pure re-rendering logic a
/// `UNNotificationServiceExtension` calls from `didReceive(_:withContentHandler:)` to replace the
/// server-embedded `aps.alert.title` with one built from the push's own `data` fields, before the
/// OS displays it. Only `GEOFENCE_EVENT` pushes carry `mutable-content: 1`, so this only ever
/// touches that one message type; every other/malformed payload yields `nil` so the extension
/// leaves the original server content untouched (the fallback the extension itself is responsible
/// for wiring, per its own doc). Reuses `GeofenceEventNotificationTemplate` — no duplicated title
/// logic between the app and the extension.
struct GeofenceEventServiceExtensionRenderingTests {

    @Test func geofenceEventEnter_rendersTheTemplateTitle() {
        let data = ["type": "GEOFENCE_EVENT", "userId": "u2", "displayName": "Noor",
                     "geofenceId": "gf_home", "geofenceName": "Home", "transition": "enter"]
        #expect(GeofenceEventServiceExtensionRendering.title(for: data) == "Noor arrived at Home")
    }

    @Test func geofenceEventExit_rendersTheTemplateTitle() {
        let data = ["type": "GEOFENCE_EVENT", "userId": "u2", "displayName": "Noor",
                     "geofenceId": "gf_home", "geofenceName": "Home", "transition": "exit"]
        #expect(GeofenceEventServiceExtensionRendering.title(for: data) == "Noor left Home")
    }

    @Test func nonGeofenceEventType_returnsNil_leavesOriginalContentUntouched() {
        let data = ["type": "SETTINGS_CHANGED", "syncIntervalMinutes": "30", "trackingEnabled": "false"]
        #expect(GeofenceEventServiceExtensionRendering.title(for: data) == nil)
    }

    @Test func missingType_returnsNil() {
        let data = ["displayName": "Noor", "geofenceName": "Home", "transition": "enter"]
        #expect(GeofenceEventServiceExtensionRendering.title(for: data) == nil)
    }

    @Test func geofenceEventWithMalformedFields_returnsNil() {
        let data = ["type": "GEOFENCE_EVENT", "displayName": "Noor"]
        #expect(GeofenceEventServiceExtensionRendering.title(for: data) == nil)
    }
}
