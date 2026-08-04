import Testing
@testable import FindlyKit

/// I15 round-2 code review — `AppDelegate.application(_:didReceiveRemoteNotification:
/// fetchCompletionHandler:)` and `NotificationService.didReceive(_:withContentHandler:)`
/// (FindlyNotificationService extension target) each needed the identical `[AnyHashable: Any]` ->
/// `[String: String]` conversion (001 §8: "all `data` values are strings — clients parse"). The
/// reviewer found the two were a byte-for-byte duplicate; this collapses them into one shared,
/// unit-tested implementation instead of two independent copies of the same few lines.
struct PushPayloadParsingTests {

    @Test func stringKeysAndValues_passThroughAsStrings() {
        let userInfo: [AnyHashable: Any] = ["type": "GEOFENCE_EVENT", "displayName": "Noor"]
        let data = PushPayloadParsing.stringData(from: userInfo)
        #expect(data == ["type": "GEOFENCE_EVENT", "displayName": "Noor"])
    }

    @Test func nonStringValue_isStringInterpolated() {
        let userInfo: [AnyHashable: Any] = ["count": 3]
        let data = PushPayloadParsing.stringData(from: userInfo)
        #expect(data == ["count": "3"])
    }

    @Test func nonStringKey_isDropped() {
        let userInfo: [AnyHashable: Any] = [1: "one", "type": "GEOFENCE_EVENT"]
        let data = PushPayloadParsing.stringData(from: userInfo)
        #expect(data == ["type": "GEOFENCE_EVENT"])
    }

    @Test func emptyUserInfo_yieldsEmptyData() {
        let data = PushPayloadParsing.stringData(from: [:])
        #expect(data.isEmpty)
    }

    @Test func nestedDictValue_isStringInterpolated_notCrashed() {
        // Real pushes carry the "aps" key with a nested dict value alongside the flat custom
        // `data` fields (specs/001 §8) — this must never crash, even though nothing downstream
        // ever reads this particular key back out.
        let userInfo: [AnyHashable: Any] = ["aps": ["alert": ["title": "Noor arrived at Home"]], "type": "GEOFENCE_EVENT"]
        let data = PushPayloadParsing.stringData(from: userInfo)
        #expect(data["type"] == "GEOFENCE_EVENT")
        #expect(data["aps"] != nil)
    }
}
