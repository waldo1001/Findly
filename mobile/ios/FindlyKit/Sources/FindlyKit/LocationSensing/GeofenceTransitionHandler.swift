import Foundation

/// The parsed, platform-independent shape of one `CLLocationManagerDelegate`
/// `didEnterRegion`/`didExitRegion` callback (specs/009-device-runtime.md §6.3). Unlike Android's
/// `GeofenceTransitionEvent` (which needs `geofenceIds: [String]` because `GeofencingClient` can
/// batch several same-transition geofences into one callback), iOS delivers exactly one region per
/// delegate call — so this is deliberately a single `geofenceId`, a documented, intentional
/// simplification of the Android shape rather than an artificial array.
public struct GeofenceTransitionEvent: Equatable {
    public let geofenceId: String
    public let transition: GeofenceTransition
    /// The transition's own coordinates (specs/009 §6.3: "MAY reuse the transition's own
    /// coordinates") — on iOS, `SystemGeofenceRegistrar` derives this from `CLLocationManager`'s
    /// last-known location when available, falling back to the triggering `CLCircularRegion`'s own
    /// center (there is no Android-style "triggeringLocation" delivered with the callback).
    public let lat: Double
    public let lon: Double
    public let accuracyM: Double

    public init(geofenceId: String, transition: GeofenceTransition, lat: Double, lon: Double, accuracyM: Double) {
        self.geofenceId = geofenceId
        self.transition = transition
        self.lat = lat
        self.lon = lon
        self.accuracyM = accuracyM
    }
}

/// The seam `SystemGeofenceRegistrar`'s `CLLocationManagerDelegate` callbacks forward into — kept
/// narrow so the thin, untestable CoreLocation adapter doesn't need a concrete `GeofenceTransitionHandler`
/// reference, mirroring `DeviceSettingsApplying`'s pattern. Class-bound (`AnyObject`, mirroring
/// `LocationProviding`'s own bound) so `SystemGeofenceRegistrar` can hold it `weak` — it is set
/// post-construction, after `LocationRuntimeContainer` exists (see that class's doc), and must
/// never keep the container's handler graph alive past its own owner's lifetime.
public protocol GeofenceTransitionHandling: AnyObject {
    func handle(_ event: GeofenceTransitionEvent) async
}

/// The tested decision/coordination logic behind a region-monitoring enter/exit callback
/// (specs/009-device-runtime.md §6.3) — deliberately separated from `SystemGeofenceRegistrar` (the
/// untested `CLLocationManagerDelegate` glue) so this class needs no CoreLocation import at all,
/// matching the seam split I10 already established for `FixCaptureCoordinator` vs.
/// `SystemLocationProvider`. Mirrors Android's `GeofenceTransitionHandler`.
///
/// Per specs/009 §4: "transitions detected while paused are dropped, not queued" — a safety net
/// for the race where a callback was already in flight when pause called
/// `GeofenceRegistrarStub.unregisterAll()`; the normal case is that pause already removed every
/// platform registration, so no callback fires at all. This check has to happen here (not just
/// inside `fixCaptureCoordinator`, whose own pause check only guards the fix) because it must also
/// gate the geofence-event enqueue, which bypasses `FixCaptureCoordinator` entirely.
public final class GeofenceTransitionHandler: GeofenceTransitionHandling {
    private let eventQueue: GeofenceEventQueue
    private let fixCaptureCoordinator: FixCaptureCoordinator
    private let batteryLevelProvider: () -> Int
    private let isPaused: () -> Bool
    private let eventIdGenerator: () -> String
    private let fixIdGenerator: () -> String
    private let now: () -> Date

    public init(
        eventQueue: GeofenceEventQueue,
        fixCaptureCoordinator: FixCaptureCoordinator,
        batteryLevelProvider: @escaping () -> Int,
        isPaused: @escaping () -> Bool,
        eventIdGenerator: @escaping () -> String = { UUID().uuidString },
        fixIdGenerator: @escaping () -> String = { UUID().uuidString },
        now: @escaping () -> Date = Date.init
    ) {
        self.eventQueue = eventQueue
        self.fixCaptureCoordinator = fixCaptureCoordinator
        self.batteryLevelProvider = batteryLevelProvider
        self.isPaused = isPaused
        self.eventIdGenerator = eventIdGenerator
        self.fixIdGenerator = fixIdGenerator
        self.now = now
    }

    public func handle(_ event: GeofenceTransitionEvent) async {
        if isPaused() { return }

        let recordedAt = ISO8601DateFormatter().string(from: now())
        await eventQueue.enqueue(GeofenceEventReport(
            eventId: eventIdGenerator(), geofenceId: event.geofenceId, transition: event.transition, recordedAt: recordedAt
        ))

        // specs/009 §6.3: "additionally capture one fix with source: geofence... MAY reuse the
        // transition's own coordinates" - the hint short-circuits FixCaptureCoordinator's own
        // LocationProviding call entirely (no extra GPS burn, see its doc).
        let hint = LocationFix(
            fixId: fixIdGenerator(), recordedAt: recordedAt, lat: event.lat, lon: event.lon,
            accuracyM: event.accuracyM, batteryPct: batteryLevelProvider(), source: .geofence
        )
        await fixCaptureCoordinator.captureAndQueue(source: .geofence, hint: hint)
    }
}
