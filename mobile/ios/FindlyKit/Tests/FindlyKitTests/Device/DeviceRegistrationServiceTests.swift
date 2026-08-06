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

    func makeService(
        userId: String = "u1",
        appVersionTracker: AppVersionRegistrationTracking = InMemoryAppVersionRegistrationTracker()
    ) -> (FakeAPIClient, DeviceRegistrationService) {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = Self.profileExistsHandler()
        let service = DeviceRegistrationService(
            apiClient: api,
            deviceIdProvider: InMemoryDeviceIdProvider(generateUUID: { "fixed-device-id" }),
            deviceInfoProvider: StaticDeviceInfoProvider(platform: "ios", model: "iPhone 15", appVersion: "1.2.3"),
            authProvider: StubAuthProvider(currentUserId: userId),
            appVersionTracker: appVersionTracker
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
        let tracker = InMemoryAppVersionRegistrationTracker()
        let (api, service) = makeService(userId: "u1", appVersionTracker: tracker)

        let registered = await service.registerOnLaunchIfNeeded()

        #expect(registered)
        #expect(api.registerDeviceCalls.count == 1)
        #expect(tracker.lastRegisteredAppVersion(forUserId: "u1") == "1.2.3")
    }

    @Test func registerOnLaunchIfNeeded_sameStoredVersion_skipsRegistration() async throws {
        let tracker = InMemoryAppVersionRegistrationTracker()
        tracker.setLastRegisteredAppVersion("1.2.3", forUserId: "u1")
        let (api, service) = makeService(userId: "u1", appVersionTracker: tracker)

        let registered = await service.registerOnLaunchIfNeeded()

        #expect(!registered)
        #expect(api.registerDeviceCalls.isEmpty)
    }

    @Test func registerOnLaunchIfNeeded_differentStoredVersion_reRegistersAsAnAppUpdate() async throws {
        let tracker = InMemoryAppVersionRegistrationTracker()
        tracker.setLastRegisteredAppVersion("1.2.2", forUserId: "u1")
        let (api, service) = makeService(userId: "u1", appVersionTracker: tracker)

        let registered = await service.registerOnLaunchIfNeeded()

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
            authProvider: StubAuthProvider(currentUserId: nil),
            appVersionTracker: InMemoryAppVersionRegistrationTracker()
        )

        let registered = await service.registerOnLaunchIfNeeded()

        #expect(!registered)
        #expect(api.registerDeviceCalls.isEmpty)
    }

    @Test func registerOnLaunchIfNeeded_differentSignedInUser_isItsOwnFirstLaunch() async throws {
        // A different userId's tracker entry is untouched by another user's registration -
        // signing in as a different family member on the same device is correctly treated as
        // "first launch after sign-in" for THAT user, independent of who registered before.
        let tracker = InMemoryAppVersionRegistrationTracker()
        tracker.setLastRegisteredAppVersion("1.2.3", forUserId: "u1")
        let (api, service) = makeService(userId: "u2", appVersionTracker: tracker)

        let registered = await service.registerOnLaunchIfNeeded()

        #expect(registered)
        #expect(api.registerDeviceCalls.count == 1)
    }

    @Test func registerOnLaunchIfNeeded_registrationFails_doesNotMarkVersionAsRegistered() async throws {
        let tracker = InMemoryAppVersionRegistrationTracker()
        let (api, service) = makeService(userId: "u1", appVersionTracker: tracker)
        api.registerDeviceResult = .failure(APIError.transport("offline"))

        let registered = await service.registerOnLaunchIfNeeded()

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
        let tracker = InMemoryAppVersionRegistrationTracker()
        let (api, service) = makeService(userId: "u1", appVersionTracker: tracker)
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .profileNotFound, message: "no profile", details: nil, requestId: "r1"), httpStatus: 404)
        }

        let registered = await service.registerOnLaunchIfNeeded()

        #expect(!registered)
        #expect(api.registerDeviceCalls.isEmpty)
        #expect(tracker.lastRegisteredAppVersion(forUserId: "u1") == nil, "no profile yet must not be remembered as registered, so the bootstrap-completion retry (RootView) or next launch tries again")
    }

    // MARK: - I24 code review (Finding 2) — the profile probe must NOT run on every single call
    // forever. `appVersionTracker` already records "has this device ever registered successfully
    // for this user" (a prior success proves a profile existed then, since POST /devices requires
    // one) — `registerOrUpdate` consults it to skip the probe once that's established, and keeps
    // it accurate by recording success from EVERY trigger, not just `registerOnLaunchIfNeeded`.

    @Test func registerOrUpdate_hasRegisteredBefore_skipsTheProfileProbe() async throws {
        let tracker = InMemoryAppVersionRegistrationTracker()
        tracker.setLastRegisteredAppVersion("1.2.2", forUserId: "u1")
        let (api, service) = makeService(userId: "u1", appVersionTracker: tracker)
        // No getMyFamilyHandler override — `makeService()` always installs
        // `Self.profileExistsHandler()` as the default, so a regression here would NOT fatalError;
        // it would silently succeed. The `#expect(api.getMyFamilyCallCount == 0, ...)` assertion
        // below is what actually catches the probe firing when it shouldn't.

        _ = try await service.registerOrUpdate()

        #expect(api.getMyFamilyCallCount == 0, "an established device must never pay the extra GET /families/me round trip")
        #expect(api.registerDeviceCalls.count == 1)
    }

    @Test func registerOrUpdate_success_recordsAppVersionRegistered_regardlessOfWhichTriggerCalledIt() async throws {
        // Simulates the observePushTokenRefreshes/observeLocationPushTokenUpdates/onReRegisterDevice
        // triggers, none of which go through registerOnLaunchIfNeeded — the local "ever registered"
        // signal must still end up accurate so a LATER call (from any trigger) can skip the probe.
        let tracker = InMemoryAppVersionRegistrationTracker()
        let (_, service) = makeService(userId: "u1", appVersionTracker: tracker)
        #expect(tracker.lastRegisteredAppVersion(forUserId: "u1") == nil)

        _ = try await service.registerOrUpdate(pushToken: "fcm-token")

        #expect(tracker.lastRegisteredAppVersion(forUserId: "u1") == "1.2.3")
    }

    @Test func registerOrUpdate_hasRegisteredBeforeButProfileDeletedConcurrently_mapsTheRealResponseToTheSameTypedError() async throws {
        // I24 review (Finding 4's scenario): an established device (probe skipped) whose profile
        // was deleted out from under it — e.g. a concurrent DELETE /users/me from another device —
        // gets a genuine 404 PROFILE_NOT_FOUND from the ACTUAL POST /devices call, not the probe.
        // That must map to the SAME DeviceRegistrationError.profileNotYetBootstrapped so every
        // caller's handling (silence, not a logged failure) stays correct either way.
        let tracker = InMemoryAppVersionRegistrationTracker()
        tracker.setLastRegisteredAppVersion("1.2.2", forUserId: "u1")
        let (api, service) = makeService(userId: "u1", appVersionTracker: tracker)
        api.registerDeviceResult = .failure(
            APIError.server(APIErrorBody(code: .profileNotFound, message: "no profile", details: nil, requestId: "r2"), httpStatus: 404)
        )

        do {
            _ = try await service.registerOrUpdate()
            Issue.record("expected DeviceRegistrationError.profileNotYetBootstrapped to be thrown")
        } catch DeviceRegistrationError.profileNotYetBootstrapped {
            // expected
        } catch {
            Issue.record("expected .profileNotYetBootstrapped, got \(error)")
        }
        #expect(api.getMyFamilyCallCount == 0, "the probe must have been skipped — this is the real POST /devices response")
    }

    @Test func registerOrUpdate_hasRegisteredBefore_genuineFailure_propagatesUnchanged() async throws {
        // A non-profile failure (e.g. a transport error) from the real POST /devices call must
        // NOT be reinterpreted as .profileNotYetBootstrapped — only a confirmed PROFILE_NOT_FOUND
        // maps to it.
        let tracker = InMemoryAppVersionRegistrationTracker()
        tracker.setLastRegisteredAppVersion("1.2.2", forUserId: "u1")
        let (api, service) = makeService(userId: "u1", appVersionTracker: tracker)
        api.registerDeviceResult = .failure(APIError.transport("offline"))

        do {
            _ = try await service.registerOrUpdate()
            Issue.record("expected APIError.transport to propagate")
        } catch APIError.transport {
            // expected
        } catch {
            Issue.record("expected APIError.transport, got \(error)")
        }
    }

    // MARK: - I24 review (security, Minor) — `loggableSummary(forDeviceRegistrationFailure:)` is
    // the curated projection `FindlyApp`'s onReRegisterDevice catch logs instead of the whole
    // `Error`. Pure function, fully testable in FindlyKit (unlike the View-layer half of I24,
    // see I18) — every case here asserts the raw free-text is ABSENT, not just that some string
    // is produced.

    @Test func loggableSummary_serverError_includesOnlyCodeHttpStatusAndRequestId() {
        let error = APIError.server(
            APIErrorBody(code: .profileNotFound, message: "some internal debug detail", details: nil, requestId: "req-123"),
            httpStatus: 404
        )

        let summary = loggableSummary(forDeviceRegistrationFailure: error)

        #expect(summary.contains("PROFILE_NOT_FOUND"))
        #expect(summary.contains("404"))
        #expect(summary.contains("req-123"))
        #expect(!summary.contains("some internal debug detail"), "the raw server message must never reach the log")
    }

    @Test func loggableSummary_transportError_dropsTheRawAssociatedString() {
        let summary = loggableSummary(forDeviceRegistrationFailure: APIError.transport("https://internal.example/leaky-detail"))

        #expect(summary == "transport")
        #expect(!summary.contains("leaky-detail"))
    }

    @Test func loggableSummary_decodingError_dropsTheRawAssociatedString() {
        let summary = loggableSummary(forDeviceRegistrationFailure: APIError.decoding("keyNotFound(CodingKeys.secretField...)"))

        #expect(summary == "decoding")
        #expect(!summary.contains("secretField"))
    }

    @Test func loggableSummary_notModified() {
        #expect(loggableSummary(forDeviceRegistrationFailure: APIError.notModified) == "notModified")
    }

    @Test func loggableSummary_nonAPIError_neverIncludesItsOwnDescription() {
        struct SomeOtherError: Error, CustomStringConvertible {
            var description: String { "sensitive-looking payload" }
        }

        let summary = loggableSummary(forDeviceRegistrationFailure: SomeOtherError())

        #expect(!summary.contains("sensitive-looking payload"))
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
