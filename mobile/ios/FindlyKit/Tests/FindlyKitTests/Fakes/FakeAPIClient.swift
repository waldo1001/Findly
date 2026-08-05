import Foundation
@testable import FindlyKit

/// A `FindlyAPIClient` test double. `registerDevice` keeps its original I1 `Result`-based shape
/// (existing `DeviceRegistrationServiceTests` depend on it); every I2 method added below follows a
/// handler-closure shape instead, so a test can vary the response per call (needed for pagination,
/// ETag-conflict, and poll-until-terminal sequences) — anything not configured `fatalError`s, a
/// deliberate signal to extend this fake rather than silently no-op.
final class FakeAPIClient: FindlyAPIClient {
    private(set) var registerDeviceCalls: [RegisterDeviceRequest] = []
    var registerDeviceResult: Result<Envelope<DeviceResponse>, Error> = .success(
        TestFeatures.envelope(DeviceResponse(
            deviceId: "fake-device", ownerUserId: "fake-user", platform: "ios", deviceName: "fake",
            model: "fake", appVersion: "1.0.0", syncIntervalMinutes: 15, trackingEnabled: true, pushInvalid: false
        ))
    )

    func registerDevice(_ request: RegisterDeviceRequest) async throws -> Envelope<DeviceResponse> {
        registerDeviceCalls.append(request)
        return try registerDeviceResult.get()
    }

    // MARK: - §3 Family

    private(set) var createFamilyCalls: [(familyName: String, displayName: String)] = []
    var createFamilyHandler: (String, String) async throws -> Envelope<CreateFamilyResponse> = { _, _ in fatalError("not configured") }
    func createFamily(familyName: String, displayName: String) async throws -> Envelope<CreateFamilyResponse> {
        createFamilyCalls.append((familyName, displayName))
        return try await createFamilyHandler(familyName, displayName)
    }

    private(set) var getMyFamilyCallCount = 0
    var getMyFamilyHandler: () async throws -> Envelope<GetMyFamilyResponse> = { fatalError("not configured") }
    func getMyFamily() async throws -> Envelope<GetMyFamilyResponse> {
        getMyFamilyCallCount += 1
        return try await getMyFamilyHandler()
    }

    private(set) var createInviteCalls: [(role: String, emailHint: String?)] = []
    var createInviteHandler: (String, String?) async throws -> Envelope<CreateInviteResponse> = { _, _ in fatalError("not configured") }
    func createInvite(role: String, emailHint: String?) async throws -> Envelope<CreateInviteResponse> {
        createInviteCalls.append((role, emailHint))
        return try await createInviteHandler(role, emailHint)
    }

    private(set) var acceptInviteCalls: [(inviteCode: String, displayName: String)] = []
    var acceptInviteHandler: (String, String) async throws -> Envelope<AcceptInviteResponse> = { _, _ in fatalError("not configured") }
    func acceptInvite(inviteCode: String, displayName: String) async throws -> Envelope<AcceptInviteResponse> {
        acceptInviteCalls.append((inviteCode, displayName))
        return try await acceptInviteHandler(inviteCode, displayName)
    }

    private(set) var updateMemberCalls: [(userId: String, role: String?, displayName: String?)] = []
    var updateMemberHandler: (String, String?, String?) async throws -> Envelope<FamilyMember> = { _, _, _ in fatalError("not configured") }
    func updateMember(userId: String, role: String?, displayName: String?) async throws -> Envelope<FamilyMember> {
        updateMemberCalls.append((userId, role, displayName))
        return try await updateMemberHandler(userId, role, displayName)
    }

    private(set) var removeMemberCalls: [String] = []
    var removeMemberHandler: (String) async throws -> Void = { _ in fatalError("not configured") }
    func removeMember(userId: String) async throws {
        removeMemberCalls.append(userId)
        try await removeMemberHandler(userId)
    }

    // MARK: - §4 Devices

    private(set) var listDevicesCallCount = 0
    var listDevicesHandler: () async throws -> Envelope<ListDevicesResponse> = { fatalError("not configured") }
    func listDevices() async throws -> Envelope<ListDevicesResponse> {
        listDevicesCallCount += 1
        return try await listDevicesHandler()
    }

    private(set) var updateDeviceCalls: [(deviceId: String, request: UpdateDeviceRequest)] = []
    var updateDeviceHandler: (String, UpdateDeviceRequest) async throws -> Envelope<DeviceResponse> = { _, _ in fatalError("not configured") }
    func updateDevice(deviceId: String, _ request: UpdateDeviceRequest) async throws -> Envelope<DeviceResponse> {
        updateDeviceCalls.append((deviceId, request))
        return try await updateDeviceHandler(deviceId, request)
    }

    // MARK: - §5 Locations

    private(set) var getLatestLocationsCallCount = 0
    var getLatestLocationsHandler: () async throws -> Envelope<LatestLocationsResponse> = { fatalError("not configured") }
    func getLatestLocations() async throws -> Envelope<LatestLocationsResponse> {
        getLatestLocationsCallCount += 1
        return try await getLatestLocationsHandler()
    }

    private(set) var reportLocationsCalls: [(deviceId: String, batchId: String, fixes: [LocationFix])] = []
    var reportLocationsHandler: (String, String, [LocationFix]) async throws -> Envelope<ReportLocationsResponse> = { _, _, _ in fatalError("not configured") }
    func reportLocations(deviceId: String, batchId: String, fixes: [LocationFix]) async throws -> Envelope<ReportLocationsResponse> {
        reportLocationsCalls.append((deviceId, batchId, fixes))
        return try await reportLocationsHandler(deviceId, batchId, fixes)
    }

    private(set) var getLocationHistoryCalls: [(userId: String, deviceId: String?, from: String, to: String, limit: Int?, cursor: String?)] = []
    var getLocationHistoryHandler: (String, String?, String, String, Int?, String?) async throws -> Envelope<LocationHistoryResponse> = { _, _, _, _, _, _ in fatalError("not configured") }
    func getLocationHistory(userId: String, deviceId: String?, from: String, to: String, limit: Int?, cursor: String?) async throws -> Envelope<LocationHistoryResponse> {
        getLocationHistoryCalls.append((userId, deviceId, from, to, limit, cursor))
        return try await getLocationHistoryHandler(userId, deviceId, from, to, limit, cursor)
    }

    // MARK: - §6 Locate

    private(set) var createLocateRequestCalls: [LocateTarget] = []
    var createLocateRequestHandler: (LocateTarget) async throws -> Envelope<CreateLocateRequestResponse> = { _ in fatalError("not configured") }
    func createLocateRequest(target: LocateTarget) async throws -> Envelope<CreateLocateRequestResponse> {
        createLocateRequestCalls.append(target)
        return try await createLocateRequestHandler(target)
    }

    private(set) var pollLocateRequestCalls: [String] = []
    var pollLocateRequestHandler: (String) async throws -> Envelope<PollLocateRequestResponse> = { _ in fatalError("not configured") }
    func pollLocateRequest(requestId: String) async throws -> Envelope<PollLocateRequestResponse> {
        pollLocateRequestCalls.append(requestId)
        return try await pollLocateRequestHandler(requestId)
    }

    private(set) var fulfillLocateRequestCalls: [(deviceId: String, requestId: String, fix: LocationFix)] = []
    var fulfillLocateRequestHandler: (String, String, LocationFix) async throws -> Envelope<FulfillLocateRequestResponse> = { _, _, _ in fatalError("not configured") }
    func fulfillLocateRequest(deviceId: String, requestId: String, fix: LocationFix) async throws -> Envelope<FulfillLocateRequestResponse> {
        fulfillLocateRequestCalls.append((deviceId, requestId, fix))
        return try await fulfillLocateRequestHandler(deviceId, requestId, fix)
    }

    // MARK: - §7 Geofences

    private(set) var getGeofencesCalls: [String?] = []
    var getGeofencesHandler: (String?) async throws -> GeofencesResult = { _ in fatalError("not configured") }
    func getGeofences(ifNoneMatch: String?) async throws -> GeofencesResult {
        getGeofencesCalls.append(ifNoneMatch)
        return try await getGeofencesHandler(ifNoneMatch)
    }

    private(set) var replaceGeofencesCalls: [(geofences: [Geofence], ifMatch: String)] = []
    var replaceGeofencesHandler: ([Geofence], String) async throws -> (config: Envelope<GeofenceConfig>, etag: String) = { _, _ in fatalError("not configured") }
    func replaceGeofences(_ geofences: [Geofence], ifMatch: String) async throws -> (config: Envelope<GeofenceConfig>, etag: String) {
        replaceGeofencesCalls.append((geofences, ifMatch))
        return try await replaceGeofencesHandler(geofences, ifMatch)
    }

    private(set) var reportGeofenceEventsCalls: [(deviceId: String, events: [GeofenceEventReport])] = []
    var reportGeofenceEventsHandler: (String, [GeofenceEventReport]) async throws -> Envelope<ReportGeofenceEventsResponse> = { _, _ in fatalError("not configured") }
    func reportGeofenceEvents(deviceId: String, events: [GeofenceEventReport]) async throws -> Envelope<ReportGeofenceEventsResponse> {
        reportGeofenceEventsCalls.append((deviceId, events))
        return try await reportGeofenceEventsHandler(deviceId, events)
    }

    func getGeofenceEventHistory(from: String, to: String, userId: String?, limit: Int?, cursor: String?) async throws -> Envelope<GeofenceEventHistoryResponse> { fatalError("not configured") }

    // MARK: - §12 Groups

    private(set) var createGroupCalls: [(name: String, endsAt: String, expiryPolicy: String, displayName: String?)] = []
    var createGroupHandler: (String, String, String, String?) async throws -> Envelope<GroupSummary> = { _, _, _, _ in fatalError("not configured") }
    func createGroup(name: String, endsAt: String, expiryPolicy: String, displayName: String?) async throws -> Envelope<GroupSummary> {
        createGroupCalls.append((name, endsAt, expiryPolicy, displayName))
        return try await createGroupHandler(name, endsAt, expiryPolicy, displayName)
    }

    private(set) var listGroupsCallCount = 0
    var listGroupsHandler: () async throws -> Envelope<ListGroupsResponse> = { fatalError("not configured") }
    func listGroups() async throws -> Envelope<ListGroupsResponse> {
        listGroupsCallCount += 1
        return try await listGroupsHandler()
    }

    private(set) var getGroupCalls: [String] = []
    var getGroupHandler: (String) async throws -> Envelope<GroupDetail> = { _ in fatalError("not configured") }
    func getGroup(groupId: String) async throws -> Envelope<GroupDetail> {
        getGroupCalls.append(groupId)
        return try await getGroupHandler(groupId)
    }

    private(set) var updateGroupCalls: [(groupId: String, name: String?, endsAt: String?)] = []
    var updateGroupHandler: (String, String?, String?) async throws -> Envelope<GroupSummary> = { _, _, _ in fatalError("not configured") }
    func updateGroup(groupId: String, name: String?, endsAt: String?) async throws -> Envelope<GroupSummary> {
        updateGroupCalls.append((groupId, name, endsAt))
        return try await updateGroupHandler(groupId, name, endsAt)
    }

    private(set) var deleteGroupCalls: [String] = []
    var deleteGroupHandler: (String) async throws -> Void = { _ in fatalError("not configured") }
    func deleteGroup(groupId: String) async throws {
        deleteGroupCalls.append(groupId)
        try await deleteGroupHandler(groupId)
    }

    private(set) var joinGroupCalls: [(code: String, displayName: String?)] = []
    var joinGroupHandler: (String, String?) async throws -> Envelope<GroupSummary> = { _, _ in fatalError("not configured") }
    func joinGroup(code: String, displayName: String?) async throws -> Envelope<GroupSummary> {
        joinGroupCalls.append((code, displayName))
        return try await joinGroupHandler(code, displayName)
    }

    private(set) var rotateGroupCodeCalls: [String] = []
    var rotateGroupCodeHandler: (String) async throws -> Envelope<RotateGroupCodeResponse> = { _ in fatalError("not configured") }
    func rotateGroupCode(groupId: String) async throws -> Envelope<RotateGroupCodeResponse> {
        rotateGroupCodeCalls.append(groupId)
        return try await rotateGroupCodeHandler(groupId)
    }

    private(set) var leaveGroupCalls: [String] = []
    var leaveGroupHandler: (String) async throws -> Void = { _ in fatalError("not configured") }
    func leaveGroup(groupId: String) async throws {
        leaveGroupCalls.append(groupId)
        try await leaveGroupHandler(groupId)
    }

    private(set) var removeGroupMemberCalls: [(groupId: String, userId: String)] = []
    var removeGroupMemberHandler: (String, String) async throws -> Void = { _, _ in fatalError("not configured") }
    func removeGroupMember(groupId: String, userId: String) async throws {
        removeGroupMemberCalls.append((groupId, userId))
        try await removeGroupMemberHandler(groupId, userId)
    }

    private(set) var getGroupLatestLocationsCalls: [String] = []
    var getGroupLatestLocationsHandler: (String) async throws -> Envelope<GroupLatestLocationsResponse> = { _ in fatalError("not configured") }
    func getGroupLatestLocations(groupId: String) async throws -> Envelope<GroupLatestLocationsResponse> {
        getGroupLatestLocationsCalls.append(groupId)
        return try await getGroupLatestLocationsHandler(groupId)
    }

    // MARK: - §13 Privacy (specs/008; wire shapes 001 §13)

    private(set) var exportDataCalls: [String?] = []
    var exportDataHandler: (String?) async throws -> Data = { _ in fatalError("not configured") }
    func exportData(userId: String?) async throws -> Data {
        exportDataCalls.append(userId)
        return try await exportDataHandler(userId)
    }

    private(set) var deleteAccountCallCount = 0
    var deleteAccountHandler: () async throws -> Void = { fatalError("not configured") }
    func deleteAccount() async throws {
        deleteAccountCallCount += 1
        try await deleteAccountHandler()
    }

    private(set) var deleteFamilyCallCount = 0
    var deleteFamilyHandler: () async throws -> Void = { fatalError("not configured") }
    func deleteFamily() async throws {
        deleteFamilyCallCount += 1
        try await deleteFamilyHandler()
    }
}
