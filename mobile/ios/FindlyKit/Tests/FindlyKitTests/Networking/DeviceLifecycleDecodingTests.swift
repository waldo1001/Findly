import Foundation
import Testing
@testable import FindlyKit

/// specs/011-device-lifecycle-and-staleness.md §2, §4.4; 001 §4.1/§4.2/§5.2 — the lifecycle wire
/// fields and their defensive defaults (003 §6 precedent: an absent `isDormant` is `false`, an
/// absent `staleNudgeEnabled` is `true`, an absent `lastSeenAt` is `nil` and hides the line).
struct DeviceLifecycleDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private let listBase = """
    "deviceId":"d1","ownerUserId":"u1","platform":"ios","deviceName":"P","model":"iPhone",
    "appVersion":"1.0.0","syncIntervalMinutes":15,"trackingEnabled":true,"pushInvalid":false,
    "ownerDisplayName":"Eric"
    """

    @Test func listItem_absentLifecycleFields_useDefensiveDefaults() throws {
        let item = try decode(DeviceListItem.self, "{\(listBase)}")
        #expect(item.isDormant == false)
        #expect(item.staleNudgeEnabled == true)
        #expect(item.lastSeenAt == nil)
    }

    @Test func listItem_presentLifecycleFields_areDecoded() throws {
        let item = try decode(
            DeviceListItem.self,
            "{\(listBase),\"lastSeenAt\":\"2026-07-19T09:05:14Z\",\"isDormant\":true,\"staleNudgeEnabled\":false}"
        )
        #expect(item.isDormant == true)
        #expect(item.staleNudgeEnabled == false)
        #expect(item.lastSeenAt == "2026-07-19T09:05:14Z")
    }

    @Test func deviceResponse_staleNudgeEnabled_defaultsTrueWhenAbsent_andDecodesWhenPresent() throws {
        let base = """
        "deviceId":"d1","ownerUserId":"u1","platform":"ios","deviceName":"P","model":"iPhone",
        "appVersion":"1.0.0","syncIntervalMinutes":15,"trackingEnabled":true,"pushInvalid":false
        """
        #expect(try decode(DeviceResponse.self, "{\(base)}").staleNudgeEnabled == true)
        #expect(try decode(DeviceResponse.self, "{\(base),\"staleNudgeEnabled\":false}").staleNudgeEnabled == false)
    }

    @Test func mapDevice_isDormant_defaultsFalseWhenAbsent_andDecodesWhenPresent() throws {
        let base = """
        "deviceId":"d1","deviceName":"P","lat":null,"lon":null,"accuracyM":null,"recordedAt":null,
        "receivedAt":null,"batteryPct":null,"source":null,"trackingEnabled":true,"syncIntervalMinutes":15,
        "isStale":null
        """
        #expect(try decode(DeviceLocation.self, "{\(base)}").isDormant == false)
        #expect(try decode(DeviceLocation.self, "{\(base),\"isDormant\":true}").isDormant == true)
    }
}
