import Foundation

/// `LocationSyncRunner.runOnce`'s result — thin enough for `SystemBackgroundSyncScheduler`'s
/// `BGAppRefreshTask` launch handler to map straight onto `task.setTaskCompleted(success:)`, and
/// for a future retry-scheduling caller to apply `BackoffPolicy` on `.retry`.
public enum RunResult: Equatable {
    case success
    case retry
}

/// specs/009-device-runtime.md §1 (pipeline) + §3.4 (the 0.8-elapsed-time trigger rule) +
/// §9 (error-handling reactions) — one opportunistic-trigger cycle. All three of iOS's triggers
/// (`BGAppRefreshTask`, significant-location-change already captured via `FixCaptureCoordinator`'s
/// own hint path, foreground) call through this single `runOnce()` — deliberately **pure Swift,
/// zero CoreLocation/BackgroundTasks imports**, so this is where "what does a sync run do" lives
/// and is unit-tested; `LocationRuntimeContainer`'s `BGAppRefreshTask` handler is a thin caller of
/// the exact same `runOnce()`. Mirrors Android's `LocationSyncRunner`.
///
/// Order per run: (1) maybe capture one `source: .periodic` fix, gated by `SyncTriggerPolicy`'s
/// 0.8 rule (skipped silently if under threshold — the already-queued backlog, if any, still gets
/// drained); (2) drain the fix queue via `syncCoordinator`; (3) drain the geofence-event queue via
/// `geofenceEventDraining` (I11 addition, specs/009 §6.3: "Events are flushed like fixes... on the
/// same cadence" — the natural fit found by piggybacking onto this same per-cycle drain rather than
/// a second independent scheduler). Both drains apply the mandatory `deviceSettings` piggyback on
/// every `.synced` outcome (specs/001 §5.1/§7.3, specs/009 §1) and re-sync the geofence config via
/// `geofenceConfigSyncing` when the piggybacked `geofenceEtag` differs from the cached one (§6.2/
/// §6.3's ETag-mismatch self-heal) — without stopping the run, more of either queue may remain.
/// Only a `.transientFailure` on the FIX queue backs off the whole run early (no point hammering
/// the geofence-event endpoint too in the same cycle; the next run retries both) — a transient
/// failure draining the EVENT queue stops just that half. `.rejected`/`.otherFailure` keep draining
/// (more of the queue may remain after an unmappable rejection un-freezes it for retry).
public final class LocationSyncRunner {
    private let currentSyncIntervalMinutes: () -> Int
    private let lastQueuedFixAtStore: LastQueuedFixAtStoring
    private let now: () -> Date
    private let captureCoordinator: FixCaptureCoordinator
    private let syncCoordinator: LocationSyncCoordinator
    private let settingsApplying: DeviceSettingsApplying
    private let geofenceConfigSyncing: GeofenceConfigSyncing
    private let geofenceEventDraining: GeofenceEventDraining
    private let onReRegisterDevice: () async -> Void
    private let onSignedOut: () async -> Void

    /// Defensively bounded (specs/009 §3.1's "MUST complete in well under 10 minutes" applies to
    /// Android's WorkManager path, but the same discipline is cheap insurance here too) - a
    /// pathologically large backlog is picked up again next run rather than looping forever.
    /// 20 * 100 = 2 000 fixes/run, well above the 1 000-fix cap (specs/009 §2).
    private static let maxBatchesPerRun = 20

    public init(
        currentSyncIntervalMinutes: @escaping () -> Int,
        lastQueuedFixAtStore: LastQueuedFixAtStoring,
        now: @escaping () -> Date = Date.init,
        captureCoordinator: FixCaptureCoordinator,
        syncCoordinator: LocationSyncCoordinator,
        settingsApplying: DeviceSettingsApplying,
        geofenceConfigSyncing: GeofenceConfigSyncing = NoOpGeofenceConfigSyncing(),
        geofenceEventDraining: GeofenceEventDraining = NoOpGeofenceEventDraining(),
        onReRegisterDevice: @escaping () async -> Void,
        onSignedOut: @escaping () async -> Void
    ) {
        self.currentSyncIntervalMinutes = currentSyncIntervalMinutes
        self.lastQueuedFixAtStore = lastQueuedFixAtStore
        self.now = now
        self.captureCoordinator = captureCoordinator
        self.syncCoordinator = syncCoordinator
        self.settingsApplying = settingsApplying
        self.geofenceConfigSyncing = geofenceConfigSyncing
        self.geofenceEventDraining = geofenceEventDraining
        self.onReRegisterDevice = onReRegisterDevice
        self.onSignedOut = onSignedOut
    }

    public func runOnce() async -> RunResult {
        await maybeCapturePeriodicFix()
        let fixResult = await drainQueue()
        // A transient failure on the fix queue backs off the whole run (specs/009 §9) - no point
        // hammering the geofence-event endpoint too in the same cycle; the next run retries both.
        if fixResult == .retry { return .retry }
        return await drainGeofenceEventQueue()
    }

    private func maybeCapturePeriodicFix() async {
        let interval = currentSyncIntervalMinutes()
        let shouldCapture = SyncTriggerPolicy.shouldCapture(
            syncIntervalMinutes: interval, lastQueuedFixAt: lastQueuedFixAtStore.lastQueuedFixAt(), now: now()
        )
        guard shouldCapture else { return }
        // FixCaptureCoordinator applies its own §1.2 suppression (paused/permission/debounce) -
        // a nil result here just means nothing was queued, which is fine to treat as "no update
        // to lastQueuedFixAt" (the next trigger will re-evaluate the same 0.8 threshold).
        if await captureCoordinator.captureAndQueue(source: .periodic) != nil {
            lastQueuedFixAtStore.recordQueuedFixAt(now())
        }
    }

    private func drainQueue() async -> RunResult {
        for _ in 0..<Self.maxBatchesPerRun {
            let outcome = await syncCoordinator.syncOnce()
            switch outcome {
            case .nothingToSync:
                return .success

            case .synced(_, _, let deviceSettings, let geofenceEtag):
                // 001 §5.1 / 009 §1: applying the piggyback is mandatory on every accepted
                // response, not just a `.paused` nicety - and a successful sync never stops the
                // run, more of the queue may remain.
                await applySyncedPiggyback(deviceSettings: deviceSettings, geofenceEtag: geofenceEtag)

            case .paused(let deviceSettings):
                await settingsApplying.applySettings(deviceSettings)
                return .success

            case .reRegisterDevice:
                await onReRegisterDevice()
                return .success

            case .signedOut:
                await onSignedOut()
                return .success

            case .transientFailure:
                return .retry

            case .rejected, .otherFailure:
                continue // the dead/rejected batch is already resolved inside the queue store
            }
        }
        return .success
    }

    /// specs/009 §6.3: "Events are flushed like fixes, batched 1-20 per call". Mirrors
    /// `drainQueue`'s structure exactly, minus the periodic-capture step (that's fix-queue-only)
    /// and minus a `.rejected` case (001 §7.3 defines no per-event rejection shape).
    private func drainGeofenceEventQueue() async -> RunResult {
        for _ in 0..<Self.maxBatchesPerRun {
            let outcome = await geofenceEventDraining.syncOnce()
            switch outcome {
            case .nothingToSync:
                return .success

            case .synced(_, _, let deviceSettings, let geofenceEtag):
                await applySyncedPiggyback(deviceSettings: deviceSettings, geofenceEtag: geofenceEtag)

            case .paused(let deviceSettings):
                await settingsApplying.applySettings(deviceSettings)
                return .success

            case .reRegisterDevice:
                await onReRegisterDevice()
                return .success

            case .signedOut:
                await onSignedOut()
                return .success

            case .transientFailure:
                return .retry

            case .otherFailure:
                continue // the batch stays frozen for retry; more of the queue may still drain
            }
        }
        return .success
    }

    /// The shared "apply the mandatory piggyback" step both drain loops' `.synced` case needs
    /// (001-api-contract.md §5.1/§7.3): settings apply unconditionally; the geofence config only
    /// re-syncs when the observed etag actually differs from the cached one
    /// (`GeofenceConfigSyncing.syncIfEtagChanged`, specs/009 §6.2/§6.3).
    private func applySyncedPiggyback(deviceSettings: DeviceSettingsSnapshot, geofenceEtag: String) async {
        await settingsApplying.applySettings(deviceSettings)
        await geofenceConfigSyncing.syncIfEtagChanged(geofenceEtag)
    }
}
