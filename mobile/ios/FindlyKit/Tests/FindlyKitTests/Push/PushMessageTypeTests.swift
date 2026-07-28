import Testing
@testable import FindlyKit

/// specs/001-api-contract.md §8 — the `data.type` discriminator every FCM data message carries.
/// Mirrors Android's `PushMessageType`: an unrecognized/missing value never throws (001 §1.1
/// forward compatibility), it just parses to `.unrecognized`.
struct PushMessageTypeTests {

    @Test func locateRequest_parses() {
        #expect(PushMessageType.from(["type": "LOCATE_REQUEST"]) == .locateRequest)
    }

    @Test func settingsChanged_parses() {
        #expect(PushMessageType.from(["type": "SETTINGS_CHANGED"]) == .settingsChanged)
    }

    @Test func geofenceEvent_parses() {
        #expect(PushMessageType.from(["type": "GEOFENCE_EVENT"]) == .geofenceEvent)
    }

    @Test func geofenceConfigChanged_parses() {
        #expect(PushMessageType.from(["type": "GEOFENCE_CONFIG_CHANGED"]) == .geofenceConfigChanged)
    }

    @Test func missingType_isUnrecognized_neverCrashes() {
        #expect(PushMessageType.from([:]) == .unrecognized(""))
    }

    @Test func unknownType_isUnrecognized() {
        #expect(PushMessageType.from(["type": "SOMETHING_NEW"]) == .unrecognized("SOMETHING_NEW"))
    }

    /// specs/001 §8.7 — reserved for future group notifications, not sent in v1; clients MUST
    /// ignore them exactly like any other unknown type (001 §1.1).
    @Test func reservedGroupTypes_areUnrecognized() {
        #expect(PushMessageType.from(["type": "GROUP_MEMBER_JOINED"]) == .unrecognized("GROUP_MEMBER_JOINED"))
        #expect(PushMessageType.from(["type": "GROUP_ENDING_SOON"]) == .unrecognized("GROUP_ENDING_SOON"))
    }
}
