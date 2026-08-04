import FindlyKit
import UserNotifications

/// I15 (specs/001-api-contract.md §8.2, specs/000-overview.md §O8) — the `UNNotificationServiceExtension`
/// `mutable-content: 1` on the `GEOFENCE_EVENT` push (001 §8.2) exists to enable. Only
/// `GEOFENCE_EVENT` pushes set that flag (001 §8), so this is the only shape the OS ever invokes
/// this extension for.
///
/// Kept logic-free by design, mirroring how `backend/src/functions` and the app target's
/// `AppDelegate` are kept thin elsewhere in this codebase (see its own doc comment): the ONLY
/// thing this class does is (1) bridge `UNNotificationRequest.content.userInfo` into the
/// `[String: String]` shape `FindlyKit`'s push types already parse — the exact same conversion
/// `AppDelegate.application(_:didReceiveRemoteNotification:...)` does inline — and (2) apply the
/// result of `GeofenceEventServiceExtensionRendering.title(for:)` (FindlyKit, unit-tested) to a
/// mutable copy of the content. All the actual template/parsing logic lives in FindlyKit and is
/// shared with the in-app `GeofenceEventPushHandler` dispatch path — not duplicated here.
///
/// Fallback contract: `bestAttemptContent` starts as an unmodified mutable copy of the server's
/// own content, and is only mutated if a title can actually be rendered. Both the normal
/// `didReceive` completion and the `serviceExtensionTimeWillExpire()` time-budget callback deliver
/// whatever `bestAttemptContent` currently holds — so a slow/failed render (or the OS's hard time
/// budget expiring) still shows the server's original `aps.alert.title`, never nothing.
final class NotificationService: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        let bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
        self.bestAttemptContent = bestAttemptContent

        var data: [String: String] = [:]
        for (key, value) in request.content.userInfo {
            guard let key = key as? String else { continue }
            data[key] = "\(value)"
        }

        if let title = GeofenceEventServiceExtensionRendering.title(for: data) {
            bestAttemptContent.title = title
        }

        contentHandler(bestAttemptContent)
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}
