import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §5, specs/001 §4.1 — request construction + the push-token-refresh
/// trigger (001 §4.1, 000 §O4).
struct DeviceRegistrationServiceTests {

    func makeService(userId: String = "u1") -> (FakeAPIClient, DeviceRegistrationService) {
        let api = FakeAPIClient()
        let service = DeviceRegistrationService(
            apiClient: api,
            deviceIdProvider: InMemoryDeviceIdProvider(generateUUID: { "fixed-device-id" }),
            deviceInfoProvider: StaticDeviceInfoProvider(platform: "ios", model: "iPhone 15", appVersion: "1.2.3"),
            authProvider: StubAuthProvider(currentUserId: userId)
        )
        return (api, service)
    }

    @Test func registerOrUpdate_buildsRequestWithPlatformIOS_omittingAbsentTokens() async throws {
        let (api, service) = makeService()
        _ = try await service.registerOrUpdate()

        #expect(api.registerDeviceCalls.count == 1)
        let request = try #require(api.registerDeviceCalls.first)
        #expect(request.platform == "ios")
        #expect(request.model == "iPhone 15")
        #expect(request.appVersion == "1.2.3")
        #expect(request.deviceId == "fixed-device-id")
        #expect(request.pushToken == nil)
        #expect(request.locationPushToken == nil)
    }

    @Test func registerOrUpdate_includesSuppliedPushToken() async throws {
        let (api, service) = makeService()
        _ = try await service.registerOrUpdate(pushToken: "fcm-token-1")

        let request = try #require(api.registerDeviceCalls.first)
        #expect(request.pushToken == "fcm-token-1")
    }

    @Test func pushTokenRefresh_triggersExactlyOneReRegistrationWithTheNewToken() async throws {
        let (api, service) = makeService()
        let pushTokens = StubPushTokenProvider()

        service.observePushTokenRefreshes(pushTokens)
        pushTokens.emit("refreshed-token")

        // Allow the detached observation Task to run.
        try await waitUntil { api.registerDeviceCalls.count == 1 }

        let request = try #require(api.registerDeviceCalls.first)
        #expect(request.pushToken == "refreshed-token")
    }

    // MARK: - specs/004-ios-client.md §5's remaining two triggers: first launch after sign-in,
    // and every app update (compare stored vs running appVersion).

    @Test func registerOnLaunchIfNeeded_noStoredVersion_registersAndStoresTheCurrentVersion() async throws {
        let (api, service) = makeService(userId: "u1")
        let tracker = InMemoryAppVersionRegistrationTracker()

        let registered = await service.registerOnLaunchIfNeeded(appVersionTracker: tracker)

        #expect(registered)
        #expect(api.registerDeviceCalls.count == 1)
        #expect(tracker.lastRegisteredAppVersion(forUserId: "u1") == "1.2.3")
    }

    @Test func registerOnLaunchIfNeeded_sameStoredVersion_skipsRegistration() async throws {
        let (api, service) = makeService(userId: "u1")
        let tracker = InMemoryAppVersionRegistrationTracker()
        tracker.setLastRegisteredAppVersion("1.2.3", forUserId: "u1")

        let registered = await service.registerOnLaunchIfNeeded(appVersionTracker: tracker)

        #expect(!registered)
        #expect(api.registerDeviceCalls.isEmpty)
    }

    @Test func registerOnLaunchIfNeeded_differentStoredVersion_reRegistersAsAnAppUpdate() async throws {
        let (api, service) = makeService(userId: "u1")
        let tracker = InMemoryAppVersionRegistrationTracker()
        tracker.setLastRegisteredAppVersion("1.2.2", forUserId: "u1")

        let registered = await service.registerOnLaunchIfNeeded(appVersionTracker: tracker)

        #expect(registered)
        #expect(api.registerDeviceCalls.count == 1)
        #expect(tracker.lastRegisteredAppVersion(forUserId: "u1") == "1.2.3")
    }

    @Test func registerOnLaunchIfNeeded_noSignedInUser_doesNothing() async throws {
        let api = FakeAPIClient()
        let service = DeviceRegistrationService(
            apiClient: api,
            deviceIdProvider: InMemoryDeviceIdProvider(generateUUID: { "fixed-device-id" }),
            deviceInfoProvider: StaticDeviceInfoProvider(platform: "ios", model: "iPhone 15", appVersion: "1.2.3"),
            authProvider: StubAuthProvider(currentUserId: nil)
        )
        let tracker = InMemoryAppVersionRegistrationTracker()

        let registered = await service.registerOnLaunchIfNeeded(appVersionTracker: tracker)

        #expect(!registered)
        #expect(api.registerDeviceCalls.isEmpty)
    }

    @Test func registerOnLaunchIfNeeded_differentSignedInUser_isItsOwnFirstLaunch() async throws {
        // A different userId's tracker entry is untouched by another user's registration -
        // signing in as a different family member on the same device is correctly treated as
        // "first launch after sign-in" for THAT user, independent of who registered before.
        let (api, service) = makeService(userId: "u2")
        let tracker = InMemoryAppVersionRegistrationTracker()
        tracker.setLastRegisteredAppVersion("1.2.3", forUserId: "u1")

        let registered = await service.registerOnLaunchIfNeeded(appVersionTracker: tracker)

        #expect(registered)
        #expect(api.registerDeviceCalls.count == 1)
    }

    @Test func registerOnLaunchIfNeeded_registrationFails_doesNotMarkVersionAsRegistered() async throws {
        let (api, service) = makeService(userId: "u1")
        api.registerDeviceResult = .failure(APIError.transport("offline"))
        let tracker = InMemoryAppVersionRegistrationTracker()

        let registered = await service.registerOnLaunchIfNeeded(appVersionTracker: tracker)

        #expect(!registered)
        #expect(tracker.lastRegisteredAppVersion(forUserId: "u1") == nil, "a failed call must not be remembered as done, so the next launch/foreground retries it")
    }
}

/// Polls `condition` briefly instead of a fixed `sleep` — avoids test flakiness from a hardcoded delay.
func waitUntil(timeoutMs: Int = 2000, _ condition: @escaping () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .milliseconds(timeoutMs))
    while !condition() {
        if ContinuousClock.now > deadline {
            struct Timeout: Error {}
            throw Timeout()
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}
