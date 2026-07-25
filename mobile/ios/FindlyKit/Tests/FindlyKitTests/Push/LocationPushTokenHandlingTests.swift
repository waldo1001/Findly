import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §7, specs/000 §O1 — the location-push token, once captured, MUST be
/// plumbed into device registration exactly like the regular push token.
struct LocationPushTokenHandlingTests {

    @Test func locationPushTokenUpdate_triggersExactlyOneReRegistrationWithTheToken() async throws {
        let api = FakeAPIClient()
        let service = DeviceRegistrationService(
            apiClient: api,
            deviceIdProvider: InMemoryDeviceIdProvider(generateUUID: { "fixed-device-id" }),
            deviceInfoProvider: StaticDeviceInfoProvider(platform: "ios", model: "iPhone 15", appVersion: "1.2.3"),
            authProvider: StubAuthProvider(currentUserId: "u1")
        )
        let locationPushTokens = StubLocationPushTokenHandler()

        service.observeLocationPushTokenUpdates(locationPushTokens)
        locationPushTokens.emit("apns-location-token-1")

        try await waitUntil { api.registerDeviceCalls.count == 1 }

        let request = try #require(api.registerDeviceCalls.first)
        #expect(request.locationPushToken == "apns-location-token-1")
        #expect(request.pushToken == nil, "unrelated token field stays absent")
    }
}
