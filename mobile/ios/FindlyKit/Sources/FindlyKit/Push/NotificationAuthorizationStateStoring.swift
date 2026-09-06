import Foundation

/// Whether notification authorization has already been requested once (specs/009-device-runtime.md
/// §7, amended 2026-09-06: "the latter MUST actually be issued on first sign-in" — "first", not
/// "every"). A boolean about what THIS APP has already asked, not about the OS's answer — that is
/// tracked separately, by `UNUserNotificationCenter` itself, which already refuses to re-prompt
/// once a user has answered. This store exists so `NotificationAuthorizationCoordinator` never
/// calls the real requester more than once per install, even though calling it again would itself
/// be harmless to the OS. Mirrors `PermissionDisclosureStateStoring`'s shape/reasoning.
public protocol NotificationAuthorizationStateStoring {
    var hasRequested: Bool { get }
    func markRequested()
}

public final class InMemoryNotificationAuthorizationStateStore: NotificationAuthorizationStateStoring {
    private var requested = false
    public init() {}
    public var hasRequested: Bool { requested }
    public func markRequested() { requested = true }
}

/// The real, `UserDefaults`-backed implementation — same shape as
/// `UserDefaultsPermissionDisclosureStore`. Plain `UserDefaults` on purpose: this is a boolean
/// about what the app has already asked, carrying no location data, no identifier, and nothing an
/// attacker gains from reading or flipping it.
public final class UserDefaultsNotificationAuthorizationStateStore: NotificationAuthorizationStateStoring {
    private static let key = "com.findly.notificationAuthorization.requested"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hasRequested: Bool { defaults.bool(forKey: Self.key) }
    public func markRequested() { defaults.set(true, forKey: Self.key) }
}
