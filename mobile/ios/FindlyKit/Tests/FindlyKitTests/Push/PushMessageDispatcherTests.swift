import Testing
@testable import FindlyKit

private final class FakeLocateRequestHandling: LocateRequestHandling {
    private(set) var handledPayloads: [[String: String]] = []
    func handle(_ data: [String: String]) async { handledPayloads.append(data) }
}

private final class FakeSettingsChangedHandling: SettingsChangedHandling {
    private(set) var handledPayloads: [[String: String]] = []
    func handle(_ data: [String: String]) async { handledPayloads.append(data) }
}

private final class FakeGeofenceEventHandling: GeofenceEventHandling {
    private(set) var handledPayloads: [[String: String]] = []
    func handle(_ data: [String: String]) { handledPayloads.append(data) }
}

private final class FakeGeofenceConfigChangedHandling: GeofenceConfigChangedHandling {
    private(set) var handledPayloads: [[String: String]] = []
    func handle(_ data: [String: String]) async { handledPayloads.append(data) }
}

/// specs/009-device-runtime.md §5 — routes one FCM data payload to its 001 §8 handler by
/// `data["type"]`, reusing `PushMessageType`'s parser. Unknown types and the §8.7 reserved group
/// types both parse to `.unrecognized` and run NO handler at all — 001 §1.1's forward-compatibility
/// rule, mirroring Android's `PushMessageDispatcher` exactly.
struct PushMessageDispatcherTests {

    private func makeDispatcher() -> (
        locate: FakeLocateRequestHandling, settings: FakeSettingsChangedHandling,
        geofenceEvent: FakeGeofenceEventHandling, geofenceConfig: FakeGeofenceConfigChangedHandling,
        dispatcher: PushMessageDispatcher
    ) {
        let locate = FakeLocateRequestHandling()
        let settings = FakeSettingsChangedHandling()
        let geofenceEvent = FakeGeofenceEventHandling()
        let geofenceConfig = FakeGeofenceConfigChangedHandling()
        let dispatcher = PushMessageDispatcher(
            locateRequestHandler: locate,
            settingsChangedHandler: settings,
            geofenceEventHandler: geofenceEvent,
            geofenceConfigChangedHandler: geofenceConfig
        )
        return (locate, settings, geofenceEvent, geofenceConfig, dispatcher)
    }

    @Test func locateRequest_routesOnlyToItsHandler() async {
        let handlers = makeDispatcher()

        await handlers.dispatcher.dispatch(["type": "LOCATE_REQUEST", "requestId": "lr_1"])

        #expect(handlers.locate.handledPayloads.count == 1)
        #expect(handlers.settings.handledPayloads.isEmpty)
        #expect(handlers.geofenceEvent.handledPayloads.isEmpty)
        #expect(handlers.geofenceConfig.handledPayloads.isEmpty)
    }

    @Test func settingsChanged_routesOnlyToItsHandler() async {
        let handlers = makeDispatcher()

        await handlers.dispatcher.dispatch(["type": "SETTINGS_CHANGED", "syncIntervalMinutes": "30", "trackingEnabled": "true"])

        #expect(handlers.settings.handledPayloads.count == 1)
        #expect(handlers.locate.handledPayloads.isEmpty)
        #expect(handlers.geofenceEvent.handledPayloads.isEmpty)
        #expect(handlers.geofenceConfig.handledPayloads.isEmpty)
    }

    @Test func geofenceEvent_routesOnlyToItsHandler() async {
        let handlers = makeDispatcher()

        await handlers.dispatcher.dispatch(["type": "GEOFENCE_EVENT", "displayName": "Noor"])

        #expect(handlers.geofenceEvent.handledPayloads.count == 1)
        #expect(handlers.locate.handledPayloads.isEmpty)
        #expect(handlers.settings.handledPayloads.isEmpty)
        #expect(handlers.geofenceConfig.handledPayloads.isEmpty)
    }

    @Test func geofenceConfigChanged_routesOnlyToItsHandler() async {
        let handlers = makeDispatcher()

        await handlers.dispatcher.dispatch(["type": "GEOFENCE_CONFIG_CHANGED", "etag": "\"e1\""])

        #expect(handlers.geofenceConfig.handledPayloads.count == 1)
        #expect(handlers.locate.handledPayloads.isEmpty)
        #expect(handlers.settings.handledPayloads.isEmpty)
        #expect(handlers.geofenceEvent.handledPayloads.isEmpty)
    }

    @Test func unknownType_dispatchesToNoHandler() async {
        let handlers = makeDispatcher()

        await handlers.dispatcher.dispatch(["type": "SOMETHING_NEW"])

        #expect(handlers.locate.handledPayloads.isEmpty)
        #expect(handlers.settings.handledPayloads.isEmpty)
        #expect(handlers.geofenceEvent.handledPayloads.isEmpty)
        #expect(handlers.geofenceConfig.handledPayloads.isEmpty)
    }

    @Test func reservedGroupTypes_dispatchToNoHandler() async {
        let handlers = makeDispatcher()

        await handlers.dispatcher.dispatch(["type": "GROUP_MEMBER_JOINED"])
        await handlers.dispatcher.dispatch(["type": "GROUP_ENDING_SOON"])

        #expect(handlers.locate.handledPayloads.isEmpty)
        #expect(handlers.settings.handledPayloads.isEmpty)
        #expect(handlers.geofenceEvent.handledPayloads.isEmpty)
        #expect(handlers.geofenceConfig.handledPayloads.isEmpty)
    }

    @Test func missingType_dispatchesToNoHandler_neverCrashes() async {
        let handlers = makeDispatcher()

        await handlers.dispatcher.dispatch([:])

        #expect(handlers.locate.handledPayloads.isEmpty)
        #expect(handlers.settings.handledPayloads.isEmpty)
        #expect(handlers.geofenceEvent.handledPayloads.isEmpty)
        #expect(handlers.geofenceConfig.handledPayloads.isEmpty)
    }
}
