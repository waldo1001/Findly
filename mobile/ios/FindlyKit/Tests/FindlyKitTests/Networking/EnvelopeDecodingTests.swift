import Testing
import Foundation
@testable import FindlyKit

/// specs/004-ios-client.md §3.1, §10 — envelope + error decoding.
struct EnvelopeDecodingTests {

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    @Test func decodesSuccessEnvelope_withFeatures() throws {
        let json = """
        { "data": { "familyId": "fam_9J2Kq7Lm3NpR5sTvWxYz" },
          "features": { "subscriptionStatus": "free",
                        "limits": { "maxDevices": 10, "maxGeofences": 20, "historyDays": 90,
                                    "minSyncIntervalMinutes": 5, "locateRequestsPerDay": 100 },
                        "flags": { "pushToLocate": true, "geofencing": true, "historyReplay": true } } }
        """.data(using: .utf8)!

        struct Payload: Decodable { let familyId: String }
        let envelope = try decoder.decode(Envelope<Payload>.self, from: json)

        #expect(envelope.data.familyId == "fam_9J2Kq7Lm3NpR5sTvWxYz")
        #expect(envelope.features.subscriptionStatus == "free")
        #expect(envelope.features.limits.maxDevices == 10)
        #expect(envelope.features.limits.maxGeofences == 20)
        #expect(envelope.features.limits.historyDays == 90)
        #expect(envelope.features.limits.minSyncIntervalMinutes == 5)
        #expect(envelope.features.limits.locateRequestsPerDay == 100)
        #expect(envelope.features.flags.pushToLocate)
        #expect(envelope.features.flags.geofencing)
        #expect(envelope.features.flags.historyReplay)
    }

    @Test func decodesErrorEnvelope_withRequestIdAndDetails() throws {
        let json = """
        { "error": { "code": "FAMILY_NOT_FOUND", "message": "no such family",
                     "details": { "fields": ["fixes[3].recordedAt"] }, "requestId": "r_a1b2c3d4" } }
        """.data(using: .utf8)!

        let envelope = try decoder.decode(APIErrorEnvelope.self, from: json)

        #expect(envelope.error.code == .familyNotFound)
        #expect(envelope.error.message == "no such family")
        #expect(envelope.error.requestId == "r_a1b2c3d4")
        if case let .array(fields)? = envelope.error.details?["fields"] {
            #expect(fields == [.string("fixes[3].recordedAt")])
        } else {
            Issue.record("expected fields array in details")
        }
    }

    @Test func decodesErrorEnvelope_withoutDetails() throws {
        let json = """
        { "error": { "code": "AUTH_MISSING_TOKEN", "message": "missing bearer", "requestId": "r_z" } }
        """.data(using: .utf8)!

        let envelope = try decoder.decode(APIErrorEnvelope.self, from: json)
        #expect(envelope.error.code == .authMissingToken)
        #expect(envelope.error.details == nil)
    }

    /// specs/004-ios-client.md §3.1 — `Features`/`PlanLimits`/`PlanFlags` mirror 001 §9 exactly,
    /// incl. the specs/005 group limits and `flags.groups`. A pre-groups fixture (no group keys at
    /// all) must still decode — the new fields default to `nil`/`false`.
    @Test func decodesFeatures_preGroupsFixture_defaultsGroupFieldsToNilAndFalse() throws {
        let json = """
        { "data": {}, "features": { "subscriptionStatus": "free",
                      "limits": { "maxDevices": 10, "maxGeofences": 20, "historyDays": 90,
                                  "minSyncIntervalMinutes": 5, "locateRequestsPerDay": 100 },
                      "flags": { "pushToLocate": true, "geofencing": true, "historyReplay": true } } }
        """.data(using: .utf8)!

        struct Empty: Decodable {}
        let envelope = try decoder.decode(Envelope<Empty>.self, from: json)

        #expect(envelope.features.limits.maxActiveGroups == nil)
        #expect(envelope.features.limits.maxGroupMembers == nil)
        #expect(envelope.features.limits.maxGroupDurationDays == nil)
        #expect(envelope.features.limits.groupGraceDays == nil)
        #expect(envelope.features.flags.groups == false)
    }

    /// The 001 §9 example with every group-era field populated.
    @Test func decodesFeatures_withGroupFieldsPopulated() throws {
        let json = """
        { "data": {}, "features": { "subscriptionStatus": "free",
                      "limits": { "maxDevices": 10, "maxGeofences": 20, "historyDays": 90,
                                  "minSyncIntervalMinutes": 5, "locateRequestsPerDay": 100,
                                  "maxActiveGroups": 5, "maxGroupMembers": 50,
                                  "maxGroupDurationDays": 30, "groupGraceDays": 7 },
                      "flags": { "pushToLocate": true, "geofencing": true, "historyReplay": true, "groups": true } } }
        """.data(using: .utf8)!

        struct Empty: Decodable {}
        let envelope = try decoder.decode(Envelope<Empty>.self, from: json)

        #expect(envelope.features.limits.maxActiveGroups == 5)
        #expect(envelope.features.limits.maxGroupMembers == 50)
        #expect(envelope.features.limits.maxGroupDurationDays == 30)
        #expect(envelope.features.limits.groupGraceDays == 7)
        #expect(envelope.features.flags.groups == true)
    }
}
