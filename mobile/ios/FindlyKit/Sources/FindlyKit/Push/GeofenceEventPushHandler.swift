import Foundation

/// `GEOFENCE_EVENT` (specs/001-api-contract.md §8.2; specs/009-device-runtime.md §5.3) — a
/// user-visible notification about **another** family member; no location action is taken. All the
/// testable logic (the exact title template) lives in `GeofenceEventNotificationTemplate`; a
/// malformed payload is dropped silently and never reaches `notifier`. Synchronous (matches
/// `GeofenceEventNotifying.notify`'s fire-and-forget shape) — mirrors Android's
/// `GeofenceEventPushHandler`.
public final class GeofenceEventPushHandler: GeofenceEventHandling {
    private let notifier: GeofenceEventNotifying

    public init(notifier: GeofenceEventNotifying) {
        self.notifier = notifier
    }

    public func handle(_ data: [String: String]) {
        guard let title = GeofenceEventNotificationTemplate.title(for: data) else { return }
        notifier.notify(title: title)
    }
}
