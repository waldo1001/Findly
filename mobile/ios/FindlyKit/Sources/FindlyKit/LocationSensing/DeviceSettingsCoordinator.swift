import Foundation

/// specs/009-device-runtime.md §3.4/§4 — the schedule-rebuild half of settings application.
///
/// **Deliberately has no `cancelAll`/"stop the BG task" method (post-review correction).** An
/// earlier version of this protocol had one, and `DeviceSettingsCoordinator`'s `.pause` case
/// called it — which is exactly backwards for iOS. specs/009 §4's first paragraph ("cancel the BG
/// task... and stop capturing") describes Android's WorkManager/foreground-service model; its
/// SECOND paragraph is the one that actually governs iOS: "a low-frequency worker/BG task is the
/// **only thing that keeps running while paused**" — the very mechanism that makes the pull-based
/// resume possible. Canceling the only surviving background trigger on pause would strand a
/// remotely-paused device with no way to ever notice a resume short of the user manually
/// reopening the app, directly violating "MUST re-check its settings... at least every 6 hours."
/// `LocationRuntimeContainer.handleBackgroundRefresh()` is what actually varies behavior by pause
/// state (poll-and-reschedule-within-6h vs. the normal capture-and-sync cycle) — this protocol's
/// only remaining job is rescheduling on an interval/resume change.
public protocol SyncScheduling {
    func reschedule(syncIntervalMinutes: Int)
}

/// I11's not-yet-built region-monitoring lifecycle seam (specs/009 §6.2's "unregister all"
/// half only — full re-registration is I11's scope, not this task's). Stubbed the same way
/// Android's A9 stubbed `GeofenceRegistry`/`GeofenceRegistrar` for A10/A11: a documented no-op
/// implementation a future I11 session replaces with the real `CLLocationManager` region-monitoring
/// unregister-all call.
public protocol GeofenceRegistrarStub {
    func unregisterAll()
}

public final class NoOpGeofenceRegistrarStub: GeofenceRegistrarStub {
    public init() {}
    public func unregisterAll() {}
}

/// **The single settings-application entry point** (specs/009-device-runtime.md §3.5) — call
/// `applySettings` from **any** of the three arrival paths whenever a `DeviceSettingsSnapshot` is
/// observed:
///
/// 1. The `SETTINGS_CHANGED` push (§5.2) — I12's scope to wire the push arrival itself, but this is
///    the seam it calls into (mirrors Android's A9/A10 split exactly).
/// 2. The `POST /locations` piggyback (001-api-contract.md §5.1's `deviceSettings` field on every
///    accepted response) — `LocationSyncRunner` calls this after every flush.
/// 3. The paused-device poll (§4, `PausedDevicePoller`).
///
/// Idempotent and reorder-safe: applying the same settings twice, or an older snapshot after a
/// newer one already landed, is always evaluated against whatever is currently cached in
/// `stateStore` — never assumed to be a delta (§5.2: "apply both, idempotently... never treat it as
/// a delta"). An `actor` so concurrent arrivals from more than one of the three paths above don't
/// race the state-store read/decide/write sequence.
///
/// Pause (§4) is implemented here directly: unregistering geofences and **stopping
/// significant-location-change monitoring** (via `onPause`, post-review addition — see below) are
/// the two teardown actions this actor performs; the BG task is deliberately left scheduled (see
/// `SyncScheduling`'s doc). Resume (§4) restores the schedule via the same `rebuildSchedule` path
/// an interval change uses, and calls `onResume` — `LocationRuntimeContainer` wires both
/// `onPause`/`onResume` to `LocationProviding.stopBackgroundMonitoring()`/
/// `startBackgroundMonitoring(coordinator:)` (and, once I11 lands, geofence config re-sync on
/// resume — specs/009 §6.2: "resume from pause" is one of its five re-registration triggers).
/// Mirrors Android's `DeviceSettingsCoordinator`, with the one deliberate iOS-specific divergence
/// documented on `SyncScheduling`.
public actor DeviceSettingsCoordinator: DeviceSettingsApplying {
    private let scheduler: SyncScheduling
    private let geofenceRegistrar: GeofenceRegistrarStub
    private let stateStore: DeviceSettingsStateStoring
    private let onPause: () -> Void
    private let onResume: () async -> Void

    public init(
        scheduler: SyncScheduling,
        geofenceRegistrar: GeofenceRegistrarStub = NoOpGeofenceRegistrarStub(),
        stateStore: DeviceSettingsStateStoring,
        onPause: @escaping () -> Void = {},
        onResume: @escaping () async -> Void = {}
    ) {
        self.scheduler = scheduler
        self.geofenceRegistrar = geofenceRegistrar
        self.stateStore = stateStore
        self.onPause = onPause
        self.onResume = onResume
    }

    public func applySettings(_ next: DeviceSettingsSnapshot) async {
        let previous = stateStore.current()
        let actions = SettingsChangeDecision.decide(previous: previous, next: next)

        // Order matters: cache the new settings BEFORE touching geofences/monitoring, so any
        // capture that races this call already observes the new paused state (§1.2's "stop
        // capturing" is enforced by every capture attempt reading stateStore fresh).
        stateStore.update(next)

        switch actions.pauseAction {
        case .pause:
            geofenceRegistrar.unregisterAll()
            // specs/009 §4: "...and stop capturing" — post-review fix: this used to be missing
            // entirely, leaving significant-location-change monitoring armed while paused (the
            // device would keep waking for every significant move purely to have
            // FixCaptureCoordinator's own pause check discard the result — no data leak, but a
            // real, avoidable battery cost). The BG task itself is deliberately NOT stopped here —
            // see `SyncScheduling`'s doc for why that would be wrong on iOS.
            onPause()
        case .resume:
            await onResume()
        case .none:
            break
        }

        if actions.rebuildSchedule {
            scheduler.reschedule(syncIntervalMinutes: next.syncIntervalMinutes)
        }
    }
}

/// The seam `LocationSyncRunner`/`PausedDevicePoller`/a future I12 push handler all call through —
/// kept as a narrow protocol (rather than a direct `DeviceSettingsCoordinator` reference
/// everywhere) so I12 can plug the `SETTINGS_CHANGED` push arrival path in later without depending
/// on this actor's full concrete type (mirrors Android's `ScheduleRebuilder` seam pattern: A9 built
/// it, A10 implemented the real coordinator behind it — here, I12 plugs into this the same way).
public protocol DeviceSettingsApplying {
    func applySettings(_ settings: DeviceSettingsSnapshot) async
}
