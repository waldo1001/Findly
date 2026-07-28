import Foundation
#if os(iOS) && canImport(UserNotifications)
import UserNotifications
#endif

/// Posts an already-built notification title somewhere real. `SystemGeofenceEventNotifier` is the
/// production `UNUserNotificationCenter`-backed implementation; kept as its own protocol so
/// `GeofenceEventPushHandler` stays unit-testable without touching that framework (specs/004
/// §1.2's `Push/` folder doc, specs/009-device-runtime.md §5.3).
public protocol GeofenceEventNotifying {
    func notify(title: String)
}

#if os(iOS) && canImport(UserNotifications)
/// specs/001-api-contract.md §8.2, specs/009-device-runtime.md §5.3/§8 — re-renders the
/// `GEOFENCE_EVENT` push locally as a `UNNotificationRequest` built straight from the push's `data`
/// payload (000 §O8), rather than relying on the OS auto-displaying the FCM message's own
/// `notification.title` (which the app cannot fully control the timing/wording of, and — while the
/// app is foregrounded — the OS does not banner automatically at all without an explicit
/// `UNUserNotificationCenterDelegate` opt-in). No body (matches the wire template exactly — "the
/// notification's own timestamp conveys the time"). specs/009 §8: iOS uses the app icon directly,
/// no separate monochrome asset to set here (unlike Android's `ic_stat_findly`).
///
/// Thin, framework-touching glue by design — same untestable-by-nature category as
/// `SystemLocationProvider`; all the testable logic lives in `GeofenceEventNotificationTemplate`/
/// `GeofenceEventPushHandler`.
public final class SystemGeofenceEventNotifier: GeofenceEventNotifying {
    public init() {}

    public func notify(title: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
#endif
