import Foundation
#if os(iOS) && canImport(UserNotifications)
import UserNotifications
#endif

/// specs/009-device-runtime.md §7 (I50 fix 4, amended 2026-09-06) — requests `UNUserNotificationCenter`
/// authorization, behind a protocol so `NotificationAuthorizationCoordinator` stays testable without
/// `UserNotifications` (mirrors `GeofenceEventNotifying`'s split for the identical reason).
public protocol NotificationAuthorizationRequesting {
    func requestAuthorization() async
}

#if os(iOS) && canImport(UserNotifications)
/// The real, `UNUserNotificationCenter`-backed implementation. `[.alert, .sound]` per specs/009
/// §7 — no `.badge` (the app carries no badge count). Errors are swallowed: there is nothing
/// actionable to do with a failure here beyond what the OS authorization status itself already
/// conveys wherever a notification is about to be posted, and this call carries no
/// location/identifier data to leak either way (specs/009 §9).
public final class SystemNotificationAuthorizationRequester: NotificationAuthorizationRequesting {
    public init() {}

    public func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
}
#endif

/// Test/macOS-build default.
public final class NoOpNotificationAuthorizationRequester: NotificationAuthorizationRequesting {
    public init() {}
    public func requestAuthorization() async {}
}
