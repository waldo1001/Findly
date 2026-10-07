import Foundation
import Testing
@testable import FindlyKit

/// Scripted authenticator — `LocalAuthentication` is never called in unit tests.
@MainActor
final class FakeAppLockAuthenticator: AppLockAuthenticating {
    var currentCapability = AppLockCapability(canAuthenticate: true, biometry: .faceID)
    var results: [AppLockAuthResult] = []
    private(set) var authenticateCallCount = 0
    private(set) var lastReason: String?
    /// Suspends `authenticate` until released, to observe the in-flight state.
    var gate: CheckedContinuation<Void, Never>?
    var shouldSuspend = false

    func capability() -> AppLockCapability { currentCapability }

    func authenticate(reason: String) async -> AppLockAuthResult {
        authenticateCallCount += 1
        lastReason = reason
        if shouldSuspend { await withCheckedContinuation { gate = $0 } }
        return results.isEmpty ? .success : results.removeFirst()
    }
}

@MainActor
final class AppLockTestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

/// specs/010-app-shell-and-screen-ux.md §1.4 — the controller that owns lock state, driven by the
/// authenticator seam, the settings store and a scene-phase feed.
@MainActor
struct AppLockControllerTests {
    private final class LockChanges { var values: [Bool] = [] }
    private final class SignedIn { var value = true }

    private struct Harness {
        let controller: AppLockController
        let auth: FakeAppLockAuthenticator
        let store: InMemoryAppLockSettingsStore
        let clock: AppLockTestClock
        let lockChanges: LockChanges
    }

    private func make(enabled: Bool = true, signedIn: Bool = true) -> Harness {
        let auth = FakeAppLockAuthenticator()
        let store = InMemoryAppLockSettingsStore()
        store.isEnabled = enabled
        let clock = AppLockTestClock()
        let changes = LockChanges()
        let flag = SignedIn()
        flag.value = signedIn
        let controller = AppLockController(
            authenticator: auth, store: store, isSignedIn: { flag.value }, now: { clock.now },
            onLockChanged: { changes.values.append($0) }
        )
        return Harness(controller: controller, auth: auth, store: store, clock: clock, lockChanges: changes)
    }

    /// A started, unlocked, enabled session.
    private func makeUnlocked() async -> Harness {
        let h = make()
        h.controller.start(scenePhase: .active)
        await h.controller.unlock()
        return h
    }

    // MARK: - Cold start

    @Test func coldStart_enabledAndSignedIn_locks_andNotifies() {
        let h = make()
        h.controller.start(scenePhase: .active)
        #expect(h.controller.isLocked)
        #expect(h.lockChanges.values == [true])
    }

    @Test func coldStart_disabled_doesNotLock() {
        let h = make(enabled: false)
        h.controller.start(scenePhase: .active)
        #expect(!h.controller.isLocked)
        #expect(h.lockChanges.values.isEmpty)
    }

    @Test func coldStart_signedOut_doesNotLock() {
        let h = make(signedIn: false)
        h.controller.start(scenePhase: .active)
        #expect(!h.controller.isLocked)
    }

    @Test func coldStart_ignoresAStaleBackgroundTimestamp_andClearsIt() {
        let h = make()
        h.store.backgroundedAt = h.clock.now
        h.controller.start(scenePhase: .active)
        #expect(h.controller.isLocked)
        #expect(h.store.backgroundedAt == nil)
    }

    @Test func start_isOneShot() async {
        let h = make()
        h.controller.start(scenePhase: .active)
        await h.controller.unlock()
        #expect(!h.controller.isLocked)
        h.controller.start(scenePhase: .active)
        #expect(!h.controller.isLocked, "a repeated start (re-run .task) must not re-lock")
    }

    /// The device has no screen lock any more (so no way to authenticate, and nothing a gate could
    /// protect): locking would be an unrecoverable lockout, so the lock stays down.
    @Test func coldStart_whenDeviceCannotAuthenticate_doesNotLock() {
        let h = make()
        h.auth.currentCapability = .init(canAuthenticate: false, biometry: .none)
        h.controller.start(scenePhase: .active)
        #expect(!h.controller.isLocked)
    }

    // MARK: - Foreground / background

    @Test func foreground_afterFiveMinutesInBackground_locks() async {
        let h = await makeUnlocked()
        h.controller.scenePhaseChanged(.background)
        h.clock.now += 300
        h.controller.scenePhaseChanged(.active)
        #expect(h.controller.isLocked)
    }

    @Test func foreground_afterLessThanFiveMinutes_doesNotLock() async {
        let h = await makeUnlocked()
        h.controller.scenePhaseChanged(.background)
        h.clock.now += 299
        h.controller.scenePhaseChanged(.active)
        #expect(!h.controller.isLocked)
    }

    @Test func inactiveAlone_doesNotRecordBackgroundTime() async {
        let h = await makeUnlocked()
        h.controller.scenePhaseChanged(.inactive)
        #expect(h.store.backgroundedAt == nil)
        h.clock.now += 3600
        h.controller.scenePhaseChanged(.active)
        #expect(!h.controller.isLocked, "Control Center / the Face ID sheet is .inactive, not a background stint")
    }

    @Test func background_recordsTimestamp_andForegroundClearsIt() async {
        let h = await makeUnlocked()
        h.controller.scenePhaseChanged(.background)
        #expect(h.store.backgroundedAt == h.clock.now)
        h.controller.scenePhaseChanged(.active)
        #expect(h.store.backgroundedAt == nil)
    }

    @Test func background_whileDisabled_recordsNothing() {
        let h = make(enabled: false)
        h.controller.start(scenePhase: .active)
        h.controller.scenePhaseChanged(.background)
        #expect(h.store.backgroundedAt == nil)
    }

    // MARK: - App-switcher cover

    @Test func cover_showsWhenInactiveOrBackground_whileEnabledAndSignedIn() async {
        let h = await makeUnlocked()
        #expect(!h.controller.isCoverVisible)
        h.controller.scenePhaseChanged(.inactive)
        #expect(h.controller.isCoverVisible)
        h.controller.scenePhaseChanged(.background)
        #expect(h.controller.isCoverVisible)
        h.controller.scenePhaseChanged(.active)
        #expect(!h.controller.isCoverVisible)
    }

    @Test func cover_neverShows_whenDisabled() {
        let h = make(enabled: false)
        h.controller.start(scenePhase: .active)
        h.controller.scenePhaseChanged(.inactive)
        h.controller.scenePhaseChanged(.background)
        #expect(!h.controller.isCoverVisible)
    }

    @Test func cover_neverShows_whenSignedOut() {
        let h = make(signedIn: false)
        h.controller.start(scenePhase: .active)
        h.controller.scenePhaseChanged(.background)
        #expect(!h.controller.isCoverVisible)
    }

    // MARK: - Unlock

    @Test func unlock_success_unlocksAndNotifies() async {
        let h = make()
        h.controller.start(scenePhase: .active)
        h.auth.results = [.success]
        await h.controller.unlock()
        #expect(!h.controller.isLocked)
        #expect(h.lockChanges.values == [true, false])
    }

    @Test func unlock_cancelOrFailure_keepsTheLock_andNeverSignsOutOrWipes() async {
        let h = make()
        h.controller.start(scenePhase: .active)
        h.auth.results = [.cancelled, .failed]
        await h.controller.unlock()
        #expect(h.controller.isLocked)
        await h.controller.unlock()
        #expect(h.controller.isLocked)
        #expect(h.controller.isEnabled, "failure must not disable the lock")
        #expect(h.store.isEnabled)
    }

    @Test func unlock_whenNotLocked_doesNotAuthenticate() async {
        let h = make(enabled: false)
        h.controller.start(scenePhase: .active)
        await h.controller.unlock()
        #expect(h.auth.authenticateCallCount == 0)
    }

    @Test func unlock_whileAnAuthenticationIsInFlight_doesNotStartASecond() async {
        let h = make()
        h.controller.start(scenePhase: .active)
        h.auth.shouldSuspend = true
        let first = Task { await h.controller.unlock() }
        await Task.yield()
        await h.controller.unlock()
        #expect(h.auth.authenticateCallCount == 1)
        h.auth.shouldSuspend = false
        h.auth.gate?.resume()
        await first.value
        #expect(!h.controller.isLocked)
    }

    @Test func unlock_usesTheLockReason() async {
        let h = make()
        h.controller.start(scenePhase: .active)
        await h.controller.unlock()
        #expect(h.auth.lastReason == "Unlock Findly")
    }

    // MARK: - Auto prompt: once per lock, only while active

    @Test func autoPrompt_firesOncePerLock_whenActive() async {
        let h = make()
        h.controller.start(scenePhase: .active)
        h.auth.results = [.cancelled]
        await h.controller.autoPromptIfNeeded()
        await h.controller.autoPromptIfNeeded()
        #expect(h.auth.authenticateCallCount == 1, "cancel leaves the lock screen up without re-prompting")
        #expect(h.controller.isLocked)
    }

    @Test func autoPrompt_waitsUntilTheSceneIsActive() async {
        let h = make()
        h.controller.start(scenePhase: .inactive)
        await h.controller.autoPromptIfNeeded()
        #expect(h.auth.authenticateCallCount == 0)
        h.controller.scenePhaseChanged(.active)
        await h.controller.autoPromptIfNeeded()
        #expect(h.auth.authenticateCallCount == 1)
        #expect(!h.controller.isLocked)
    }

    @Test func autoPrompt_rearmsForTheNextLock() async {
        let h = make()
        h.controller.start(scenePhase: .active)
        await h.controller.autoPromptIfNeeded()
        h.controller.scenePhaseChanged(.background)
        h.clock.now += 600
        h.controller.scenePhaseChanged(.active)
        #expect(h.controller.isLocked)
        await h.controller.autoPromptIfNeeded()
        #expect(h.auth.authenticateCallCount == 2)
    }

    // MARK: - Enabling

    @Test func enable_requiresASuccessfulAuthentication() async {
        let h = make(enabled: false)
        h.auth.results = [.success]
        let result = await h.controller.setEnabled(true)
        #expect(result == .enabled)
        #expect(h.controller.isEnabled)
        #expect(h.store.isEnabled)
        #expect(h.auth.authenticateCallCount == 1)
    }

    @Test func enable_failedOrCancelledAuthentication_leavesItOff() async {
        let h = make(enabled: false)
        h.auth.results = [.cancelled, .failed]
        #expect(await h.controller.setEnabled(true) == .authenticationFailed)
        #expect(await h.controller.setEnabled(true) == .authenticationFailed)
        #expect(!h.controller.isEnabled)
        #expect(!h.store.isEnabled)
    }

    @Test func enable_whenDeviceCannotAuthenticate_isUnavailable_withoutPrompting() async {
        let h = make(enabled: false)
        h.auth.currentCapability = .init(canAuthenticate: false, biometry: .none)
        #expect(await h.controller.setEnabled(true) == .unavailable)
        #expect(h.auth.authenticateCallCount == 0)
        #expect(!h.controller.isEnabled)
    }

    @Test func enable_doesNotLockTheCurrentSession() async {
        let h = make(enabled: false)
        _ = await h.controller.setEnabled(true)
        #expect(!h.controller.isLocked)
    }

    @Test func disable_needsNoAuthentication_andClearsPendingState() async {
        let h = await makeUnlocked()
        let callsBefore = h.auth.authenticateCallCount
        h.controller.scenePhaseChanged(.background)
        let result = await h.controller.setEnabled(false)
        #expect(result == .disabled)
        #expect(h.auth.authenticateCallCount == callsBefore)
        #expect(!h.controller.isEnabled)
        #expect(!h.store.isEnabled)
        #expect(h.store.backgroundedAt == nil)
        #expect(!h.controller.isCoverVisible)
    }

    // MARK: - End of session

    @Test func endSession_clearsSettingAndTimestamp_unlocks_andNotifies() {
        let h = make()
        h.controller.start(scenePhase: .active)
        h.store.backgroundedAt = h.clock.now
        h.controller.endSession()
        #expect(!h.controller.isLocked)
        #expect(!h.controller.isEnabled)
        #expect(!h.store.isEnabled)
        #expect(h.store.backgroundedAt == nil)
        #expect(!h.controller.isCoverVisible)
        #expect(h.lockChanges.values == [true, false])
    }

    @Test func afterEndSession_aNewSignIn_isNotLocked() {
        let h = make()
        h.controller.start(scenePhase: .active)
        h.controller.endSession()
        h.controller.scenePhaseChanged(.background)
        h.clock.now += 3600
        h.controller.scenePhaseChanged(.active)
        #expect(!h.controller.isLocked)
    }
}

struct UserDefaultsAppLockSettingsStoreTests {
    private func freshDefaults() -> UserDefaults {
        let name = "AppLockTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaults_toOffWithNoTimestamp() {
        let store = UserDefaultsAppLockSettingsStore(defaults: freshDefaults())
        #expect(!store.isEnabled)
        #expect(store.backgroundedAt == nil)
    }

    @Test func roundTrips_andClears() {
        let defaults = freshDefaults()
        let store = UserDefaultsAppLockSettingsStore(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        store.isEnabled = true
        store.backgroundedAt = date
        #expect(UserDefaultsAppLockSettingsStore(defaults: defaults).isEnabled)
        #expect(UserDefaultsAppLockSettingsStore(defaults: defaults).backgroundedAt == date)
        store.clear()
        #expect(!UserDefaultsAppLockSettingsStore(defaults: defaults).isEnabled)
        #expect(UserDefaultsAppLockSettingsStore(defaults: defaults).backgroundedAt == nil)
    }
}
