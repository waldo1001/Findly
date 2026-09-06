import Foundation

/// specs/009-device-runtime.md §1.3/§3.4 (I52 item 3) — what `SystemLocationProvider` should do to
/// the single shared `CLLocationManager` once every pending `requestSingleFix` caller has resolved,
/// given whether the §1.3 presence session is currently running its own continuous
/// `startUpdatingLocation()` stream on that SAME manager. See `PresenceAccuracyPolicyTests` for the
/// two concrete defects this rule prevents:
///
/// 1. **A one-shot capture must never leave the manager at a raised accuracy after it drains.**
///    The presence session sets `desiredAccuracy` to its coarse kilometre baseline once at start;
///    `PendingFixContinuations.registerAndAct` correctly RAISES it while a higher-tier caller
///    (I51's locate handler, the presence timer's own balanced tick) is pending, but nothing
///    previously put it back down once the registry drained — silently leaving an always-on
///    presence session running at GPS-class accuracy after a single locate, defeating the coarse
///    baseline's entire purpose.
/// 2. **A one-shot timeout must never stop the presence session itself.** Cancelling a stale
///    `requestLocation()` is normally done via `manager.stopUpdatingLocation()` — but that is the
///    exact same call that would tear down presence's own continuous stream, since both share one
///    `CLLocationManager`. Calling it unconditionally while presence is active would silently kill
///    presence every time an unrelated one-shot capture happened to time out.
public enum ManagerAccuracyDrainAction: Equatable {
    /// No presence session is running: safe to fully stop the manager (cancels the in-flight
    /// one-shot `requestLocation()`; nothing else depends on this manager staying alive).
    case stopUpdating
    /// A presence session is running: NEVER stop the manager — instead drop `desiredAccuracy` back
    /// to the presence baseline (`kCLLocationAccuracyThreeKilometers`), undoing whatever a one-shot
    /// caller raised it to, while leaving `startUpdatingLocation()`'s continuous stream untouched.
    case resetAccuracyToPresenceBaseline
}

public enum PresenceAccuracyPolicy {
    public static func drainAction(presenceActive: Bool) -> ManagerAccuracyDrainAction {
        presenceActive ? .resetAccuracyToPresenceBaseline : .stopUpdating
    }
}
