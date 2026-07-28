import Foundation

/// Adapts `BackgroundSyncScheduling` (the `BGTaskScheduler`-facing shape, specs/009 §3.4) to
/// `SyncScheduling` (the shape `DeviceSettingsCoordinator` composes with, specs/009 §3.5).
/// `syncIntervalMinutes` is deliberately **not** forwarded to `BGTaskScheduler` — iOS has no period
/// concept (§3.4: "the system decides actual frequency"); the interval is instead read live, fresh
/// from `DeviceSettingsStateStoring`, by `SyncTriggerPolicy.shouldCapture` on every trigger. What
/// `reschedule` actually needs to guarantee is "a `BGAppRefreshTask` request exists" — re-submitting
/// with the same identifier silently replaces any still-pending one (no error, per
/// `BGTaskScheduler`'s documented behavior), so this is a safe, idempotent no-op-if-redundant call.
private final class BackgroundSyncSchedulingAdapter: SyncScheduling {
    private let scheduler: BackgroundSyncScheduling
    init(scheduler: BackgroundSyncScheduling) { self.scheduler = scheduler }
    func reschedule(syncIntervalMinutes: Int) { scheduler.scheduleNextSync() }
}

/// The composition root for everything I10 builds (specs/009-device-runtime.md §1–§4, §9) — wires
/// the durable queue, the real `LocationProviding`/`BackgroundSyncScheduling` implementations, the
/// pure coordinators/policies, and the sync runner into one object with a small, app-target-facing
/// public surface. Lives in `FindlyKit` (not the app target) per specs/004 §1.1's rule: this is
/// composition/wiring, not UI.
///
/// **Constructed exactly once, in `FindlyApp.init()` — not in `RootView` (post-review
/// correction).** An earlier version of this doc argued `RootView` was an equally safe place to
/// build this, matching how it already constructs `FixQueue`/`exportArtifactStore`. That was
/// wrong: a standalone minimal SwiftUI reproduction confirmed `RootView.init()` reruns on every
/// `AppCoordinator.route` publish (`RootView` holds it via `@ObservedObject` while it's a
/// `@StateObject` in `FindlyApp`), i.e. on every in-app navigation — which would have silently
/// rebuilt this entire class (a live `CLLocationManager`, a fresh SQLite connection, a new
/// `FixQueue` actor) on every screen change. `App.init()`, unlike a child `View`'s init, IS
/// SwiftUI-guaranteed to run exactly once per process launch, so `FindlyApp` builds one instance
/// and passes it into `RootView` as a plain parameter.
@MainActor
public final class LocationRuntimeContainer {
    private let locationProvider: LocationProviding
    private let backgroundScheduler: BackgroundSyncScheduling
    private let stateStore: DeviceSettingsStateStoring
    private let captureCoordinator: FixCaptureCoordinator
    private let settingsCoordinator: DeviceSettingsCoordinator
    private let syncRunner: LocationSyncRunner
    private let pausedDevicePoller: PausedDevicePoller
    // I11 (specs/009-device-runtime.md §6.2) — the fetch/cache/full-replace-register sequence.
    // Held so `start()`/`onSignedIn()` (cold start, first sync after sign-in) and `onResume` below
    // (resume from pause) can all call through the same instance `LocationSyncRunner` also drains
    // the ETag-mismatch trigger through. `public` (I12 reconciliation): the app target's composition
    // root hands this SAME instance to `PushRuntimeContainer` so the `GEOFENCE_CONFIG_CHANGED` push
    // handler shares one source of truth with every other §6.2 registration trigger, rather than
    // each side owning an independent cache that could disagree — mirrors `settingsApplying` below.
    public let geofenceConfigSyncCoordinator: GeofenceConfigSyncCoordinator
    // Post-review addition (security review, High finding) — previously only ever a local `let`
    // inside `FindlyApp.init()`, with no path from anywhere in the sign-out flow able to reach it
    // at all. `wipeLocalState()` below needs it directly for the unregister-all half of the fix.
    private let geofenceRegistrar: GeofenceRegistering

    /// Consecutive-transient-failure counter for `BackoffPolicy` (specs/009 §9) — reset to 0 on
    /// any non-retry outcome. In-memory only: a process restart naturally resets backoff, which is
    /// fine (spec is silent on this surviving restart, unlike the batch identity in `FixStoring`).
    private var consecutiveTransientFailures = 0

    private static let defaultSyncIntervalMinutes = 15 // the server's own first-registration default (001 §4.1)

    public let fixQueue: FixQueue
    /// I11 (specs/009-device-runtime.md §6.3) — the durable geofence-event queue, exposed the same
    /// way `fixQueue` is: `DeleteAccountViewModel`'s local-state wipe needs a direct reference
    /// (specs/008-privacy-endpoints.md §4.4), same as `FixQueue`.
    public let geofenceEventQueue: GeofenceEventQueue
    /// I11 — the cached geofence config document + ETag, exposed for the same account-deletion
    /// local-wipe reason as `geofenceEventQueue` above.
    public let geofenceConfigStore: GeofenceConfigStateStoring
    /// I11 (specs/009-device-runtime.md §6.3) — the tested decision logic behind a region-
    /// monitoring enter/exit callback. Exposed so the app target can wire it into
    /// `SystemGeofenceRegistrar.transitionHandler` AFTER this container is constructed — mirrors
    /// how `fixQueue` is exposed as a plain property rather than threaded back out through a
    /// closure, since `SystemGeofenceRegistrar` (like `SystemLocationProvider`) is built OUTSIDE
    /// this container, in `FindlyApp.init()`.
    public let geofenceTransitionHandler: GeofenceTransitionHandler

    /// specs/009-device-runtime.md §5.2/§3.5 — the seam I12's `SETTINGS_CHANGED` push handler calls
    /// into (`DeviceSettingsCoordinator`'s own doc names this exactly: "I12's scope to wire the
    /// push arrival itself, but this is the seam it calls into"). Exposed read-only so the app
    /// target's composition root (`FindlyApp.init()`) can hand the SAME coordinator instance this
    /// container already built to `PushRuntimeContainer`, rather than constructing a second one.
    public var settingsApplying: DeviceSettingsApplying { settingsCoordinator }

    public init(
        apiClient: FindlyAPIClient,
        deviceId: @escaping () -> String?,
        locationProvider: LocationProviding = NoOpLocationProvider(),
        backgroundScheduler: BackgroundSyncScheduling = NoOpBackgroundSyncScheduler(),
        fixStore: FixStoring = InMemoryFixStore(),
        stateStore: DeviceSettingsStateStoring = InMemoryDeviceSettingsStateStore(),
        geofenceRegistrar: GeofenceRegistering = NoOpGeofenceRegistrar(),
        geofenceConfigStore: GeofenceConfigStateStoring = InMemoryGeofenceConfigStateStore(),
        geofenceEventStore: GeofenceEventQueueStoring = InMemoryGeofenceEventQueueStore(),
        lastQueuedFixAtStore: LastQueuedFixAtStoring = InMemoryLastQueuedFixAtStore(),
        isPermissionGranted: @escaping () -> Bool = { false },
        batteryLevelProvider: @escaping () -> Int = { 100 },
        onReRegisterDevice: @escaping () async -> Void = {},
        onSignedOut: @escaping () async -> Void = {}
    ) {
        self.locationProvider = locationProvider
        self.backgroundScheduler = backgroundScheduler
        self.stateStore = stateStore
        self.geofenceConfigStore = geofenceConfigStore
        self.geofenceRegistrar = geofenceRegistrar

        let queue = FixQueue(store: fixStore)
        self.fixQueue = queue

        let geofenceEventQueue = GeofenceEventQueue(store: geofenceEventStore)
        self.geofenceEventQueue = geofenceEventQueue

        let captureCoordinator = FixCaptureCoordinator(
            provider: locationProvider,
            queue: queue,
            isPaused: { stateStore.current()?.trackingEnabled == false },
            isPermissionGranted: isPermissionGranted
        )
        self.captureCoordinator = captureCoordinator

        self.geofenceTransitionHandler = GeofenceTransitionHandler(
            eventQueue: geofenceEventQueue,
            fixCaptureCoordinator: captureCoordinator,
            batteryLevelProvider: batteryLevelProvider,
            isPaused: { stateStore.current()?.trackingEnabled == false }
        )

        let geofenceConfigSyncCoordinator = GeofenceConfigSyncCoordinator(
            apiClient: apiClient, configStore: geofenceConfigStore, registrar: geofenceRegistrar
        )
        self.geofenceConfigSyncCoordinator = geofenceConfigSyncCoordinator

        let schedulingAdapter = BackgroundSyncSchedulingAdapter(scheduler: backgroundScheduler)
        let settingsCoordinator = DeviceSettingsCoordinator(
            scheduler: schedulingAdapter,
            geofenceRegistrar: geofenceRegistrar,
            stateStore: stateStore,
            onPause: {
                // specs/009 §4 "...and stop capturing" (post-review fix — previously nothing
                // stopped significant-location-change monitoring on pause). The BG task is
                // deliberately left alone; see `SyncScheduling`'s doc.
                locationProvider.stopBackgroundMonitoring()
            },
            onResume: {
                // specs/009 §4/§6.2: resume restores monitoring/scheduling AND is one of the five
                // geofence re-registration triggers (I11) — the OS may have already lost the
                // platform registrations while paused (a paused device unregisters all geofences,
                // §4), so resume must re-sync/re-register, not just restart location monitoring.
                locationProvider.startBackgroundMonitoring(coordinator: captureCoordinator)
                backgroundScheduler.scheduleNextSync()
                await geofenceConfigSyncCoordinator.sync()
            }
        )
        self.settingsCoordinator = settingsCoordinator

        let syncCoordinator = LocationSyncCoordinator(
            queue: queue, apiClient: apiClient, deviceId: deviceId,
            // specs/009 §4 (post-review fix): gate the flush client-side rather than relying
            // solely on the server's 403 — see LocationSyncCoordinator's doc.
            cachedSettings: { stateStore.current() }
        )

        let geofenceEventSyncCoordinator = GeofenceEventSyncCoordinator(
            queue: geofenceEventQueue, apiClient: apiClient, deviceId: deviceId,
            cachedSettings: { stateStore.current() }
        )

        self.syncRunner = LocationSyncRunner(
            currentSyncIntervalMinutes: { stateStore.current()?.syncIntervalMinutes ?? Self.defaultSyncIntervalMinutes },
            lastQueuedFixAtStore: lastQueuedFixAtStore,
            captureCoordinator: captureCoordinator,
            syncCoordinator: syncCoordinator,
            settingsApplying: settingsCoordinator,
            geofenceConfigSyncing: geofenceConfigSyncCoordinator,
            geofenceEventDraining: geofenceEventSyncCoordinator,
            onReRegisterDevice: onReRegisterDevice,
            onSignedOut: onSignedOut
        )

        self.pausedDevicePoller = PausedDevicePoller(apiClient: apiClient, deviceId: deviceId, settingsApplying: settingsCoordinator)
    }

    /// Call once at startup (after sign-in / whenever a `deviceId` becomes available). specs/009
    /// §4: "a low-frequency worker/BG task is the ONLY thing that keeps running while paused" —
    /// post-review fix: this method used to schedule NOTHING at all when starting up already
    /// paused (e.g. the app relaunching while a previously-applied pause is still in effect),
    /// which meant a device that never happened to be unpaused while the app was actually running
    /// could never self-heal via the pull-based resume path. Now it always arms the BG task; only
    /// significant-location-change monitoring is conditional on not being paused.
    public func start() {
        if stateStore.current()?.trackingEnabled != false {
            locationProvider.startBackgroundMonitoring(coordinator: captureCoordinator)
            backgroundScheduler.scheduleNextSync()
        } else {
            backgroundScheduler.scheduleNextSync(afterDelay: Self.pausedPollIntervalSeconds)
        }
    }

    /// specs/009 §6.2's "device reboot / app reinstall" registration trigger — both lose OS-level
    /// geofence registrations without changing anything server-side (unlike a plain reboot, which
    /// iOS actually DOES persist region monitoring across — see this method's callers' doc for why
    /// the safe, simple, idempotent choice is still "re-check/re-register on cold start regardless").
    /// Deliberately a **separate, explicit** method from `start()` — NOT auto-invoked from it —
    /// so `start()` stays a plain synchronous call with no fire-and-forget `Task` inside it (every
    /// existing `start()` test asserts its synchronous side effects immediately after calling it;
    /// spawning unawaited async work there would make those assertions race a background task that
    /// might still be mid-flight, or might fail hard against a test's `FakeAPIClient` that never
    /// anticipated a `getGeofences` call). The app target's cold-start path
    /// (`FindlyApp.init()`, the one place a process launch is unambiguous) calls this once,
    /// alongside `start()`, in its own `Task`.
    public func syncGeofenceConfigOnColdStart() async {
        if stateStore.current()?.trackingEnabled != false {
            await geofenceConfigSyncCoordinator.sync()
        }
    }

    /// specs/009 §6.2's "first config sync after sign-in" registration trigger. iOS has no
    /// `DeviceRegistrar.onRegistered`-shaped hook yet (Android's own trigger for this — a
    /// pre-existing gap this container's `onReRegisterDevice` doc already flags, not this task's to
    /// close) — the closest available, unambiguous "the user just signed in" signal is the
    /// sign-in flow's own completion callback, so the app target calls this from there
    /// (`RootView`'s `SignInViewModel(onSignedIn:)`). Kept separate from `syncGeofenceConfigOnColdStart()`
    /// because an in-app sign-out/sign-in cycle (e.g. `DeleteAccountViewModel.signOutForRetry()`
    /// followed by signing back in) never re-runs `FindlyApp.init()`, so the cold-start trigger
    /// alone would miss it.
    public func onSignedIn() async {
        if stateStore.current()?.trackingEnabled != false {
            await geofenceConfigSyncCoordinator.sync()
        }
    }

    /// specs/009 §4's pause teardown, the parts this container owns: stop significant-location-
    /// change monitoring and cancel the scheduled `BGAppRefreshTask`. Geofence unregistration and
    /// the settings-cache update itself are `DeviceSettingsCoordinator.applySettings`'s job — this
    /// method exists for a caller that wants to tear down monitoring without going through a
    /// settings change. **Not, on its own, what sign-out should call** — see `wipeLocalState()`
    /// below, which calls this AND clears every piece of local state I10/I11 persist; `stop()`
    /// alone leaves the fix queue, geofence-event queue, cached geofence config, and cached device
    /// settings all untouched.
    public func stop() {
        locationProvider.stopBackgroundMonitoring()
        backgroundScheduler.cancelScheduledSync()
    }

    /// **Post-review addition (security review, High finding).** The one consolidated "this device
    /// no longer belongs to a current session" wipe — covers everything I10+I11 persist locally.
    /// Previously, only account deletion's `DeleteAccountViewModel.wipeLocalStateAndComplete()`
    /// cleared any of this, and even that path never reached `geofenceRegistrar` (which had no
    /// path to it at all — it lived only as a local `let` inside `FindlyApp.init()`) or
    /// `stateStore`. Neither the forced-sign-out path (a second `AUTH_TOKEN_EXPIRED`, specs/009 §9)
    /// nor the sign-out-for-retry recovery flow (specs/008 §1.3) wiped anything — a real,
    /// deterministic bug, not a race: User A's cached `trackingEnabled: true` settings and
    /// registered `CLLocationManager` regions survive her sign-out untouched, so a geofence
    /// transition crossed in the window before a *different* trigger happens to re-sync gets
    /// durably queued and, if that queue is still non-empty once User B signs in on the same
    /// device, flushed under User B's `deviceId` — reporting a transition tagged with a
    /// `geofenceId` from a family User B has no relationship to. `GeofenceConfigSyncCoordinator`'s
    /// own network-failure fallback (`registerFromCache`) compounds this: if User B's very first
    /// sign-in sync happens to fail while offline, it would re-register User A's stale cached
    /// geofences under `CLLocationManager` — actively starting monitoring of a different family's
    /// home/school under the new session.
    ///
    /// MUST be called on every path that ends a session on this device — this container has no way
    /// to enforce that itself (it doesn't own sign-out), so every caller must be audited: as of
    /// this fix, `FindlyApp.swift`'s forced `onSignedOut` closure and
    /// `DeleteAccountViewModel.signOutForRetry()` (both previously did nothing local at all) now
    /// call this; `DeleteAccountViewModel.wipeLocalStateAndComplete()` (account deletion) now calls
    /// this too, via the same `wipeLocalState` closure injected into the view model, instead of
    /// its own previously-separate, now-removed ad-hoc partial wipe — one implementation, three
    /// call sites, not two independently-maintained ones.
    ///
    /// `stateStore.clear()` is the piece that makes a stray geofence transition — arriving either
    /// after this method returns, or **racing this method's own suspension points while it's still
    /// running** (`SystemGeofenceRegistrar.forwardTransition` delivers transitions via an
    /// unstructured `Task`, decoupled from this method's step order — see the concurrency note on
    /// the method body itself) — get dropped by `GeofenceTransitionHandler.isPaused`/
    /// `FixCaptureCoordinator.isPaused` rather than queued: see `DeviceSettingsStateStoring.clear()`'s
    /// doc for why that requires an explicit `trackingEnabled: false` write, not a bare "forget
    /// everything". This is why `clear()` runs as this method's **first** step, synchronously,
    /// before any `await`.
    ///
    /// Idempotent-safe to call more than once (every step it delegates to already is).
    public func wipeLocalState() async {
        // Post-review fix (concurrency re-review): `stateStore.clear()` MUST run FIRST, before
        // `stop()`/`unregisterAll()`/either `await` below — it's the step that actually makes
        // `FixCaptureCoordinator`/`GeofenceTransitionHandler`'s `isPaused()` gates read "paused".
        // `SystemGeofenceRegistrar.forwardTransition` delivers a transition via an unstructured
        // `Task { await transitionHandler?.handle(event) }`, decoupled from this method's own
        // isolation and step order — `handle()`'s `isPaused()` check is a fast, synchronous,
        // in-memory/UserDefaults read that can easily complete before this method's SQLite-backed
        // `fixQueue.clearAll()`/`geofenceEventQueue.clearAll()` awaits finish. With `clear()` run
        // FIRST (synchronously, before this method's own first suspension point), any transition
        // whose `isPaused()` check runs anytime after THIS method starts executing observes the
        // definite paused state immediately — the only remaining race is a callback whose
        // `isPaused()` check was already in flight *before* `wipeLocalState()` was even called,
        // which is the same non-atomicity specs/009 §6.2 already accepts as normal, not a new gap.
        // Previously this ran LAST, leaving a real (if narrow) window where a transition racing
        // this method's own suspension points could enqueue an event that survives the very
        // `clearAll()` call meant to remove it — see
        // `wipeLocalState_racingAConcurrentTransition_stillDropsIt` for the regression test.
        stateStore.clear()
        stop()
        geofenceRegistrar.unregisterAll()
        await fixQueue.clearAll()
        await geofenceEventQueue.clearAll()
        geofenceConfigStore.clear()
    }

    /// specs/009 §4: "at least every 6 hours" — the ONE explicit cadence number the spec gives for
    /// the paused-device poll, and (post-review fix) the bound this class actually enforces on the
    /// BG task's `earliestBeginDate` while paused. §3.4's "the system decides actual frequency"
    /// language governs the NON-paused case only — there is no equivalent numeric floor to honor
    /// there, so that path deliberately keeps requesting no explicit delay (`nil`, unchanged).
    private static let pausedPollIntervalSeconds: TimeInterval = 6 * 60 * 60

    /// The `BGAppRefreshTask` launch-handler body (specs/009 §3.4, trigger 1) — registered via
    /// `SystemBackgroundSyncScheduler.registerLaunchHandler` in the app target. Always reschedules
    /// before returning (§3.4: "rescheduled at the end of every run").
    ///
    /// **Post-review fix — this is the Blocking finding's core correctness property.** Previously
    /// this method ran `syncRunner.runOnce()` unconditionally and, on success, rescheduled with no
    /// explicit delay — but `DeviceSettingsCoordinator`'s `.pause` case used to cancel the BG task
    /// outright, so a paused device never got here again at all. Now the BG task is never
    /// canceled by pause (see `SyncScheduling`'s doc), and THIS method is what makes that survival
    /// meaningful: while paused, every firing does a `PausedDevicePoller.poll()` (specs/009 §4's
    /// pull-based resume check) instead of attempting a capture-and-sync cycle, and reschedules
    /// itself bounded to `pausedPollIntervalSeconds` — never leaving the device without a future
    /// check more than 6 hours out.
    public func handleBackgroundRefresh() async {
        if stateStore.current()?.trackingEnabled == false {
            _ = await pausedDevicePoller.poll()
            // The poll may have just observed trackingEnabled: true and, via
            // DeviceSettingsCoordinator's own `.resume` branch (onResume, wired in `init`), ALREADY
            // rescheduled immediately. Only apply the paused >=6h bound if STILL paused after the
            // poll, so a genuine resume isn't clobbered back onto a 6-hour wait.
            if stateStore.current()?.trackingEnabled == false {
                backgroundScheduler.scheduleNextSync(afterDelay: Self.pausedPollIntervalSeconds)
            }
            return
        }

        let result = await syncRunner.runOnce()
        switch result {
        case .success:
            consecutiveTransientFailures = 0
            backgroundScheduler.scheduleNextSync()
        case .retry:
            consecutiveTransientFailures += 1
            let interval = stateStore.current()?.syncIntervalMinutes ?? Self.defaultSyncIntervalMinutes
            let delay = BackoffPolicy.delay(forAttempt: consecutiveTransientFailures, syncIntervalMinutes: interval)
            backgroundScheduler.scheduleNextSync(afterDelay: delay)
        }
    }

    /// specs/009 §3.4 (trigger 3, foreground) + §4 (the paused-device poll's "every app
    /// foreground" requirement) + §7 (permission re-checked on every foreground — a natural
    /// consequence of `isPermissionGranted` being read fresh on every capture attempt, no extra
    /// code needed here). Call from the app target's scene-phase/`onAppear` observation.
    public func onAppForeground() async {
        _ = await pausedDevicePoller.poll()
        _ = await syncRunner.runOnce()
    }
}

/// A plain settable reference to the one `LocationRuntimeContainer` instance, `@MainActor`-isolated
/// to match it. Post-review narrowing: this used to also bridge Apple's "register before
/// `App.init` returns" requirement with the container not existing yet at that point — now that
/// `FindlyApp.init()` builds the container BEFORE calling
/// `SystemBackgroundSyncScheduler.registerLaunchHandler`, that handler captures it directly and no
/// longer needs this indirection. The one remaining reason this exists: a closure passed INTO
/// `LocationRuntimeContainer.init(...)` (its `onSignedOut` parameter) cannot reference the
/// `container` local variable that same init call is still in the middle of producing — reading it
/// back through this holder (populated a few lines after construction, but only ever read once a
/// real failure happens, long after) sidesteps that self-reference problem. Holds no logic.
@MainActor
public final class LocationRuntimeContainerHolder {
    public static let shared = LocationRuntimeContainerHolder()
    public var container: LocationRuntimeContainer?
    private init() {}
}
