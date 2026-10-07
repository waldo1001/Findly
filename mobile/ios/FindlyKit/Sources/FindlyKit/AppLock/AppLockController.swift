import Foundation

/// The scene phases the lock cares about (SwiftUI's `ScenePhase`, minus the framework).
public enum AppLockScenePhase: Equatable, Sendable {
    case active
    case inactive
    case background
}

public enum AppLockEnableResult: Equatable, Sendable {
    case enabled
    case disabled
    /// The device has no credential to authenticate with (010 §1.4: the toggle is disabled).
    case unavailable
    /// The one authentication required to switch it on was cancelled or failed.
    case authenticationFailed
}

/// specs/010-app-shell-and-screen-ux.md §1.4 (row I64) — owns the lock state. All decisions come
/// from `AppLockPolicy`; `LocalAuthentication` is reached only through `AppLockAuthenticating`.
///
/// What it never does: sign the user out or wipe anything (010 §1.4 "cancel or failure leaves the
/// lock screen up"), keep its own retry counter (the OS applies its own limits), or touch the
/// device runtime / push handling (009 — the `LOCATE_REQUEST` notification must still display).
@MainActor
public final class AppLockController: ObservableObject {
    @Published public private(set) var isLocked = false
    @Published public private(set) var isEnabled: Bool
    /// The opaque app-switcher cover (010 §1.4): up while the scene is not active and the lock is on.
    @Published public private(set) var isCoverVisible = false
    @Published public private(set) var scenePhase: AppLockScenePhase = .inactive

    private let authenticator: AppLockAuthenticating
    private let store: AppLockSettingsStoring
    private let isSignedIn: () -> Bool
    private let now: () -> Date
    private let onLockChanged: (Bool) -> Void

    private var hasStarted = false
    private var isAuthenticating = false
    private var autoPromptPending = false

    /// - Parameter isSignedIn: read lazily — it reaches `Auth`, which must not be touched before
    ///   `UIApplication.shared` exists (004 §2.6). Only ever invoked from `start`/`scenePhaseChanged`.
    /// - Parameter onLockChanged: wired to `AppCoordinator.setLocked` so deep links wait for unlock.
    public init(
        authenticator: AppLockAuthenticating,
        store: AppLockSettingsStoring = InMemoryAppLockSettingsStore(),
        isSignedIn: @escaping () -> Bool = { false },
        now: @escaping () -> Date = Date.init,
        onLockChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.authenticator = authenticator
        self.store = store
        self.isSignedIn = isSignedIn
        self.now = now
        self.onLockChanged = onLockChanged
        self.isEnabled = store.isEnabled
    }

    /// What the device can authenticate with right now (re-read on demand, never cached).
    public func capability() -> AppLockCapability { authenticator.capability() }

    public var toggleState: AppLockToggleState {
        AppLockToggleState.make(capability: authenticator.capability(), isEnabled: isEnabled)
    }

    // MARK: - Lifecycle

    /// Cold start (010 §1.4: "the lock covers the UI from the first frame after auth restore").
    /// One-shot: a re-run `.task` must not re-lock a session the user already unlocked.
    public func start(scenePhase: AppLockScenePhase) {
        guard !hasStarted else { return }
        hasStarted = true
        self.scenePhase = scenePhase
        updateCover()
        evaluate(isColdStart: true)
    }

    public func scenePhaseChanged(_ phase: AppLockScenePhase) {
        scenePhase = phase
        // `.inactive` alone (Control Center, the Face ID sheet) is not a background stint.
        if phase == .background, isEnabled, isSignedIn() {
            store.backgroundedAt = now()
        }
        updateCover()
        if phase == .active, hasStarted {
            evaluate(isColdStart: false)
        }
    }

    private func evaluate(isColdStart: Bool) {
        let backgroundedAt = store.backgroundedAt
        store.backgroundedAt = nil
        let should = AppLockPolicy.shouldLock(
            enabled: isEnabled, signedIn: isSignedIn(), isColdStart: isColdStart,
            backgroundedAt: backgroundedAt, now: now()
        )
        // A device with no credential cannot authenticate, so locking would be an unrecoverable
        // lockout — and there is no screen lock for a gate to add to. Stay unlocked.
        guard should, authenticator.capability().canAuthenticate else { return }
        lock()
    }

    private func lock() {
        guard !isLocked else { return }
        isLocked = true
        autoPromptPending = true
        onLockChanged(true)
    }

    private func unlockState() {
        autoPromptPending = false
        guard isLocked else { return }
        isLocked = false
        onLockChanged(false)
    }

    private func updateCover() {
        isCoverVisible = isEnabled && isSignedIn() && scenePhase != .active
    }

    // MARK: - Unlocking

    /// 010 §1.4 "It prompts automatically once when it appears" — once per lock, and only once the
    /// scene is active (an `evaluatePolicy` issued while inactive is dismissed by the system).
    public func autoPromptIfNeeded() async {
        guard isLocked, scenePhase == .active, autoPromptPending, !isAuthenticating else { return }
        autoPromptPending = false
        await unlock()
    }

    /// The Unlock button. Cancel or failure keeps the lock up and does nothing else.
    public func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        let result = await authenticator.authenticate(reason: "Unlock Findly")
        isAuthenticating = false
        if result == .success { unlockState() }
    }

    // MARK: - Setting

    /// 010 §1.4 "Enabling": switching ON requires one successful authentication (so it cannot be
    /// enabled into a lock the user cannot open); switching OFF needs none.
    public func setEnabled(_ enabled: Bool) async -> AppLockEnableResult {
        defer { objectWillChange.send() }  // lets a toggle that flipped optimistically snap back
        if !enabled {
            isEnabled = false
            store.isEnabled = false
            store.backgroundedAt = nil
            updateCover()
            return .disabled
        }
        guard authenticator.capability().canAuthenticate else { return .unavailable }
        guard await authenticator.authenticate(reason: "Turn on app lock") == .success else {
            return .authenticationFailed
        }
        isEnabled = true
        store.isEnabled = true
        return .enabled
    }

    // MARK: - End of session

    /// The app-lock part of the end-of-session local wipe (010 §1.4 last bullet): the setting and
    /// the background timestamp go, and a lock screen up for the previous user comes down.
    public func endSession() {
        store.clear()
        isEnabled = false
        isCoverVisible = false
        unlockState()
    }
}
