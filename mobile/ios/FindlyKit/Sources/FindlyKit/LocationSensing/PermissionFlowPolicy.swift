import Foundation

/// The location-authorization states this app distinguishes, collapsed from the platform's own
/// richer enums (`CLAuthorizationStatus` on iOS; two separate permission checks on Android) so the
/// policy below is platform-agnostic and testable without either framework.
public enum LocationAuthorization: Equatable, Sendable {
    /// Never asked. The OS dialog is still available.
    case notDetermined
    /// Foreground only — iOS `authorizedWhenInUse`, Android `ACCESS_FINE_LOCATION` without
    /// `ACCESS_BACKGROUND_LOCATION`.
    case whenInUse
    /// Background-capable — iOS `authorizedAlways`, Android fine + background.
    case always
    /// Refused or unavailable (`denied`/`restricted`). The OS will not show its dialog again, so
    /// the only route back is system settings.
    case denied
}

/// Which explanation to show. They are distinct screens because they make distinct asks, and
/// 003 §11.2 requires the background one to be a **separate, later** request.
public enum PermissionDisclosureKind: Equatable, Sendable {
    case foreground
    case background
}

/// The one next action in the permission flow.
public enum PermissionFlowStep: Equatable, Sendable {
    /// Show the in-app explanation. **Nothing may trigger an OS prompt while this is pending** —
    /// that ordering is the entire point of 009 §7's "prominent disclosure precedes the OS prompt".
    case showDisclosure(PermissionDisclosureKind)
    case requestForeground
    case requestBackgroundUpgrade
    /// Nothing to ask: either fully authorized, sufficiently authorized for the current interval,
    /// or denied (where asking again cannot succeed).
    case none
}

/// The degraded-state banner (009 §7). Denial is never fatal — the family map still works, this
/// device simply stops contributing — so the app must say so rather than appear to work.
public enum PermissionBanner: Equatable, Sendable {
    case none
    /// Location refused outright: this device cannot report its position at all.
    case cannotReport
    /// Foreground granted, background refused, and the configured interval needs background:
    /// reporting happens only while the app is open.
    case foregroundOnly
}

/// specs/009-device-runtime.md §7 + specs/003-android-client.md §11 — the permission flow's
/// decisions, as pure functions.
///
/// **Why this is a policy type rather than logic inside a view:** §7's requirements are behavioural
/// ("disclosure precedes the OS prompt", "dismissible-per-session", "re-checked on every
/// foreground") and were normative from the start, yet went unimplemented on both platforms for the
/// entire project — precisely because they lived only in prose and in a view-layer TODO. Expressed
/// here they are unit-testable on a plain macOS host, and Android's `PermissionFlowPolicy` mirrors
/// the same rules so the two clients cannot drift.
public enum PermissionFlowPolicy {

    /// The single next action, given current authorization and what the user has already been told.
    ///
    /// - Parameters:
    ///   - requiresBackground: whether this device's configured `syncIntervalMinutes` needs
    ///     background reporting at all (003 §11.3). A device that only reports while open never
    ///     asks for the background upgrade, and never nags about lacking it.
    public static func nextStep(
        authorization: LocationAuthorization,
        foregroundDisclosureAcknowledged: Bool,
        backgroundDisclosureAcknowledged: Bool,
        requiresBackground: Bool
    ) -> PermissionFlowStep {
        switch authorization {
        case .denied:
            // The OS dialog is spent. Re-prompting cannot succeed and re-explaining is nagging;
            // 003 §11.5 routes the user to system settings through the banner instead.
            return .none

        case .always:
            return .none

        case .notDetermined:
            return foregroundDisclosureAcknowledged ? .requestForeground : .showDisclosure(.foreground)

        case .whenInUse:
            guard requiresBackground else { return .none }
            return backgroundDisclosureAcknowledged ? .requestBackgroundUpgrade : .showDisclosure(.background)
        }
    }

    /// The degraded-state banner to show, if any.
    ///
    /// - Parameter dismissedThisSession: deliberately **not** persisted. 009 §7 says
    ///   "dismissible-per-session": a user who waves it away once should still be told, next
    ///   launch, that this device is not reporting. Persisting dismissal would let a silently
    ///   broken device stay silently broken forever.
    public static func banner(
        authorization: LocationAuthorization,
        requiresBackground: Bool,
        dismissedThisSession: Bool
    ) -> PermissionBanner {
        guard !dismissedThisSession else { return .none }

        switch authorization {
        case .denied:
            // Checked before `foregroundOnly` on purpose: both can apply at once, and "this device
            // cannot report at all" is the more severe truth.
            return .cannotReport
        case .whenInUse:
            return requiresBackground ? .foregroundOnly : .none
        case .always, .notDetermined:
            // `.notDetermined` shows nothing: the user has not refused anything yet, and the
            // disclosure/prompt flow is what should be running instead.
            return .none
        }
    }
}
