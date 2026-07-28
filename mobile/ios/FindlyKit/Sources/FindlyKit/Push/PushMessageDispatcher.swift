import Foundation

// Narrow per-type protocols (rather than depending on the concrete handler classes directly) so
// `PushMessageDispatcher` is unit-testable in isolation from each handler's own parsing/networking
// logic (already covered by their dedicated test files) — mirrors the seam pattern used throughout
// this codebase (`DeviceSettingsApplying`, `GeofenceConfigRegistering`, …). The four concrete
// handler classes each conform to exactly one of these.

public protocol LocateRequestHandling {
    func handle(_ data: [String: String]) async
}

public protocol SettingsChangedHandling {
    func handle(_ data: [String: String]) async
}

public protocol GeofenceEventHandling {
    func handle(_ data: [String: String])
}

public protocol GeofenceConfigChangedHandling {
    func handle(_ data: [String: String]) async
}

/// Routes one FCM data payload to its specs/001-api-contract.md §8 handler by `data["type"]`
/// (specs/009-device-runtime.md §5), reusing `PushMessageType`'s existing parser rather than a
/// second string comparison. Unknown types and the §8.7 reserved group types both parse to
/// `PushMessageType.unrecognized` and run no handler at all — 001 §1.1's forward-compatibility
/// rule. Mirrors Android's `PushMessageDispatcher`.
public final class PushMessageDispatcher {
    private let locateRequestHandler: LocateRequestHandling
    private let settingsChangedHandler: SettingsChangedHandling
    private let geofenceEventHandler: GeofenceEventHandling
    private let geofenceConfigChangedHandler: GeofenceConfigChangedHandling

    public init(
        locateRequestHandler: LocateRequestHandling,
        settingsChangedHandler: SettingsChangedHandling,
        geofenceEventHandler: GeofenceEventHandling,
        geofenceConfigChangedHandler: GeofenceConfigChangedHandling
    ) {
        self.locateRequestHandler = locateRequestHandler
        self.settingsChangedHandler = settingsChangedHandler
        self.geofenceEventHandler = geofenceEventHandler
        self.geofenceConfigChangedHandler = geofenceConfigChangedHandler
    }

    public func dispatch(_ data: [String: String]) async {
        switch PushMessageType.from(data) {
        case .locateRequest:
            await locateRequestHandler.handle(data)
        case .settingsChanged:
            await settingsChangedHandler.handle(data)
        case .geofenceEvent:
            geofenceEventHandler.handle(data)
        case .geofenceConfigChanged:
            await geofenceConfigChangedHandler.handle(data)
        case .unrecognized:
            break
        }
    }
}
