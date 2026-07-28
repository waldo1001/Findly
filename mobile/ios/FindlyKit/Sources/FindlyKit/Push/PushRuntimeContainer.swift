import Foundation

/// The composition root for I12's push runtime (specs/009-device-runtime.md §5, specs/001 §8) —
/// mirrors `LocationRuntimeContainer`'s role for I10: wires the four per-type handlers into one
/// `PushMessageDispatcher` with a small, app-target-facing public surface. Lives in `FindlyKit`
/// (not the app target) per specs/004-ios-client.md §1.1's rule — this is composition/wiring, not
/// app lifecycle.
///
/// Firebase-SDK-touching pieces (the real `PushTokenProviding` bridging APNs → FCM,
/// `UIApplicationDelegate` callbacks) deliberately stay in the app target (mirrors
/// `FirebaseAuthProvider`'s precedent) so `FindlyKit` stays Firebase-SDK-free and `swift test` keeps
/// running headless (specs/004 §9) — this container only needs the already-Firebase-free
/// `LocationProviding`/`FindlyAPIClient`/`DeviceSettingsApplying`/`GeofenceEventNotifying` seams.
public final class PushRuntimeContainer {
    public let dispatcher: PushMessageDispatcher

    public init(
        apiClient: FindlyAPIClient,
        locationProvider: LocationProviding,
        deviceId: @escaping () -> String?,
        settingsApplying: DeviceSettingsApplying,
        geofenceEventNotifier: GeofenceEventNotifying,
        geofenceConfigRegistrar: GeofenceConfigRegistering = NoOpGeofenceConfigRegistering(),
        geofenceConfigCache: GeofenceConfigCaching = InMemoryGeofenceConfigCache()
    ) {
        let locateRequestHandler = LocateRequestPushHandler(locationProvider: locationProvider, apiClient: apiClient, deviceId: deviceId)
        let settingsChangedHandler = SettingsChangedPushHandler(settingsApplying: settingsApplying)
        let geofenceEventHandler = GeofenceEventPushHandler(notifier: geofenceEventNotifier)
        let geofenceConfigSyncCoordinator = GeofenceConfigSyncCoordinator(apiClient: apiClient, cache: geofenceConfigCache, registrar: geofenceConfigRegistrar)
        let geofenceConfigChangedHandler = GeofenceConfigChangedPushHandler(syncCoordinator: geofenceConfigSyncCoordinator)

        self.dispatcher = PushMessageDispatcher(
            locateRequestHandler: locateRequestHandler,
            settingsChangedHandler: settingsChangedHandler,
            geofenceEventHandler: geofenceEventHandler,
            geofenceConfigChangedHandler: geofenceConfigChangedHandler
        )
    }
}

/// Mirrors `LocationRuntimeContainerHolder` exactly — a plain settable reference so the app
/// target's `AppDelegate` (created/invoked by `@UIApplicationDelegateAdaptor`, whose exact timing
/// relative to `App.init()` isn't something app code controls) can reach the dispatcher
/// `FindlyApp.init()` builds, without a direct reference cycle between the two. Holds no logic.
@MainActor
public final class PushRuntimeContainerHolder {
    public static let shared = PushRuntimeContainerHolder()
    public var container: PushRuntimeContainer?
    private init() {}
}
