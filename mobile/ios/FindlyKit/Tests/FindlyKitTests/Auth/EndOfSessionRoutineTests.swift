import Foundation
import Testing
@testable import FindlyKit

/// specs/008-privacy-endpoints.md §3.1/§4.4, specs/009-device-runtime.md §9 (I43) — the ONE shared
/// end-of-session routine every path that ends a signed-in session on this device must call. This
/// suite proves the routine itself does the right thing for both `Options` axes; the two
/// `DeleteAccountViewModel` call sites' own routing through it is (still) proven end-to-end by
/// `DeleteAccountViewModelTests`. `FindlyApp.swift`'s forced `onSignedOut` closure and
/// `RootView.clearSessionOnConfirmedAuthFailure()` are deliberately kept thin one-call wrappers
/// around this routine — `swift test` cannot see app-target wiring (specs/004-ios-client.md §2), so
/// those two call sites are verified by the mandatory `xcodebuild build` gate plus code review, not
/// a unit test.
@MainActor
struct EndOfSessionRoutineTests {

    /// Mirrors `LocationRuntimeContainer.wipeLocalState()` without needing a real container —
    /// `LocationRuntimeContainerTests` owns proving what the real method actually clears.
    private final class WipeLocalStateRecorder {
        private(set) var callCount = 0
        func wipe() async { callCount += 1 }
    }

    // MARK: - The I43 bug this routine exists to close: default options clear everything

    @Test func run_defaultOptions_removesTheExportArtifact() async {
        let exportArtifactStore = InMemoryExportArtifactStore()
        _ = try? exportArtifactStore.write(Data("leftover export".utf8))
        let auth = FakeAuthProviding()
        auth.currentUserId = "u1"

        await EndOfSessionRoutine.run(
            currentUserId: auth.currentUserId,
            authProvider: auth,
            deviceIdProvider: InMemoryDeviceIdProvider(),
            appVersionTracker: InMemoryAppVersionRegistrationTracker(),
            exportArtifactStore: exportArtifactStore,
            wipeLocalState: {}
        )

        #expect(exportArtifactStore.currentURL == nil, "008 §3.1/§4.4, 009 §9 (I43) — a previous user's plaintext export must not outlive a forced sign-out")
    }

    @Test func run_defaultOptions_clearsDeviceIdAndAppVersionTracker_forTheCapturedUid() async {
        let deviceIdProvider = InMemoryDeviceIdProvider()
        let originalDeviceId = deviceIdProvider.deviceId(forUserId: "u1")
        let appVersionTracker = InMemoryAppVersionRegistrationTracker()
        appVersionTracker.setLastRegisteredAppVersion("1.0.0", forUserId: "u1")
        let auth = FakeAuthProviding()
        auth.currentUserId = "u1"

        await EndOfSessionRoutine.run(
            currentUserId: auth.currentUserId,
            authProvider: auth,
            deviceIdProvider: deviceIdProvider,
            appVersionTracker: appVersionTracker,
            exportArtifactStore: InMemoryExportArtifactStore(),
            wipeLocalState: {}
        )

        #expect(deviceIdProvider.deviceId(forUserId: "u1") != originalDeviceId, "a freshly-generated id proves the old one was actually cleared, not merely re-read")
        #expect(appVersionTracker.lastRegisteredAppVersion(forUserId: "u1") == nil)
    }

    @Test func run_defaultOptions_wipesLocalState_clearsStoredSession_andSignsOut() async {
        let recorder = WipeLocalStateRecorder()
        let auth = FakeAuthProviding()
        auth.currentUserId = "u1"

        await EndOfSessionRoutine.run(
            currentUserId: auth.currentUserId,
            authProvider: auth,
            deviceIdProvider: InMemoryDeviceIdProvider(),
            appVersionTracker: InMemoryAppVersionRegistrationTracker(),
            exportArtifactStore: InMemoryExportArtifactStore(),
            wipeLocalState: { await recorder.wipe() }
        )

        #expect(recorder.callCount == 1)
        #expect(auth.clearStoredSessionCallCount == 1)
        #expect(auth.signOutCallCount == 1)
    }

    // MARK: - Options mechanics, exercised directly (call-site routing is proven by DeleteAccountViewModelTests / RootView's own thin wrapper)

    /// Proves the `clearsDeviceIdentityAndExportArtifact: false` axis still behaves correctly as a
    /// mechanism, even though **no call site in the app target uses it any more (I44, specs/008
    /// §3.1)** — `DeleteAccountViewModel.signOutForRetry()` was the one caller that ever passed
    /// `false` here (I25 review: the backend account is already gone, but a SAME-uid sign-in was
    /// assumed to be the very next step, so a stale `deviceIdProvider`/`exportArtifactStore` read
    /// under that same uid was assumed harmless). I44 found that assumption unenforced — a
    /// DIFFERENT person can reach sign-in from the retry state first — and switched
    /// `signOutForRetry()` to the routine's default (`true`). This test is kept as a direct unit
    /// test of the `Options` struct's own behavior (a future call site could still have a reason to
    /// set it), not as a proof of any current caller's shape; see `Options.clearsDeviceIdentityAndExportArtifact`'s
    /// doc for the full history and I44's dead-option flag.
    @Test func run_clearsDeviceIdentityAndExportArtifactFalse_leavesThoseTwoAlone_butStillClearsAppVersionTrackerAndWipesAndSignsOut() async {
        let deviceIdProvider = InMemoryDeviceIdProvider()
        let originalDeviceId = deviceIdProvider.deviceId(forUserId: "u1")
        let exportArtifactStore = InMemoryExportArtifactStore()
        _ = try? exportArtifactStore.write(Data("leftover export".utf8))
        let appVersionTracker = InMemoryAppVersionRegistrationTracker()
        appVersionTracker.setLastRegisteredAppVersion("1.0.0", forUserId: "u1")
        let recorder = WipeLocalStateRecorder()
        let auth = FakeAuthProviding()
        auth.currentUserId = "u1"

        await EndOfSessionRoutine.run(
            currentUserId: auth.currentUserId,
            authProvider: auth,
            deviceIdProvider: deviceIdProvider,
            appVersionTracker: appVersionTracker,
            exportArtifactStore: exportArtifactStore,
            wipeLocalState: { await recorder.wipe() },
            options: .init(clearsDeviceIdentityAndExportArtifact: false)
        )

        #expect(deviceIdProvider.deviceId(forUserId: "u1") == originalDeviceId, "I25 — deferred until wipeLocalStateAndComplete() confirms full teardown")
        #expect(exportArtifactStore.currentURL != nil, "I25 — deferred until wipeLocalStateAndComplete() confirms full teardown")
        #expect(appVersionTracker.lastRegisteredAppVersion(forUserId: "u1") == nil, "appVersionTracker gates control flow, unlike the two plain values above — cleared unconditionally")
        #expect(recorder.callCount == 1)
        #expect(auth.clearStoredSessionCallCount == 1)
        #expect(auth.signOutCallCount == 1)
    }

    /// `RootView.clearSessionOnConfirmedAuthFailure()`'s shape (A37 review, Finding 4): the
    /// Keychain-backed `verificationID` is an opaque OTP-step handle that `signOut()`'s own teardown
    /// already makes moot — not this path's territory.
    @Test func run_clearsStoredSessionFalse_leavesStoredSessionAlone_butStillClearsEverythingElseAndSignsOut() async {
        let exportArtifactStore = InMemoryExportArtifactStore()
        _ = try? exportArtifactStore.write(Data("leftover export".utf8))
        let deviceIdProvider = InMemoryDeviceIdProvider()
        let originalDeviceId = deviceIdProvider.deviceId(forUserId: "u1")
        let recorder = WipeLocalStateRecorder()
        let auth = FakeAuthProviding()
        auth.currentUserId = "u1"

        await EndOfSessionRoutine.run(
            currentUserId: auth.currentUserId,
            authProvider: auth,
            deviceIdProvider: deviceIdProvider,
            appVersionTracker: InMemoryAppVersionRegistrationTracker(),
            exportArtifactStore: exportArtifactStore,
            wipeLocalState: { await recorder.wipe() },
            options: .init(clearsStoredSession: false)
        )

        #expect(auth.clearStoredSessionCallCount == 0)
        #expect(exportArtifactStore.currentURL == nil, "this axis is independent of clearsStoredSession — the export artifact still must not survive")
        #expect(deviceIdProvider.deviceId(forUserId: "u1") != originalDeviceId, "this axis is independent of clearsStoredSession")
        #expect(recorder.callCount == 1)
        #expect(auth.signOutCallCount == 1)
    }

    // MARK: - Defensive edges: the local wipe must never depend on auth state being available

    @Test func run_nilCurrentUserId_skipsUidKeyedClears_butStillWipesLocalStateAndSignsOut() async {
        let deviceIdProvider = InMemoryDeviceIdProvider()
        let appVersionTracker = InMemoryAppVersionRegistrationTracker()
        let recorder = WipeLocalStateRecorder()
        let auth = FakeAuthProviding()
        auth.currentUserId = nil

        await EndOfSessionRoutine.run(
            currentUserId: nil,
            authProvider: auth,
            deviceIdProvider: deviceIdProvider,
            appVersionTracker: appVersionTracker,
            exportArtifactStore: InMemoryExportArtifactStore(),
            wipeLocalState: { await recorder.wipe() }
        )

        #expect(recorder.callCount == 1, "the local wipe must not depend on knowing who was signed in")
        #expect(auth.signOutCallCount == 1)
    }

    @Test func run_nilAuthProvider_stillWipesLocalState_skipsEveryAuthCall() async {
        let recorder = WipeLocalStateRecorder()

        await EndOfSessionRoutine.run(
            currentUserId: nil,
            authProvider: nil,
            deviceIdProvider: InMemoryDeviceIdProvider(),
            appVersionTracker: InMemoryAppVersionRegistrationTracker(),
            exportArtifactStore: InMemoryExportArtifactStore(),
            wipeLocalState: { await recorder.wipe() }
        )

        #expect(recorder.callCount == 1, "a weakly-captured authProvider that happened to already deallocate must not skip the local wipe")
    }
}
