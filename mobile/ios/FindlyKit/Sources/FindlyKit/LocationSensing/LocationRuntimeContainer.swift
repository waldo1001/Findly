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
    func cancelAll() { scheduler.cancelScheduledSync() }
}

/// The composition root for everything I10 builds (specs/009-device-runtime.md §1–§4, §9) — wires
/// the durable queue, the real `LocationProviding`/`BackgroundSyncScheduling` implementations, the
/// pure coordinators/policies, and the sync runner into one object with a small, app-target-facing
/// public surface. Lives in `FindlyKit` (not the app target) per specs/004 §1.1's rule: this is
/// composition/wiring, not UI, and keeping it here is what lets `RootView` construct one instance
/// the same way it already constructs `FixQueue`/`exportArtifactStore` today.
///
/// **Why the app target still needs `LocationRuntimeContainerHolder` alongside this class**: Apple
/// requires `BGTaskScheduler.register(forTaskWithIdentifier:using:launchHandler:)` to run before
/// `App.init()` returns (`SystemBackgroundSyncScheduler.registerLaunchHandler`'s doc) — long before
/// `RootView` has constructed the API client/auth provider this container needs. The launch
/// handler closure itself, however, only actually *runs* later (when the system fires the task),
/// by which point `RootView.init()` has always already executed at least once — SwiftUI builds the
/// view hierarchy on every launch, including one the system woke up in the background, so the
/// handler can safely resolve its container lazily through the holder rather than needing it at
/// registration time. `FindlyApp.swift` registers; `RootView` constructs the real container and
/// publishes it to the holder; nothing about this requires app-target business logic beyond that
/// one assignment.
@MainActor
public final class LocationRuntimeContainer {
    private let locationProvider: LocationProviding
    private let backgroundScheduler: BackgroundSyncScheduling
    private let stateStore: DeviceSettingsStateStoring
    private let captureCoordinator: FixCaptureCoordinator
    private let settingsCoordinator: DeviceSettingsCoordinator
    private let syncRunner: LocationSyncRunner
    private let pausedDevicePoller: PausedDevicePoller

    /// Consecutive-transient-failure counter for `BackoffPolicy` (specs/009 §9) — reset to 0 on
    /// any non-retry outcome. In-memory only: a process restart naturally resets backoff, which is
    /// fine (spec is silent on this surviving restart, unlike the batch identity in `FixStoring`).
    private var consecutiveTransientFailures = 0

    private static let defaultSyncIntervalMinutes = 15 // the server's own first-registration default (001 §4.1)

    public let fixQueue: FixQueue

    public init(
        apiClient: FindlyAPIClient,
        deviceId: @escaping () -> String?,
        locationProvider: LocationProviding = NoOpLocationProvider(),
        backgroundScheduler: BackgroundSyncScheduling = NoOpBackgroundSyncScheduler(),
        fixStore: FixStoring = InMemoryFixStore(),
        stateStore: DeviceSettingsStateStoring = InMemoryDeviceSettingsStateStore(),
        geofenceRegistrar: GeofenceRegistrarStub = NoOpGeofenceRegistrarStub(),
        lastQueuedFixAtStore: LastQueuedFixAtStoring = InMemoryLastQueuedFixAtStore(),
        isPermissionGranted: @escaping () -> Bool = { false },
        onReRegisterDevice: @escaping () async -> Void = {},
        onSignedOut: @escaping () async -> Void = {}
    ) {
        self.locationProvider = locationProvider
        self.backgroundScheduler = backgroundScheduler
        self.stateStore = stateStore

        let queue = FixQueue(store: fixStore)
        self.fixQueue = queue

        let captureCoordinator = FixCaptureCoordinator(
            provider: locationProvider,
            queue: queue,
            isPaused: { stateStore.current()?.trackingEnabled == false },
            isPermissionGranted: isPermissionGranted
        )
        self.captureCoordinator = captureCoordinator

        let schedulingAdapter = BackgroundSyncSchedulingAdapter(scheduler: backgroundScheduler)
        let settingsCoordinator = DeviceSettingsCoordinator(
            scheduler: schedulingAdapter,
            geofenceRegistrar: geofenceRegistrar,
            stateStore: stateStore,
            onResume: {
                // specs/009 §4: resume restores monitoring/scheduling. Geofence re-registration is
                // I11's scope (geofenceRegistrar above is a no-op stub until then).
                locationProvider.startBackgroundMonitoring(coordinator: captureCoordinator)
                backgroundScheduler.scheduleNextSync()
            }
        )
        self.settingsCoordinator = settingsCoordinator

        let syncCoordinator = LocationSyncCoordinator(queue: queue, apiClient: apiClient, deviceId: deviceId)

        self.syncRunner = LocationSyncRunner(
            currentSyncIntervalMinutes: { stateStore.current()?.syncIntervalMinutes ?? Self.defaultSyncIntervalMinutes },
            lastQueuedFixAtStore: lastQueuedFixAtStore,
            captureCoordinator: captureCoordinator,
            syncCoordinator: syncCoordinator,
            settingsApplying: settingsCoordinator,
            onReRegisterDevice: onReRegisterDevice,
            onSignedOut: onSignedOut
        )

        self.pausedDevicePoller = PausedDevicePoller(apiClient: apiClient, deviceId: deviceId, settingsApplying: settingsCoordinator)
    }

    /// Call once at startup (after sign-in / whenever a `deviceId` becomes available) — arms
    /// significant-location-change monitoring (unless currently paused) and submits the first
    /// `BGAppRefreshTask` request. Safe to call even while paused (starts nothing in that case,
    /// same as `DeviceSettingsCoordinator`'s own pause handling).
    public func start() {
        if stateStore.current()?.trackingEnabled != false {
            locationProvider.startBackgroundMonitoring(coordinator: captureCoordinator)
            backgroundScheduler.scheduleNextSync()
        }
    }

    /// specs/009 §4's pause teardown, the parts this container owns: stop significant-location-
    /// change monitoring and cancel the scheduled `BGAppRefreshTask`. Geofence unregistration and
    /// the settings-cache update itself are `DeviceSettingsCoordinator.applySettings`'s job — this
    /// method exists for a caller that wants to tear down without going through a settings change
    /// (e.g. sign-out).
    public func stop() {
        locationProvider.stopBackgroundMonitoring()
        backgroundScheduler.cancelScheduledSync()
    }

    /// The `BGAppRefreshTask` launch-handler body (specs/009 §3.4, trigger 1) — registered via
    /// `SystemBackgroundSyncScheduler.registerLaunchHandler` in the app target, resolved lazily
    /// through `LocationRuntimeContainerHolder` (see this class's top doc). Always reschedules
    /// before returning (§3.4: "rescheduled at the end of every run"): a plain re-submit on
    /// success, a `BackoffPolicy`-delayed one on a transient failure (§9).
    public func handleBackgroundRefresh() async {
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

/// Bridges Apple's "register before `App.init` returns" requirement with the reality that
/// `LocationRuntimeContainer`'s dependency graph doesn't exist yet at that point — see
/// `LocationRuntimeContainer`'s top doc for the full rationale. Holds no logic: a plain settable
/// reference, `@MainActor`-isolated to match the container it holds.
@MainActor
public final class LocationRuntimeContainerHolder {
    public static let shared = LocationRuntimeContainerHolder()
    public var container: LocationRuntimeContainer?
    private init() {}
}
