import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §5, specs/001 §4.1 — request construction + the push-token-refresh
/// trigger (001 §4.1, 000 §O4).
struct DeviceRegistrationServiceTests {

    /// A profile-exists `getMyFamily()` stub — the default for `makeService()` below, since
    /// `registerOrUpdate` now probes `GET /families/me` before every registration attempt (I24,
    /// specs/001 §1.5.3) and `FakeAPIClient.getMyFamilyHandler` `fatalError`s if never configured.
    /// Mirrors `CreateGroupViewModelTests.profileExistsHandler()`.
    private static func profileExistsHandler() -> () async throws -> Envelope<GetMyFamilyResponse> {
        {
            TestFeatures.envelope(GetMyFamilyResponse(
                familyId: "fam_x", familyName: "Wauters", createdAt: "2026-07-19T08:00:00Z",
                me: MeSummary(userId: "u1", role: "parent"), members: []
            ))
        }
    }

    func makeService(userId: String = "u1") -> (FakeAPIClient, DeviceRegistrationService) {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = Self.profileExistsHandler()
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

    // MARK: - I24 (specs/001 §1.5.3, §4.1) — `POST /devices` is not one of the four
    // profile-bootstrapping endpoints, so a profile-less caller always gets `404
    // PROFILE_NOT_FOUND`. `registerOrUpdate` now probes `GET /families/me` first (the I17 idiom:
    // the component that needs the profile checks for itself) so that doomed call is never made,
    // and the caller can distinguish "not onboarded yet" from a genuine failure.

    @Test func registerOrUpdate_confirmedProfileMissing_throwsProfileNotYetBootstrapped_withoutCallingRegisterDevice() async throws {
        let (api, service) = makeService()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .profileNotFound, message: "no profile", details: nil, requestId: "r1"), httpStatus: 404)
        }

        do {
            _ = try await service.registerOrUpdate()
            Issue.record("expected DeviceRegistrationError.profileNotYetBootstrapped to be thrown")
        } catch DeviceRegistrationError.profileNotYetBootstrapped {
            // expected
        } catch {
            Issue.record("expected .profileNotYetBootstrapped, got \(error)")
        }
        #expect(api.registerDeviceCalls.isEmpty, "the doomed POST /devices call must never be made for a confirmed profile-less caller")
        #expect(api.getMyFamilyCallCount == 1)
    }

    @Test func registerOrUpdate_profileExists_registersNormally() async throws {
        let (api, service) = makeService()

        _ = try await service.registerOrUpdate()

        #expect(api.getMyFamilyCallCount == 1)
        #expect(api.registerDeviceCalls.count == 1)
    }

    @Test func registerOrUpdate_inconclusiveProbe_failsOpenAndStillRegisters() async throws {
        // A transport blip on the probe must never silently stop an already-profiled caller's
        // device from registering/refreshing its push token — same "fail open" reasoning as
        // CreateGroupViewModel.isBootstrappingProfile (I17).
        let (api, service) = makeService()
        api.getMyFamilyHandler = { throw APIError.transport("offline") }

        _ = try await service.registerOrUpdate()

        #expect(api.registerDeviceCalls.count == 1)
    }

    @Test func registerOrUpdate_familyNotFoundProbeResult_stillRegisters() async throws {
        // FAMILY_NOT_FOUND means a profile exists but has no family yet (001 §1.5.3 step 4) —
        // device registration works without a family (§4.1), so this must NOT be treated the
        // same as PROFILE_NOT_FOUND.
        let (api, service) = makeService()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .familyNotFound, message: "no family", details: nil, requestId: "r1"), httpStatus: 404)
        }

        _ = try await service.registerOrUpdate()

        #expect(api.registerDeviceCalls.count == 1)
    }

    @Test func registerOnLaunchIfNeeded_noProfileYet_skipsTheDoomedCall_andDoesNotMarkVersionRegistered() async throws {
        let (api, service) = makeService(userId: "u1")
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .profileNotFound, message: "no profile", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let tracker = InMemoryAppVersionRegistrationTracker()

        let registered = await service.registerOnLaunchIfNeeded(appVersionTracker: tracker)

        #expect(!registered)
        #expect(api.registerDeviceCalls.isEmpty)
        #expect(tracker.lastRegisteredAppVersion(forUserId: "u1") == nil, "no profile yet must not be remembered as registered, so the bootstrap-completion retry (RootView) or next launch tries again")
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
