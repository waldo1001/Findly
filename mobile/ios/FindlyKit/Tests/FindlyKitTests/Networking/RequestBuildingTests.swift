import Testing
import Foundation
@testable import FindlyKit

/// specs/004-ios-client.md §3.2, §9, §10 — one request-building test per 001 §1.6 endpoint (19
/// total): method, path, headers (incl. `X-Device-Id` only where required), and body shape.
///
/// H1 CI note (2026-07-20): `.serialized` is required, not stylistic. Every test installs its
/// expectations via the process-global `MockURLProtocol.requestHandler` static immediately before
/// firing a request; Swift Testing runs `@Test`s within a suite concurrently by default, so without
/// this trait two tests race on that shared static and observe each other's request/response —
/// the exact failure signature (wrong method/path expected, `keyNotFound` for another endpoint's
/// field) seen the first time this suite actually executed in CI (previously only compile-verified,
/// never run, on the CLT-only sandbox this project was authored in).
@Suite(.serialized)
struct RequestBuildingTests {
    let baseURL = URL(string: "https://api.findly.invalid/api/v1")!

    func makeClient() -> URLSessionAPIClient {
        URLSessionAPIClient(baseURL: baseURL, authProvider: StubAuthProvider(currentUserId: "u1"), session: MockURLProtocol.makeSession())
    }

    func bodyJSON(_ request: URLRequest) throws -> [String: Any] {
        return try #require(JSONSerialization.jsonObject(with: fullBody(of: request)) as? [String: Any])
    }

    // MARK: §3 Families

    @Test func createFamily_buildsRequest() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/v1/families")
            #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-8")
            #expect(request.value(forHTTPHeaderField: "X-Device-Id") == nil)
            let body = try self.bodyJSON(request)
            #expect(body["familyName"] as? String == "Wauters")
            #expect(body["displayName"] as? String == "Eric")
            return (jsonResponse(url: request.url!, status: 201), envelopeJSON(data: """
            { "familyId": "fam_x", "familyName": "Wauters", "member": { "userId": "u1", "role": "parent", "displayName": "Eric" } }
            """))
        }
        let envelope = try await client.createFamily(familyName: "Wauters", displayName: "Eric")
        #expect(envelope.data.familyId == "fam_x")
    }

    @Test func getMyFamily_buildsRequest() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/v1/families/me")
            #expect(request.value(forHTTPHeaderField: "X-Device-Id") == nil)
            return (jsonResponse(url: request.url!, status: 200), envelopeJSON(data: """
            { "familyId": "fam_x", "familyName": "Wauters", "createdAt": "2026-07-19T08:00:00Z",
              "me": { "userId": "u1", "role": "parent" }, "members": [] }
            """))
        }
        let envelope = try await client.getMyFamily()
        #expect(envelope.data.members.isEmpty)
    }

    @Test func createInvite_buildsRequest() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/v1/families/me/invites")
            let body = try self.bodyJSON(request)
            #expect(body["role"] as? String == "member")
            #expect(body["emailHint"] as? String == "kid@example.com")
            return (jsonResponse(url: request.url!, status: 201), envelopeJSON(data: """
            { "inviteCode": "7F3K9QRZ", "role": "member", "expiresAt": "2026-07-22T10:00:00Z" }
            """))
        }
        let envelope = try await client.createInvite(role: "member", emailHint: "kid@example.com")
        #expect(envelope.data.inviteCode == "7F3K9QRZ")
    }

    @Test func acceptInvite_buildsRequest() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/v1/invites/accept")
            let body = try self.bodyJSON(request)
            #expect(body["inviteCode"] as? String == "7f3k-9qrz")
            #expect(body["displayName"] as? String == "Noor")
            return (jsonResponse(url: request.url!, status: 200), envelopeJSON(data: """
            { "familyId": "fam_x", "familyName": "Wauters", "role": "member" }
            """))
        }
        let envelope = try await client.acceptInvite(inviteCode: "7f3k-9qrz", displayName: "Noor")
        #expect(envelope.data.role == "member")
    }

    @Test func updateMember_buildsRequest() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url?.path == "/api/v1/families/me/members/u2")
            let body = try self.bodyJSON(request)
            #expect(body["displayName"] as? String == "Noor W.")
            #expect(body["role"] == nil, "omitted optional fields must not be sent as null")
            return (jsonResponse(url: request.url!, status: 200), envelopeJSON(data: """
            { "userId": "u2", "role": "member", "displayName": "Noor W.", "joinedAt": "2026-07-19T08:00:00Z" }
            """))
        }
        let envelope = try await client.updateMember(userId: "u2", role: nil, displayName: "Noor W.")
        #expect(envelope.data.displayName == "Noor W.")
    }

    @Test func removeMember_buildsRequestAndHandlesNoContent() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url?.path == "/api/v1/families/me/members/u2")
            return (jsonResponse(url: request.url!, status: 204), Data())
        }
        try await client.removeMember(userId: "u2")
    }

    // MARK: §4 Devices

    @Test func registerDevice_buildsRequest_omittingAbsentTokens() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/v1/devices")
            let body = try self.bodyJSON(request)
            #expect(body["deviceId"] as? String == "3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1b")
            #expect(body["platform"] as? String == "ios")
            #expect(body["pushToken"] == nil, "absent token must not be sent as null")
            #expect(body["locationPushToken"] == nil)
            return (jsonResponse(url: request.url!, status: 201), envelopeJSON(data: """
            { "deviceId": "3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1b", "ownerUserId": "u1", "platform": "ios",
              "deviceName": "Eric's phone", "model": "iPhone 15", "appVersion": "1.0.0",
              "syncIntervalMinutes": 15, "trackingEnabled": true, "pushInvalid": false }
            """))
        }
        let request = RegisterDeviceRequest(deviceId: "3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1b", platform: "ios", model: "iPhone 15", appVersion: "1.0.0")
        let envelope = try await client.registerDevice(request)
        #expect(envelope.data.pushInvalid == false)
    }

    @Test func listDevices_buildsRequest() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/v1/devices")
            return (jsonResponse(url: request.url!, status: 200), envelopeJSON(data: "{ \"devices\": [] }"))
        }
        let envelope = try await client.listDevices()
        #expect(envelope.data.devices.isEmpty)
    }

    @Test func updateDevice_buildsRequest() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url?.path == "/api/v1/devices/dev1")
            let body = try self.bodyJSON(request)
            #expect(body["trackingEnabled"] as? Bool == false)
            return (jsonResponse(url: request.url!, status: 200), envelopeJSON(data: """
            { "deviceId": "dev1", "ownerUserId": "u1", "platform": "ios", "deviceName": "n",
              "model": "m", "appVersion": "1.0.0", "syncIntervalMinutes": 15, "trackingEnabled": false, "pushInvalid": false }
            """))
        }
        let envelope = try await client.updateDevice(deviceId: "dev1", UpdateDeviceRequest(trackingEnabled: false))
        #expect(envelope.data.trackingEnabled == false)
    }

    // MARK: §5 Locations

    @Test func reportLocations_buildsRequest_withXDeviceIdHeader() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/v1/locations")
            #expect(request.value(forHTTPHeaderField: "X-Device-Id") == "dev1", "X-Device-Id REQUIRED on device-originated calls")
            let body = try self.bodyJSON(request)
            #expect(body["batchId"] as? String == "batch1")
            return (jsonResponse(url: request.url!, status: 200), envelopeJSON(data: """
            { "accepted": 1, "duplicates": 0, "lastKnownUpdated": true,
              "deviceSettings": { "syncIntervalMinutes": 15, "trackingEnabled": true },
              "geofenceEtag": "\\"0x1\\"" }
            """))
        }
        let fix = LocationFix(fixId: "f1", recordedAt: "2026-07-19T09:05:12Z", lat: 51.0, lon: 3.7, accuracyM: 12.5, batteryPct: 78, source: .periodic)
        let envelope = try await client.reportLocations(deviceId: "dev1", batchId: "batch1", fixes: [fix])
        #expect(envelope.data.accepted == 1)
    }

    @Test func getLatestLocations_buildsRequest() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/v1/locations/latest")
            #expect(request.value(forHTTPHeaderField: "X-Device-Id") == nil)
            return (jsonResponse(url: request.url!, status: 200), envelopeJSON(data: "{ \"members\": [] }"))
        }
        let envelope = try await client.getLatestLocations()
        #expect(envelope.data.members.isEmpty)
    }

    @Test func getLocationHistory_buildsRequest_withQueryItems() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "GET")
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            #expect(components.path == "/api/v1/locations/history")
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
            #expect(query["userId"] ?? nil == "u2")
            #expect(query["from"] ?? nil == "2026-07-01")
            #expect(query["to"] ?? nil == "2026-07-19")
            #expect(query["limit"] ?? nil == "100")
            return (jsonResponse(url: request.url!, status: 200), envelopeJSON(data: "{ \"points\": [], \"nextCursor\": null }"))
        }
        let envelope = try await client.getLocationHistory(userId: "u2", deviceId: nil, from: "2026-07-01", to: "2026-07-19", limit: 100, cursor: nil)
        #expect(envelope.data.points.isEmpty)
    }

    // MARK: §6 Locate

    @Test func createLocateRequest_buildsRequest_targetUser() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/v1/locate-requests")
            let body = try self.bodyJSON(request)
            #expect(body["targetUserId"] as? String == "u2")
            #expect(body["targetDeviceId"] == nil, "exactly one of targetUserId|targetDeviceId")
            return (jsonResponse(url: request.url!, status: 201), envelopeJSON(data: """
            { "requestId": "lr_x", "status": "pending", "targetUserId": "u2", "targetDeviceId": "dev2",
              "expiresAt": "2026-07-19T09:06:12Z", "lastKnown": null }
            """))
        }
        let envelope = try await client.createLocateRequest(target: .user("u2"))
        #expect(envelope.data.status == .pending)
    }

    @Test func pollLocateRequest_buildsRequest() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/v1/locate-requests/lr_x")
            return (jsonResponse(url: request.url!, status: 200), envelopeJSON(data: """
            { "requestId": "lr_x", "status": "pending", "expiresAt": "2026-07-19T09:06:12Z", "fix": null }
            """))
        }
        let envelope = try await client.pollLocateRequest(requestId: "lr_x")
        #expect(envelope.data.status == .pending)
    }

    @Test func fulfillLocateRequest_buildsRequest_withXDeviceIdHeader() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/v1/locate-requests/lr_x/fulfill")
            #expect(request.value(forHTTPHeaderField: "X-Device-Id") == "dev2")
            let body = try self.bodyJSON(request)
            #expect((body["fix"] as? [String: Any])?["source"] as? String == "locate")
            return (jsonResponse(url: request.url!, status: 200), envelopeJSON(data: "{ \"status\": \"fulfilled\" }"))
        }
        let fix = LocationFix(fixId: "f2", recordedAt: "2026-07-19T09:05:44Z", lat: 51.0544, lon: 3.7170, accuracyM: 4.8, batteryPct: 77, source: .locate)
        let envelope = try await client.fulfillLocateRequest(deviceId: "dev2", requestId: "lr_x", fix: fix)
        #expect(envelope.data.status == "fulfilled")
    }

    // MARK: §7 Geofences

    @Test func getGeofences_buildsRequest_returnsOkWithEtag() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/v1/geofences")
            #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"0x1\"")
            return (jsonResponse(url: request.url!, status: 200, headers: ["ETag": "\"0x2\""]), envelopeJSON(data: """
            { "version": 4, "geofences": [] }
            """))
        }
        let result = try await client.getGeofences(ifNoneMatch: "\"0x1\"")
        guard case let .ok(config, etag) = result else { Issue.record("expected .ok"); return }
        #expect(config.version == 4)
        #expect(etag == "\"0x2\"")
    }

    @Test func getGeofences_returnsNotModifiedOn304() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            (jsonResponse(url: request.url!, status: 304), Data())
        }
        let result = try await client.getGeofences(ifNoneMatch: "\"0x2\"")
        #expect(result == .notModified)
    }

    @Test func replaceGeofences_buildsRequest_withIfMatchAndReturnsNewEtag() async throws {
        let client = makeClient()
        let geofence = Geofence(geofenceId: "gf_home", name: "Home", lat: 51.0543, lon: 3.7174, radiusM: 150, icon: "home", notifyOnEnter: true, notifyOnExit: true)
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "PUT")
            #expect(request.url?.path == "/api/v1/geofences")
            #expect(request.value(forHTTPHeaderField: "If-Match") == "\"0\"")
            let body = try self.bodyJSON(request)
            #expect((body["geofences"] as? [[String: Any]])?.count == 1)
            return (jsonResponse(url: request.url!, status: 200, headers: ["ETag": "\"0x3\""]), envelopeJSON(data: """
            { "version": 5, "geofences": [] }
            """))
        }
        let result = try await client.replaceGeofences([geofence], ifMatch: "\"0\"")
        #expect(result.config.data.version == 5)
        #expect(result.etag == "\"0x3\"")
    }

    @Test func reportGeofenceEvents_buildsRequest_withXDeviceIdHeader() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/v1/geofence-events")
            #expect(request.value(forHTTPHeaderField: "X-Device-Id") == "dev1")
            return (jsonResponse(url: request.url!, status: 200), envelopeJSON(data: """
            { "accepted": 1, "duplicates": 0, "deviceSettings": { "syncIntervalMinutes": 15, "trackingEnabled": true }, "geofenceEtag": "\\"0x1\\"" }
            """))
        }
        let event = GeofenceEventReport(eventId: "e1", geofenceId: "gf_home", transition: .enter, recordedAt: "2026-07-19T15:03:22Z")
        let envelope = try await client.reportGeofenceEvents(deviceId: "dev1", events: [event])
        #expect(envelope.data.accepted == 1)
    }

    @Test func getGeofenceEventHistory_buildsRequest_withQueryItems() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            #expect(components.path == "/api/v1/geofence-events")
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
            #expect(query["from"] ?? nil == "2026-07-01")
            #expect(query["to"] ?? nil == "2026-07-19")
            return (jsonResponse(url: request.url!, status: 200), envelopeJSON(data: "{ \"events\": [], \"nextCursor\": null }"))
        }
        let envelope = try await client.getGeofenceEventHistory(from: "2026-07-01", to: "2026-07-19", userId: nil, limit: nil, cursor: nil)
        #expect(envelope.data.events.isEmpty)
    }

    // MARK: §12 Groups (specs/005-temporary-groups.md; wire shapes 001 §12)

    @Test func createGroup_buildsRequest() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/v1/groups")
            let body = try self.bodyJSON(request)
            #expect(body["name"] as? String == "Festival crew")
            #expect(body["endsAt"] as? String == "2026-08-02T22:00:00Z")
            #expect(body["expiryPolicy"] as? String == "delete")
            #expect(body["displayName"] as? String == "Eric")
            return (jsonResponse(url: request.url!, status: 201), envelopeJSON(data: """
            { "groupId": "grp_9J2Kq7Lm3NpR5sTvWxYz", "name": "Festival crew",
              "endsAt": "2026-08-02T22:00:00Z", "expiryPolicy": "delete", "state": "active",
              "role": "owner", "memberCount": 1, "code": "7F3K9QRZ",
              "createdAt": "2026-07-21T10:00:00Z" }
            """))
        }
        let envelope = try await client.createGroup(name: "Festival crew", endsAt: "2026-08-02T22:00:00Z", expiryPolicy: "delete", displayName: "Eric")
        #expect(envelope.data.groupId == "grp_9J2Kq7Lm3NpR5sTvWxYz")
        #expect(envelope.data.code == "7F3K9QRZ")
        #expect(envelope.data.createdAt == "2026-07-21T10:00:00Z")
    }

    @Test func listGroups_buildsRequest() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/v1/groups")
            return (jsonResponse(url: request.url!, status: 200), envelopeJSON(data: """
            { "groups": [ { "groupId": "grp_x", "name": "Festival crew", "endsAt": "2026-08-02T22:00:00Z",
              "expiryPolicy": "delete", "state": "active", "role": "owner", "memberCount": 7, "code": "7F3K9QRZ" } ] }
            """))
        }
        let envelope = try await client.listGroups()
        #expect(envelope.data.groups.count == 1)
        #expect(envelope.data.groups[0].createdAt == nil, "list items omit createdAt")
    }

    @Test func getGroup_buildsRequest_withRoster() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/v1/groups/grp_x")
            return (jsonResponse(url: request.url!, status: 200), envelopeJSON(data: """
            { "groupId": "grp_x", "name": "Festival crew", "endsAt": "2026-08-02T22:00:00Z",
              "expiryPolicy": "delete", "state": "active", "role": "member", "memberCount": 2,
              "code": "7F3K9QRZ", "createdAt": "2026-07-21T10:00:00Z",
              "members": [ { "userId": "u1", "displayName": "Eric", "role": "owner", "joinedAt": "2026-07-21T10:00:00Z" },
                            { "userId": "u9", "displayName": "Noor", "role": "member", "joinedAt": "2026-07-21T10:05:00Z" } ] }
            """))
        }
        let envelope = try await client.getGroup(groupId: "grp_x")
        #expect(envelope.data.members?.count == 2)
    }

    @Test func getGroup_buildsRequest_hiddenRosterDuringGrace() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            (jsonResponse(url: request.url!, status: 200), envelopeJSON(data: """
            { "groupId": "grp_x", "name": "Festival crew", "endsAt": "2026-08-02T22:00:00Z",
              "expiryPolicy": "grace", "state": "ended", "role": "member", "memberCount": 2,
              "code": null, "createdAt": "2026-07-21T10:00:00Z", "members": null }
            """))
        }
        let envelope = try await client.getGroup(groupId: "grp_x")
        #expect(envelope.data.members == nil, "roster hidden for a non-owner during grace, 005 §2.3")
        #expect(envelope.data.code == nil)
    }

    @Test func updateGroup_buildsRequest() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url?.path == "/api/v1/groups/grp_x")
            let body = try self.bodyJSON(request)
            #expect(body["endsAt"] as? String == "2026-08-03T22:00:00Z")
            #expect(body["name"] == nil, "omitted optional fields must not be sent as null")
            return (jsonResponse(url: request.url!, status: 200), envelopeJSON(data: """
            { "groupId": "grp_x", "name": "Festival crew", "endsAt": "2026-08-03T22:00:00Z",
              "expiryPolicy": "delete", "state": "active", "role": "owner", "memberCount": 1, "code": "7F3K9QRZ" }
            """))
        }
        let envelope = try await client.updateGroup(groupId: "grp_x", name: nil, endsAt: "2026-08-03T22:00:00Z")
        #expect(envelope.data.endsAt == "2026-08-03T22:00:00Z")
    }

    @Test func deleteGroup_buildsRequestAndHandlesNoContent() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url?.path == "/api/v1/groups/grp_x")
            return (jsonResponse(url: request.url!, status: 204), Data())
        }
        try await client.deleteGroup(groupId: "grp_x")
    }

    @Test func joinGroup_buildsRequest() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/v1/groups/join")
            let body = try self.bodyJSON(request)
            #expect(body["code"] as? String == "7f3k-9qrz")
            #expect(body["displayName"] as? String == "Noor")
            return (jsonResponse(url: request.url!, status: 200), envelopeJSON(data: """
            { "groupId": "grp_x", "name": "Festival crew", "endsAt": "2026-08-02T22:00:00Z",
              "expiryPolicy": "delete", "state": "active", "role": "member", "memberCount": 8, "code": "7F3K9QRZ" }
            """))
        }
        let envelope = try await client.joinGroup(code: "7f3k-9qrz", displayName: "Noor")
        #expect(envelope.data.role == "member")
        #expect(envelope.data.memberCount == 8)
    }

    @Test func rotateGroupCode_buildsRequest() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/v1/groups/grp_x/code/rotate")
            return (jsonResponse(url: request.url!, status: 200), envelopeJSON(data: """
            { "code": "9XPT4WKA", "rotatedAt": "2026-07-21T10:05:00Z" }
            """))
        }
        let envelope = try await client.rotateGroupCode(groupId: "grp_x")
        #expect(envelope.data.code == "9XPT4WKA")
    }

    @Test func leaveGroup_buildsRequestAndHandlesNoContent() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/v1/groups/grp_x/leave")
            return (jsonResponse(url: request.url!, status: 204), Data())
        }
        try await client.leaveGroup(groupId: "grp_x")
    }

    @Test func removeGroupMember_buildsRequestAndHandlesNoContent() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url?.path == "/api/v1/groups/grp_x/members/u9")
            return (jsonResponse(url: request.url!, status: 204), Data())
        }
        try await client.removeGroupMember(groupId: "grp_x", userId: "u9")
    }

    @Test func getGroupLatestLocations_buildsRequest_positionOnly() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/v1/groups/grp_x/locations/latest")
            return (jsonResponse(url: request.url!, status: 200), envelopeJSON(data: """
            { "members": [
                { "userId": "u1", "displayName": "Eric", "role": "owner",
                  "location": { "lat": 51.0543, "lon": 3.7174, "accuracyM": 15.0,
                                "recordedAt": "2026-07-21T09:58:00Z", "receivedAt": "2026-07-21T09:58:02Z",
                                "isStale": false } },
                { "userId": "u9", "displayName": "Noor", "role": "member", "location": null } ] }
            """))
        }
        let envelope = try await client.getGroupLatestLocations(groupId: "grp_x")
        #expect(envelope.data.members.count == 2)
        #expect(envelope.data.members[0].location?.lat == 51.0543)
        #expect(envelope.data.members[1].location == nil)
    }
}
