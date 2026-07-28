import Foundation

/// The full geofence-registration seam (specs/009-device-runtime.md §6.2) — widens
/// `GeofenceRegistrarStub` (I10's "unregister all" half, still used standalone by
/// `DeviceSettingsCoordinator`'s pause path) with the "register all" half I11 adds. One real class,
/// `SystemGeofenceRegistrar`, implements both halves — mirrors how Android's A11 ended up with one
/// `GeofencingClientManager` implementing both `GeofenceRegistry`/`GeofenceRegistrar` (A9/A10's
/// separately-seamed halves), as A10's own report predicted for iOS too.
///
/// `registerAll` is always a **full replace** — "unregister all, then register all", performed by
/// the conforming implementation itself (every `GeofenceConfigSyncCoordinator` trigger only ever
/// calls this one method). specs/009 §6.2 (normative): non-atomicity between the two platform calls
/// is an accepted risk, not a bug to fix — implementations MUST NOT attempt to make this atomic
/// (there is no platform primitive for it). Not `async`/`throws`: `CLLocationManager`'s
/// `startMonitoring(for:)`/`stopMonitoring(for:)` are synchronous, fire-and-forget calls with no
/// completion handshake (unlike Android's `GeofencingClient`, which needs a `Task`/coroutine
/// because its `addGeofences`/`removeGeofences` return a `Task<Void>` to await).
public protocol GeofenceRegistering: GeofenceRegistrarStub {
    /// Registers exactly `geofences` with the platform, replacing whatever was previously
    /// registered. `etag` is accepted for symmetry with `GeofenceConfigSyncCoordinator`'s call site
    /// (documents "this is the registration matching that config version") but conforming
    /// implementations have no platform use for it — region monitoring has no concept of an ETag.
    func registerAll(geofences: [Geofence], etag: String)
}

/// Test/default no-op implementation — both halves inert. `LocationRuntimeContainer`'s default
/// until a real device build supplies `SystemGeofenceRegistrar`.
public final class NoOpGeofenceRegistrar: GeofenceRegistering {
    public init() {}
    public func unregisterAll() {}
    public func registerAll(geofences: [Geofence], etag: String) {}
}
