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

    /// Whether the user has already answered "Not now" to this kind's disclosure (I31, mirrors
    /// A25, specs/009-device-runtime.md §7). Tracked as a separate flag from
    /// `isAcknowledged`/`acknowledge` (never conflated) so `clearDeclined` can forget only the
    /// decline when the banner's explicit "reopen the disclosure" action fires, without also
    /// fabricating an acknowledgement that was never given.
    func isDeclined(_ kind: PermissionDisclosureKind) -> Bool
    func decline(_ kind: PermissionDisclosureKind)

    /// Forgets a prior decline for this kind only — used when an explicit user action on the
    /// degraded-state banner re-opens the full-screen disclosure (I31, specs/009 §7), so the flow
    /// gate presents it again instead of staying suppressed.
    func clearDeclined(_ kind: PermissionDisclosureKind)

    /// Drops both acknowledgements and both declines — part of the account-deletion local wipe
    /// (specs/008 §4.4). A different user on the same device must see the explanation again: this
    /// is consent, not a device-level preference.
    func clear()
}

/// Test/default in-memory implementation.
public final class InMemoryPermissionDisclosureStore: PermissionDisclosureStateStoring {
    private var acknowledged: Set<PermissionDisclosureKind> = []
    private var declined: Set<PermissionDisclosureKind> = []

    public init() {}

    public func isAcknowledged(_ kind: PermissionDisclosureKind) -> Bool { acknowledged.contains(kind) }
    public func acknowledge(_ kind: PermissionDisclosureKind) { acknowledged.insert(kind) }
    public func isDeclined(_ kind: PermissionDisclosureKind) -> Bool { declined.contains(kind) }
    public func decline(_ kind: PermissionDisclosureKind) { declined.insert(kind) }
    public func clearDeclined(_ kind: PermissionDisclosureKind) { declined.remove(kind) }
    public func clear() {
        acknowledged.removeAll()
        declined.removeAll()
    }
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

    private func declinedKey(for kind: PermissionDisclosureKind) -> String {
        switch kind {
        case .foreground: return "com.findly.permissionDisclosure.foreground.declined"
        case .background: return "com.findly.permissionDisclosure.background.declined"
        }
    }

    public func isAcknowledged(_ kind: PermissionDisclosureKind) -> Bool {
        defaults.bool(forKey: key(for: kind))
    }

    public func acknowledge(_ kind: PermissionDisclosureKind) {
        defaults.set(true, forKey: key(for: kind))
    }

    public func isDeclined(_ kind: PermissionDisclosureKind) -> Bool {
        defaults.bool(forKey: declinedKey(for: kind))
    }

    public func decline(_ kind: PermissionDisclosureKind) {
        defaults.set(true, forKey: declinedKey(for: kind))
    }

    public func clearDeclined(_ kind: PermissionDisclosureKind) {
        defaults.removeObject(forKey: declinedKey(for: kind))
    }

    public func clear() {
        defaults.removeObject(forKey: key(for: .foreground))
        defaults.removeObject(forKey: key(for: .background))
        defaults.removeObject(forKey: declinedKey(for: .foreground))
        defaults.removeObject(forKey: declinedKey(for: .background))
    }
}

extension PermissionDisclosureKind: Hashable {}

/// Lets SwiftUI drive a `fullScreenCover(item:)` straight from the view model's `disclosure`,
/// without a wrapper type whose only job would be to carry an id.
extension PermissionDisclosureKind: Identifiable {
    public var id: Self { self }
}
