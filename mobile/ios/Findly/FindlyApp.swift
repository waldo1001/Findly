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
    // specs/008-privacy-endpoints.md §1.3, specs/004-ios-client.md §3.6 (I25) — the SAME instance
    // handed to `DeviceRegistrationService` below; also threaded down into `RootView` so
    // `DeleteAccountViewModel`'s local wipe can clear it, the same way it already clears
    // `deviceIdProvider`.
    private let appVersionTracker: AppVersionRegistrationTracking
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
    // specs/010-app-shell-and-screen-ux.md §1.2 — the ONE shared instance the drawer header reads
    // (family name + caller display name, "cached from the launch probe"); populated by
    // `AppLaunchResolver` (cold start / interactive sign-in) and refreshed opportunistically by
    // `FamilyMembersViewModel`/bootstrap successes. Built once here, like everything else in this
    // file, and handed down as a plain `@StateObject` in `RootView`.
    //
    // Assigned via `_familyContextCache = StateObject(wrappedValue:)` from a local `let` in
    // `init()` below (same pattern as `coordinator`), rather than a bare `= FamilyContextCache()`
    // default — `LocationRuntimeContainer`'s init (also built inside `init()`, for its
    // `wipeLocalState()` review fix, specs/010 §1.2) needs the SAME instance, and reading
    // `self.familyContextCache` this early — before `body`/`WindowGroup` ever runs — is not a
    // reliable way to reach a `@StateObject`'s real, SwiftUI-installed storage.
    @StateObject private var familyContextCache: FamilyContextCache

    init() {
        // specs/004 §8 — real deployment values come from this target's Info.plist (iOS's
        // counterpart to Android's BuildConfig fields). Previously this was a bare `AppConfig()`,
        // which shipped the `.invalid` placeholder base URL and `authMode == .stubLocal`: the app
        // could not reach func-findly, and phone sign-in was faked by StubAuthProvider instead of
        // going through Firebase. Found on the first real TestFlight install, 2026-08-05.
        let config = AppConfig(infoDictionary: Bundle.main.infoDictionary)
        self.config = config

        // specs/004-ios-client.md §4.1, §8 — AuthMode.stubLocal (default) matches the backend's
        // AUTH_MODE=insecure-local (specs/001 §2.3); AuthMode.firebase swaps in FirebaseAuthProvider,
        // the H1/H2 follow-up — a config change only, no further code change at this seam.
        //
        // Built BEFORE the coordinator as of specs/004 §2.6: the launch route is derived from this
        // provider's restored session, so it has to exist first.
        let authProvider: AuthProviding
        switch config.authMode {
        case .stubLocal:
            authProvider = StubAuthProvider(firebaseProjectId: config.firebaseProjectId)
        case .firebase:
            // I33 — Firebase is deliberately NOT configured here. `App.init()` runs before
            // `UIApplicationMain` establishes `UIApplication.shared` and its delegate, so calling
            // `FirebaseApp.configure()` this early makes Firebase's method-swizzler install its
            // remote-notification interceptor against a not-yet-existent delegate. That interceptor
            // never fires, so Firebase's phone-auth notification-forwarding self-check always failed
            // with `FIRAuthErrorDomain 17054` on device — regardless of the swizzling toggle.
            // Configuration now happens only in `AppDelegate.didFinishLaunchingWithOptions`, where
            // the delegate is guaranteed live. Constructing `FirebaseAuthProvider()` is safe
            // unconfigured — it touches only the Keychain, never `Auth.auth()` — and the launch-route
            // read of `currentUserId` already lives in `RootView`'s `.task`, which runs strictly
            // after `didFinishLaunchingWithOptions`.
            authProvider = FirebaseAuthProvider()
        }
        self.authProvider = authProvider

        // specs/004-ios-client.md §2.6 — starts at `.launching` and is resolved by `RootView`'s
        // `.task`, NOT here.
        //
        // The first version of this read `authProvider.currentUserId` right here to pick the
        // route. That constructs `Auth.auth()` before `UIApplicationMain` has `UIApplication.shared`
        // up, and Firebase's `protectedDataInitialization` obtains UIApplication *by reflection* —
        // when that lookup fails it returns early without assigning `tokenManager`, which is an
        // implicitly-unwrapped optional and therefore stays nil for the entire process. The first
        // APNs callback then trapped in `Auth.setAPNSToken`. Build 5 crashed ~0.5s after launch
        // this way, via `AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken`.
        //
        // So: nothing in this initializer may touch `FirebaseAuth`. `configureFirebaseIfNeeded()`
        // above is fine — it touches `FirebaseApp` only and constructs no `Auth`.
        let coordinator = AppCoordinator(joinLinkHost: config.joinLinkHost)
        _coordinator = StateObject(wrappedValue: coordinator)

        // specs/010-app-shell-and-screen-ux.md §1.2 — declared as a local here (same reasoning as
        // `coordinator` above) so `LocationRuntimeContainer`'s init below can be handed the SAME
        // instance for its `wipeLocalState()` review fix.
        let familyContextCache = FamilyContextCache()
        _familyContextCache = StateObject(wrappedValue: familyContextCache)

        // specs/008-privacy-endpoints.md §3.1 rule 2(b) — the one-shot cold-start cleanup: removes
        // any export artifact left behind by a previous process (e.g. killed mid-export, before
        // the next export's own defensive clear or the account-deletion wipe ever ran). `App.init`
        // is guaranteed by SwiftUI to run exactly once per process launch, so this is the one place
        // in the app target where "cold start" is unambiguous.
        FileManagerExportArtifactStore().removeCurrentArtifact()

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

        // specs/009-device-runtime.md §6.3 (I11) — the durable geofence-event queue, same fallback/
        // hardening posture as fixStore above (a non-durable in-memory store beats crashing app
        // launch on e.g. a full disk).
        let geofenceEventStoreURL = Self.geofenceEventStoreDatabaseURL()
        let geofenceEventStore: GeofenceEventQueueStoring
        if let store = try? SQLiteGeofenceEventQueueStore(url: geofenceEventStoreURL) {
            geofenceEventStore = store
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: geofenceEventStoreURL.path)
            var mutableURL = geofenceEventStoreURL
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? mutableURL.setResourceValues(resourceValues)
        } else {
            geofenceEventStore = InMemoryGeofenceEventQueueStore()
        }

        let deviceInfoProvider = SystemDeviceInfoProvider()
        // specs/004-ios-client.md §5 (I24 review, Finding 2) — moved up from further below so it
        // can be handed to `DeviceRegistrationService` itself: `registerOrUpdate()` now consults it
        // to decide whether a profile-probe round trip is worth making at all (see that method's
        // doc), not just to record "first launch after sign-in"/"every app update".
        let appVersionTracker = UserDefaultsAppVersionRegistrationTracker()
        self.appVersionTracker = appVersionTracker
        let deviceRegistrationService = DeviceRegistrationService(
            apiClient: apiClient, deviceIdProvider: deviceIdProvider, deviceInfoProvider: deviceInfoProvider,
            authProvider: authProvider, appVersionTracker: appVersionTracker
        )
        let locationProvider = SystemLocationProvider()
        // specs/009-device-runtime.md §6.2 (I11) — the real, CLLocationManager-region-monitoring-
        // backed registrar. Built here (like `locationProvider` above), BEFORE
        // `LocationRuntimeContainer` exists, because `LocationRuntimeContainer.init` needs it as an
        // init parameter — its `transitionHandler` is wired the same way
        // `locationProvider`/`captureCoordinator` are (a settable reference, populated once the
        // container's own object graph exists, see the assignment right after `container` below).
        let geofenceRegistrar = SystemGeofenceRegistrar()
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
            geofenceRegistrar: geofenceRegistrar,
            geofenceConfigStore: UserDefaultsGeofenceConfigStateStore(),
            geofenceEventStore: geofenceEventStore,
            lastQueuedFixAtStore: UserDefaultsLastQueuedFixAtStore(),
            // specs/009-device-runtime.md §7 (I31) — the one, real, `UserDefaults`-backed instance.
            // `RootView` reads this SAME instance back (`locationRuntimeContainer.
            // permissionDisclosureStore`) for its `PermissionFlowViewModel`, instead of
            // constructing a second, disconnected store the way it used to (the I26 pattern this
            // task fixes) — see `LocationRuntimeContainer.wipeLocalState()`'s doc for why sharing
            // one instance is what makes the account-deletion wipe's clear() a live call.
            permissionDisclosureStore: UserDefaultsPermissionDisclosureStore(),
            // specs/010-app-shell-and-screen-ux.md §1.2 (I34 review fix) — the SAME instance
            // handed to `RootView`/`LiveMapScreen` below, so `wipeLocalState()` is this cache's
            // real, live-called `clear()` caller on every sign-out/account-deletion path, exactly
            // like `permissionDisclosureStore` immediately above (the identical I26/I31 shape).
            familyContextCache: familyContextCache,
            isPermissionGranted: { [weak locationProvider] in locationProvider?.isAuthorized ?? false },
            // specs/009 §9: 404 DEVICE_NOT_FOUND -> stop the schedule, clear local device state,
            // re-run registration. `onSignedIn` below (I12) now also explicitly registers on first
            // launch after sign-in and on every app update, per specs/004 §5's trigger list — this
            // remains the backstop for any registration `onSignedIn` missed or that failed silently.
            //
            // I24 fix: this call goes to `registerOrUpdate()` DIRECTLY rather than through one of
            // `DeviceRegistrationService`'s own best-effort wrappers (`registerOnLaunchIfNeeded`,
            // `observePushTokenRefreshes`) — its doc comment's own convention is that such direct
            // callers "need failure visibility", so a bare `try?` here was defeating that by
            // discarding the very error it was written to expose. Anything but
            // `.profileNotYetBootstrapped` is a genuine failure, now logged (via the curated,
            // log-safe `loggableSummary(forDeviceRegistrationFailure:)` — never the raw `Error`,
            // whose `message`/`details` text is only safe today by backend convention, not by
            // anything enforced at this call site) instead of vanishing.
            //
            // I24 review (Finding 4) — `.profileNotYetBootstrapped` here does NOT mean "hasn't
            // onboarded yet": `onReRegisterDevice` only fires on a `404 DEVICE_NOT_FOUND` for a
            // device that WAS registered, which proves a profile existed at that point. Reaching
            // this case means the profile was deleted out from under this in-flight session — e.g.
            // a concurrent `DELETE /users/me` from another device — between then and now. Silence
            // remains correct: there is nothing to retry once the account itself is gone (no
            // RootView bootstrap callback will ever fire for this session either).
            onReRegisterDevice: { [weak authProvider] in
                guard let uid = authProvider?.currentUserId else { return }
                deviceIdProvider.clearDeviceId(forUserId: uid)
                do {
                    _ = try await deviceRegistrationService.registerOrUpdate()
                } catch DeviceRegistrationError.profileNotYetBootstrapped {
                    // Expected — see this closure's top doc (I24 review, Finding 4).
                } catch {
                    Self.deviceRegistrationLog.error("device re-registration after DEVICE_NOT_FOUND failed: \(loggableSummary(forDeviceRegistrationFailure: error), privacy: .public)")
                }
            },
            // specs/009 §9: a second AUTH_TOKEN_EXPIRED means signed-out - wipe local state and
            // return to sign-in. Reads the container back through the holder (populated a few
            // lines below, but only ever CALLED once a real failure happens, long after that
            // assignment has run) rather than capturing `container` directly, which doesn't exist
            // yet at this point inside its own initializer argument list — the same self-reference
            // problem the holder was originally built to solve, now narrowed to just this one use.
            //
            // Post-review fix (security review, High finding): previously called `.stop()`, which
            // only halts monitoring/cancels the BG task — it left every piece of I10/I11 local
            // state (fix queue, geofence-event queue, cached geofence config/ETag, cached device
            // settings, registered CLLocationManager geofences) untouched across a forced sign-out,
            // a real, deterministic cross-account data leak (see `wipeLocalState()`'s doc). Now
            // calls the consolidated `wipeLocalState()` (which itself calls `stop()`), the same
            // method `DeleteAccountViewModel`'s two sign-out-shaped paths use.
            onSignedOut: { [weak authProvider, weak coordinator] in
                try? authProvider?.signOut()
                await LocationRuntimeContainerHolder.shared.container?.wipeLocalState()
                await coordinator?.showSignIn()
            }
        )
        self.locationRuntimeContainer = container
        self.fixQueue = container.fixQueue
        LocationRuntimeContainerHolder.shared.container = container

        // specs/009-device-runtime.md §6.3 (I11) — `geofenceRegistrar` was built above, before the
        // container (and therefore `GeofenceTransitionHandler`) existed; wire it now, the same
        // "settable reference populated post-construction" pattern `SystemLocationProvider`/
        // `captureCoordinator` already established (see `container.start()`'s internal wiring).
        geofenceRegistrar.transitionHandler = container.geofenceTransitionHandler

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

        // specs/009-device-runtime.md §6.2 (I11) — "device reboot / app reinstall" (both lose
        // OS-level geofence registrations without changing anything server-side) is covered by
        // re-checking/re-registering on every cold start if `trackingEnabled`, matching Android
        // A11's own reasoning. `FindlyApp.init()` is the one unambiguous "cold start" hook (runs
        // exactly once per process launch) — deliberately a separate `Task` from `container.start()`
        // itself rather than folded into it, so `start()` stays a plain synchronous call with no
        // async work racing its own synchronous side effects (see `syncGeofenceConfigOnColdStart`'s
        // doc for the full rationale).
        Task { await container.syncGeofenceConfigOnColdStart() }

        // specs/009-device-runtime.md §5 (I12) — the push runtime: wires the four per-type
        // handlers into one dispatcher (`AppDelegate.didReceiveRemoteNotification` reaches it via
        // `PushRuntimeContainerHolder`), and connects the real FCM-backed `PushTokenProviding` to
        // `DeviceRegistrationService`'s existing (already-tested, I1) refresh-triggered
        // re-registration path — no call-site change needed there, exactly like Android's
        // `RealPushTokenProvider` swap-in.
        //
        // Reconciliation with I11 (post-merge fix): `GEOFENCE_CONFIG_CHANGED`'s handler now shares
        // `container.geofenceConfigSyncCoordinator` — the SAME instance `LocationRuntimeContainer`
        // already built and drains through every other §6.2 trigger — instead of constructing a
        // second, independent one. Two instances would each own their own `GeofenceConfigStateStoring`
        // read/write of the SAME `UserDefaults` keys and could race/disagree about the cached ETag,
        // defeating the "single source of truth" §6.1 requires; sharing one instance mirrors exactly
        // how `settingsApplying` above is already shared between the location and push sides.
        let pushRuntimeContainer = PushRuntimeContainer(
            apiClient: apiClient,
            locationProvider: locationProvider,
            deviceId: deviceIdClosure,
            settingsApplying: container.settingsApplying,
            geofenceConfigSyncCoordinator: container.geofenceConfigSyncCoordinator,
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
        //
        // `appVersionTracker` itself now lives above, handed to `DeviceRegistrationService.init`
        // (I24 review, Finding 2) — `registerOnLaunchIfNeeded()` reads it internally.
        //
        // A local `let`, not `self.onSignedIn` directly - capturing `self` in the `Task` closure
        // below would be an escaping-closure-captures-mutating-self error inside a struct's
        // `init()`. Assigned to the stored property immediately after, so both this cold-launch
        // call and `RootView`'s later interactive-sign-in call end up invoking the identical logic.
        let onSignedInClosure: () async -> Void = { [weak authProvider] in
            guard authProvider?.currentUserId != nil else { return }
            UIApplication.shared.registerForRemoteNotifications()
            await deviceRegistrationService.registerOnLaunchIfNeeded()
        }
        self.onSignedIn = onSignedInClosure
        // specs/004 §2.6: NOT fired from here any more. This closure reads `currentUserId`, i.e.
        // constructs `Auth.auth()` — and a `Task` spawned in `App.init()` can run before
        // `UIApplication.shared` exists, which is exactly the sequence that left Firebase's
        // `tokenManager` nil and crashed build 5 on the first APNs callback. `RootView`'s `.task`
        // now runs it, right after resolving the launch route, where the UI is guaranteed up.
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                coordinator: coordinator,
                config: config,
                authProvider: authProvider,
                apiClient: apiClient,
                deviceIdProvider: deviceIdProvider,
                exportArtifactStore: exportArtifactStore,
                appVersionTracker: appVersionTracker,
                locationRuntimeContainer: locationRuntimeContainer,
                onSignedIn: onSignedIn,
                familyContextCache: familyContextCache
            )
                // specs/004-ios-client.md §3.4/§3.5 — both the `findly://group-join?code=…` deep
                // link and, since specs/007, the `https://{joinLinkHost}/g#CODE` universal link are
                // parsed/validated in FindlyKit (AppCoordinator.handleDeepLink, backed by the pure
                // GroupCodeParsing); this is just the OS-lifecycle forwarding, the one piece of
                // "logic" the app target is allowed (specs/004 §1.1).
                //
                // I32 (specs/004 §4.1) — Auth gets first refusal. The reCAPTCHA web-sheet fallback
                // returns via the `app-1-…` REVERSED_CLIENT_ID scheme; `Auth.canHandle(url)` claims
                // that one and resumes verification itself. Everything else (the app's own
                // findly://.../https://{joinLinkHost} links) falls through unclaimed to the
                // coordinator exactly as before.
                .onOpenURL { url in
                    guard !FirebaseAuthProvider.canHandle(url) else { return }
                    coordinator.handleDeepLink(url)
                }
        }
    }

    /// I24 — makes a genuine device re-registration failure observable (see `onReRegisterDevice`
    /// above) instead of the bare `try?` that used to discard it silently. `docs/security-review-
    /// checklist.md`: the logged value is always `loggableSummary(forDeviceRegistrationFailure:)`'s
    /// curated `code`/`httpStatus`/`requestId` projection (I24 review, security Minor) — never the
    /// raw `Error`, and never device/user IDs, tokens, or coordinates.
    private static let deviceRegistrationLog = Logger(subsystem: "com.findly.ios", category: "DeviceRegistration")

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

    /// specs/009-device-runtime.md §6.3 (I11) — the durable geofence-event queue's on-disk
    /// location. Same app-private Application Support directory as `fixStoreDatabaseURL()` above,
    /// a separate file (never Documents — this is raw geofence-transition history, not a
    /// user-visible document).
    private static func geofenceEventStoreDatabaseURL() -> URL {
        let fileManager = FileManager.default
        let directory = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fileManager.temporaryDirectory
        return directory.appendingPathComponent("findly-geofenceevents.sqlite")
    }
}
