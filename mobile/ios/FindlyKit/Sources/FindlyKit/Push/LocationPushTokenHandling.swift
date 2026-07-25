import Foundation

/// specs/004-ios-client.md §7, specs/000 §O1 — the #1 platform risk. Scaffolds capture of the APNs
/// Location Push token so it can be plumbed into `RegisterDeviceRequest.locationPushToken` the
/// moment it's available, exactly like the regular FCM/APNs push token (`PushTokenProviding`).
///
/// **The `com.apple.developer.location.push` entitlement itself is a human/Apple-account action**
/// — Apple Developer Program enrollment ($99/yr), then a formal entitlement request. Apply
/// immediately; this is explicitly NOT blocking I1/I2 coding (specs/004 §7). Until granted, there
/// is no real conforming type to write — `CLLocationManager.startMonitoringLocationPushes()`
/// requires the entitlement to do anything meaningful — and the app relies on the FCM data-only
/// `LOCATE_REQUEST` push (specs/001 §8.1) exactly as normatively specified, with the UI (I2)
/// falling back to "last known, updating…" per 000 §O1. The Location Push Service Extension target
/// itself is not created in I1 — it has no code to write until the entitlement exists.
public protocol LocationPushTokenHandling {
    var locationPushTokenUpdates: AsyncStream<String> { get }
}

/// Test/dev double — call `emit(_:)` to simulate the token becoming available.
public final class StubLocationPushTokenHandler: LocationPushTokenHandling {
    public let locationPushTokenUpdates: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation

    public init() {
        var continuation: AsyncStream<String>.Continuation!
        self.locationPushTokenUpdates = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    public func emit(_ token: String) {
        continuation.yield(token)
    }

    public func finish() {
        continuation.finish()
    }
}
