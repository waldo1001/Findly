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
