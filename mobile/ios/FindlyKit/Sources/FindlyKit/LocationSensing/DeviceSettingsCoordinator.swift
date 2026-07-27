import Foundation

/// specs/009-device-runtime.md §3.4/§4 — the schedule-rebuild half of settings application:
/// canceling/rescheduling the opportunistic sync triggers. `SystemBackgroundSyncScheduler`
/// implements this for real (`BGTaskScheduler`); significant-location-change monitoring is
/// started/stopped by whoever owns the `LocationProviding` instance (`LocationRuntimeContainer`),
/// which is why `cancelAll`/`reschedule` alone don't fully implement §4's teardown — the
/// coordinator below composes this WITH stopping/starting background monitoring at its one call
/// site.
public protocol SyncScheduling {
    func reschedule(syncIntervalMinutes: Int)
    func cancelAll()
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
/// Pause (§4) is implemented here directly: canceling the schedule and unregistering geofences are
/// the only two actions §4 lists beyond "stop capturing", and "stop capturing" is already a natural
/// consequence of `stateStore` being the same source of truth a real pause-check closure reads
/// (specs/009 §1.2) — no separate signal is needed. Resume (§4) restores the schedule via the same
/// `rebuildSchedule` path an interval change uses, and calls `onResume` — `LocationRuntimeContainer`
/// wires this to re-arm significant-location-change monitoring (and, once I11 lands, geofence
/// config re-sync — specs/009 §6.2: "resume from pause" is one of its five re-registration
/// triggers). Mirrors Android's `DeviceSettingsCoordinator` exactly.
public actor DeviceSettingsCoordinator: DeviceSettingsApplying {
    private let scheduler: SyncScheduling
    private let geofenceRegistrar: GeofenceRegistrarStub
    private let stateStore: DeviceSettingsStateStoring
    private let onResume: () async -> Void

    public init(
        scheduler: SyncScheduling,
        geofenceRegistrar: GeofenceRegistrarStub = NoOpGeofenceRegistrarStub(),
        stateStore: DeviceSettingsStateStoring,
        onResume: @escaping () async -> Void = {}
    ) {
        self.scheduler = scheduler
        self.geofenceRegistrar = geofenceRegistrar
        self.stateStore = stateStore
        self.onResume = onResume
    }

    public func applySettings(_ next: DeviceSettingsSnapshot) async {
        let previous = stateStore.current()
        let actions = SettingsChangeDecision.decide(previous: previous, next: next)

        // Order matters: cache the new settings BEFORE touching the schedule/geofences, so any
        // capture that races this call already observes the new paused state (§1.2's "stop
        // capturing" is enforced by every capture attempt reading stateStore fresh).
        stateStore.update(next)

        switch actions.pauseAction {
        case .pause:
            scheduler.cancelAll()
            geofenceRegistrar.unregisterAll()
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
