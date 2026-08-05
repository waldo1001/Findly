import Foundation

/// Whether the user has already been shown each explanation (specs/009-device-runtime.md §7).
///
/// **Persisted, unlike the banner's dismissal.** The two look similar and are deliberately
/// opposite: acknowledgement survives relaunch (nobody should re-read the same explanation every
/// launch), while banner dismissal is session-only so a device that cannot report is re-surfaced
/// next launch rather than staying silently broken. Keeping them in different places is what stops
/// one being "simplified" into the other later.
///
/// The two kinds are tracked separately because 003 §11.2 makes the background ask a **separate,
/// later** request with its own rationale — one shared flag would silently skip the background
/// disclosure, which is the screen Play's background-location review is looking for.
public protocol PermissionDisclosureStateStoring {
    func isAcknowledged(_ kind: PermissionDisclosureKind) -> Bool
    func acknowledge(_ kind: PermissionDisclosureKind)

    /// Drops both acknowledgements — part of the account-deletion local wipe (specs/008 §4.4).
    /// A different user on the same device must see the explanation again: this is consent, not a
    /// device-level preference.
    func clear()
}

/// Test/default in-memory implementation.
public final class InMemoryPermissionDisclosureStore: PermissionDisclosureStateStoring {
    private var acknowledged: Set<PermissionDisclosureKind> = []

    public init() {}

    public func isAcknowledged(_ kind: PermissionDisclosureKind) -> Bool { acknowledged.contains(kind) }
    public func acknowledge(_ kind: PermissionDisclosureKind) { acknowledged.insert(kind) }
    public func clear() { acknowledged.removeAll() }
}

/// The real, `UserDefaults`-backed implementation — same shape as
/// `UserDefaultsGeofenceConfigStateStore`. Plain `UserDefaults` rather than the Keychain on
/// purpose: this is a boolean about what a user has read, carrying no location data, no identifier
/// and nothing an attacker gains from reading or flipping. The worst a tampered value achieves is
/// showing or skipping an explanation screen.
public final class UserDefaultsPermissionDisclosureStore: PermissionDisclosureStateStoring {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(for kind: PermissionDisclosureKind) -> String {
        switch kind {
        case .foreground: return "com.findly.permissionDisclosure.foreground"
        case .background: return "com.findly.permissionDisclosure.background"
        }
    }

    public func isAcknowledged(_ kind: PermissionDisclosureKind) -> Bool {
        defaults.bool(forKey: key(for: kind))
    }

    public func acknowledge(_ kind: PermissionDisclosureKind) {
        defaults.set(true, forKey: key(for: kind))
    }

    public func clear() {
        defaults.removeObject(forKey: key(for: .foreground))
        defaults.removeObject(forKey: key(for: .background))
    }
}

extension PermissionDisclosureKind: Hashable {}
