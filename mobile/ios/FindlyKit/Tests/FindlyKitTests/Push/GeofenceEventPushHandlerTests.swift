import Testing
@testable import FindlyKit

/// specs/001-api-contract.md §8.2 — normative title template (no time text). Returns `nil` on any
/// malformed/missing field (specs/009-device-runtime.md §5 intro) rather than throwing.
struct GeofenceEventNotificationTemplateTests {

    @Test func enter_buildsArrivedAtTitle() {
        let title = GeofenceEventNotificationTemplate.title(for: ["displayName": "Noor", "geofenceName": "Home", "transition": "enter"])
        #expect(title == "Noor arrived at Home")
    }

    @Test func exit_buildsLeftTitle() {
        let title = GeofenceEventNotificationTemplate.title(for: ["displayName": "Noor", "geofenceName": "Home", "transition": "exit"])
        #expect(title == "Noor left Home")
    }

    @Test func missingDisplayName_returnsNil() {
        #expect(GeofenceEventNotificationTemplate.title(for: ["geofenceName": "Home", "transition": "enter"]) == nil)
    }

    @Test func blankDisplayName_returnsNil() {
        #expect(GeofenceEventNotificationTemplate.title(for: ["displayName": "", "geofenceName": "Home", "transition": "enter"]) == nil)
    }

    @Test func missingGeofenceName_returnsNil() {
        #expect(GeofenceEventNotificationTemplate.title(for: ["displayName": "Noor", "transition": "enter"]) == nil)
    }

    @Test func unknownTransition_returnsNil() {
        #expect(GeofenceEventNotificationTemplate.title(for: ["displayName": "Noor", "geofenceName": "Home", "transition": "hover"]) == nil)
    }

    @Test func missingTransition_returnsNil() {
        #expect(GeofenceEventNotificationTemplate.title(for: ["displayName": "Noor", "geofenceName": "Home"]) == nil)
    }
}

/// specs/001-api-contract.md §8.2, specs/009-device-runtime.md §5.3 — a user-visible notification
/// about another family member; no location action taken. All the testable logic lives in
/// `GeofenceEventNotificationTemplate`; a malformed payload never reaches the notifier.
struct GeofenceEventPushHandlerTests {

    private final class FakeGeofenceEventNotifying: GeofenceEventNotifying {
        private(set) var notifiedTitles: [String] = []
        func notify(title: String) { notifiedTitles.append(title) }
    }

    @Test func validPayload_notifiesWithTheTemplateTitle() {
        let notifier = FakeGeofenceEventNotifying()
        let handler = GeofenceEventPushHandler(notifier: notifier)

        handler.handle(["type": "GEOFENCE_EVENT", "userId": "u2", "displayName": "Noor", "geofenceId": "gf_home", "geofenceName": "Home", "transition": "enter"])

        #expect(notifier.notifiedTitles == ["Noor arrived at Home"])
    }

    @Test func malformedPayload_neverNotifies() {
        let notifier = FakeGeofenceEventNotifying()
        let handler = GeofenceEventPushHandler(notifier: notifier)

        handler.handle(["displayName": "Noor"])

        #expect(notifier.notifiedTitles.isEmpty)
    }
}
