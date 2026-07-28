import SwiftUI
import FindlyKit
import UIKit
import os

/// specs/004-ios-client.md §1.1 — the app target's App-lifecycle-wiring entry point.
///
/// **Post-review correction (Major finding #4): this is now the composition root, not `RootView`.**
/// `RootView` held `coordinator: AppCoordinator` via `@ObservedObject` while `AppCoordinator` is a
/// `@StateObject` *here* — a standalone minimal-reproduction of that exact pattern confirmed
/// `RootView.init()` reruns on every `coordinator.route` publish (i.e. on every in-app
/// navigation, including ones triggered from inside `RootView` itself), not once per launch.
/// Building `SQLiteFixStore`/`FixQueue`/`LocationRuntimeContainer` (a live `CLLocationManager`,
/// `BGTaskScheduler` submissions, a fresh SQLite connection) inside `RootView.init()` therefore
/// reconstructed the entire location-runtime stack on every navigation — falsifying this task's
/// own "the ONE and only `FixQueue` instance" invariant. `App.init()` (this type), unlike a child
/// `View`'s init, IS guaranteed by SwiftUI to run exactly once per process launch (already relied
/// on by the export-artifact cold-start cleanup below, pre-dating this fix) — so every object this
/// file constructs now lives here, exactly once, and is handed DOWN into `RootView` as plain
/// parameters instead of being built by it.
@main
@MainActor
struct FindlyApp: App {
    // specs/009-device-runtime.md §5 (I12) — bridges Firebase/APNs delegate callbacks and passes
    // OS-lifecycle push events into FindlyKit's `PushMessageDispatcher` (specs/004 §1.1's allowance:
    // "passing... push-registration callbacks... into FindlyKit types through their public
    // protocols"). Zero business logic lives in `AppDelegate` itself.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // specs/004-ios-client.md §8 — the one shared `AppConfig`, so `AppCoordinator` (deep-link host
    // matching) and `RootView` (share link/QR) agree on the same `joinLinkHost` (specs/007 §1).
    private let config: AppConfig
    @StateObject private var coordinator: AppCoordinator

    // The full object graph, built exactly once (see this type's top doc) and handed to
    // `RootView` as init parameters — `RootView` no longer constructs any of this itself.
    private let authProvider: AuthProviding
    private let apiClient: FindlyAPIClient
    private let deviceIdProvider: DeviceIdProviding
    private let exportArtifactStore: ExportArtifactStoring
    // specs/009-device-runtime.md (I10) — the real capture/sync engine. `fixQueue` is
    // `locationRuntimeContainer.fixQueue`, never a second, separately-constructed `FixQueue` — see
    // `LocationRuntimeContainer`'s doc for why two instances over the same on-disk file would
    // desync (the same class of bug specs/009 §2 exists to prevent one layer down).
    private let fixQueue: FixQueue
    private let locationRuntimeContainer: LocationRuntimeContainer
    // specs/009-device-runtime.md §5 (I12) — first-launch-after-sign-in / app-update device
    // re-registration plus push-notification registration, run once at cold launch (if already
    // signed in) and again from `RootView`'s sign-in completion (a session that begins signed OUT).
    // A plain closure (not a stored dependency) keeps `RootView`'s own parameter list from having
    // to grow by `DeviceRegistrationService` + `AppVersionRegistrationTracking` just to thread this
    // one call through.
    private let onSignedIn: () async -> Void

    init() {
        let config = AppConfig()
        self.config = config
        let coordinator = AppCoordinator(joinLinkHost: config.joinLinkHost)
        _coordinator = StateObject(wrappedValue: coordinator)

        // specs/008-privacy-endpoints.md §3.1 rule 2(b) — the one-shot cold-start cleanup: removes
        // any export artifact left behind by a previous process (e.g. killed mid-export, before
        // the next export's own defensive clear or the account-deletion wipe ever ran). `App.init`
        // is guaranteed by SwiftUI to run exactly once per process launch, so this is the one place
        // in the app target where "cold start" is unambiguous.
        FileManagerExportArtifactStore().removeCurrentArtifact()

        // specs/004-ios-client.md §4.1, §8 — AuthMode.stubLocal (default) matches the backend's
        // AUTH_MODE=insecure-local (specs/001 §2.3); AuthMode.firebase swaps in FirebaseAuthProvider,
        // the H1/H2 follow-up — a config change only, no further code change at this seam.
        let authProvider: AuthProviding
        switch config.authMode {
        case .stubLocal:
            authProvider = StubAuthProvider(firebaseProjectId: config.firebaseProjectId)
        case .firebase:
            authProvider = FirebaseAuthProvider()
        }
        self.authProvider = authProvider
        let apiClient = URLSessionAPIClient(baseURL: config.baseURL, authProvider: authProvider)
        self.apiClient = apiClient
        let deviceIdProvider = UserDefaultsDeviceIdProvider()
        self.deviceIdProvider = deviceIdProvider
        self.exportArtifactStore = FileManagerExportArtifactStore()

        // specs/009-device-runtime.md §2 — the durable, on-disk queue (I10). Falls back to
        // in-memory only if the on-disk file genuinely can't be opened (e.g. a full disk) — a
        // fix-queue that silently loses history is better than one that crashes app launch.
        let fixStoreURL = Self.fixStoreDatabaseURL()
        let fixStore: FixStoring
        if let store = try? SQLiteFixStore(url: fixStoreURL, onOverflowDropped: Self.logOverflowDrop) {
            fixStore = store
            // Post-review addition (security review, non-blocking but cheap): matches
            // `ExportArtifactStoring.swift`'s `FileManagerExportArtifactStore.write` precedent —
            // this file holds real pending fix coordinates, not just an ephemeral export artifact,
            // so it gets the same backup-exclusion + complete file protection. Best-effort
            // (`try?`): a failure here degrades to "protected by the OS default only", never to a
            // crash. Applied to the main file only — SQLite's WAL/SHM sidecar files are transient
            // (deleted/truncated in the common case) and not worth the added complexity of
            // tracking them here for a non-blocking hardening pass.
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: fixStoreURL.path)
            var mutableURL = fixStoreURL
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? mutableURL.setResourceValues(resourceValues)
        } else {
            fixStore = InMemoryFixStore(onOverflowDropped: Self.logOverflowDrop)
        }

        let deviceInfoProvider = SystemDeviceInfoProvider()
        let deviceRegistrationService = DeviceRegistrationService(
            apiClient: apiClient, deviceIdProvider: deviceIdProvider, deviceInfoProvider: deviceInfoProvider, authProvider: authProvider
        )
        let locationProvider = SystemLocationProvider()
        let deviceIdClosure: () -> String? = { [weak authProvider] in
            guard let uid = authProvider?.currentUserId else { return nil }
            return deviceIdProvider.deviceId(forUserId: uid)
        }

        let container = LocationRuntimeContainer(
            apiClient: apiClient,
            deviceId: deviceIdClosure,
            locationProvider: locationProvider,
            backgroundScheduler: SystemBackgroundSyncScheduler(),
            fixStore: fixStore,
            stateStore: UserDefaultsDeviceSettingsStateStore(),
            lastQueuedFixAtStore: UserDefaultsLastQueuedFixAtStore(),
            isPermissionGranted: { [weak locationProvider] in locationProvider?.isAuthorized ?? false },
            // specs/009 §9: 404 DEVICE_NOT_FOUND -> stop the schedule, clear local device state,
            // re-run registration. `onSignedIn` below (I12) now also explicitly registers on first
            // launch after sign-in and on every app update, per specs/004 §5's trigger list — this
            // remains the backstop for any registration `onSignedIn` missed or that failed silently.
            onReRegisterDevice: { [weak authProvider] in
                guard let uid = authProvider?.currentUserId else { return }
                deviceIdProvider.clearDeviceId(forUserId: uid)
                _ = try? await deviceRegistrationService.registerOrUpdate()
            },
            // specs/009 §9: a second AUTH_TOKEN_EXPIRED means signed-out - stop the runtime and
            // return to sign-in. Reads the container back through the holder (populated a few
            // lines below, but only ever CALLED once a real failure happens, long after that
            // assignment has run) rather than capturing `container` directly, which doesn't exist
            // yet at this point inside its own initializer argument list — the same self-reference
            // problem the holder was originally built to solve, now narrowed to just this one use.
            onSignedOut: { [weak authProvider, weak coordinator] in
                try? authProvider?.signOut()
                await LocationRuntimeContainerHolder.shared.container?.stop()
                await coordinator?.showSignIn()
            }
        )
        self.locationRuntimeContainer = container
        self.fixQueue = container.fixQueue
        LocationRuntimeContainerHolder.shared.container = container

        // specs/009-device-runtime.md §3.4 — Apple requires
        // `BGTaskScheduler.register(forTaskWithIdentifier:using:launchHandler:)` to run before
        // `App.init` returns. `container` is already fully built above (unlike before this fix,
        // when it didn't exist until `RootView.init()` ran, which could be arbitrarily later and
        // arbitrarily often) — the handler closure captures it directly, no holder indirection
        // needed for THIS purpose any more (the holder's only remaining job is the `onSignedOut`
        // self-reference above).
        SystemBackgroundSyncScheduler.registerLaunchHandler {
            await container.handleBackgroundRefresh()
        }

        container.start()

        // specs/009-device-runtime.md §5 (I12) — the push runtime: wires the four per-type
        // handlers into one dispatcher (`AppDelegate.didReceiveRemoteNotification` reaches it via
        // `PushRuntimeContainerHolder`), and connects the real FCM-backed `PushTokenProviding` to
        // `DeviceRegistrationService`'s existing (already-tested, I1) refresh-triggered
        // re-registration path — no call-site change needed there, exactly like Android's
        // `RealPushTokenProvider` swap-in.
        let pushRuntimeContainer = PushRuntimeContainer(
            apiClient: apiClient,
            locationProvider: locationProvider,
            deviceId: deviceIdClosure,
            settingsApplying: container.settingsApplying,
            geofenceEventNotifier: SystemGeofenceEventNotifier()
        )
        PushRuntimeContainerHolder.shared.container = pushRuntimeContainer
        deviceRegistrationService.observePushTokenRefreshes(FirebasePushTokenProvider.shared)

        // specs/004-ios-client.md §5's remaining two triggers (first launch after sign-in, every
        // app update) + specs/004 §1.1's "push-registration callbacks" allowance:
        // `UIApplication.registerForRemoteNotifications()` starts the APNs handshake that
        // eventually yields an FCM token via `FirebasePushTokenProvider`. Gated on already being
        // signed in so this is a no-op for a session that starts at the sign-in screen — `RootView`
        // calls this same closure again once `SignInViewModel` reports success.
        let appVersionTracker = UserDefaultsAppVersionRegistrationTracker()
        // A local `let`, not `self.onSignedIn` directly - capturing `self` in the `Task` closure
        // below would be an escaping-closure-captures-mutating-self error inside a struct's
        // `init()`. Assigned to the stored property immediately after, so both this cold-launch
        // call and `RootView`'s later interactive-sign-in call end up invoking the identical logic.
        let onSignedInClosure: () async -> Void = { [weak authProvider] in
            guard authProvider?.currentUserId != nil else { return }
            UIApplication.shared.registerForRemoteNotifications()
            await deviceRegistrationService.registerOnLaunchIfNeeded(appVersionTracker: appVersionTracker)
        }
        self.onSignedIn = onSignedInClosure
        Task { await onSignedInClosure() }
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                coordinator: coordinator,
                config: config,
                authProvider: authProvider,
                apiClient: apiClient,
                deviceIdProvider: deviceIdProvider,
                fixQueue: fixQueue,
                exportArtifactStore: exportArtifactStore,
                locationRuntimeContainer: locationRuntimeContainer,
                onSignedIn: onSignedIn
            )
                // specs/004-ios-client.md §3.4/§3.5 — both the `findly://group-join?code=…` deep
                // link and, since specs/007, the `https://{joinLinkHost}/g#CODE` universal link are
                // parsed/validated in FindlyKit (AppCoordinator.handleDeepLink, backed by the pure
                // GroupCodeParsing); this is just the OS-lifecycle forwarding, the one piece of
                // "logic" the app target is allowed (specs/004 §1.1).
                .onOpenURL { url in coordinator.handleDeepLink(url) }
        }
    }

    /// specs/009-device-runtime.md §2 / docs/security-review-checklist.md — the fix-queue's
    /// 1 000-cap overflow log line: a **count only**, never coordinates/fixId/deviceId. `.debug`
    /// level matches the spec's "logged at debug level" wording exactly.
    private static let fixQueueLog = Logger(subsystem: "com.findly.ios", category: "FixQueue")
    private static func logOverflowDrop(_ droppedCount: Int) {
        fixQueueLog.debug("1000-fix cap reached, dropped \(droppedCount, privacy: .public) oldest fix(es)")
    }

    /// specs/009-device-runtime.md §2 — the durable fix-queue's on-disk location: app-private
    /// Application Support storage (never Documents, which is user-visible/exportable via Files.app
    /// — this is raw location history, not a user-facing document), created on first use.
    private static func fixStoreDatabaseURL() -> URL {
        let fileManager = FileManager.default
        let directory = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fileManager.temporaryDirectory
        return directory.appendingPathComponent("findly-fixqueue.sqlite")
    }
}
