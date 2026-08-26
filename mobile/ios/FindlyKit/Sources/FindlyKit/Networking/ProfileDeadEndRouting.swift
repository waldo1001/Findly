import Foundation

/// specs/010-app-shell-and-screen-ux.md §2.1 — the ONE mapping every feature screen's load path
/// (Geofences, Map, History, Devices, Family, Locate, Export) reuses: a confirmed `404
/// PROFILE_NOT_FOUND` or `404 FAMILY_NOT_FOUND` on a load MUST NOT render a retryable error card
/// (retrying a `GET` cannot create a profile, 001 §1.5.3) — it identifies which Onboarding variant
/// to route to instead. Every other error (transport, decode, any other server code) returns `nil`,
/// so the caller's existing `.error(userFacingMessage(for:))` inline rendering is unchanged for
/// those — this rule is about the load path's two specific 404s, nothing else (010 §2.1).
public func onboardingRoutingOutcome(for error: Error) -> OnboardingVariant? {
    switch (error as? APIError)?.serverCode {
    case .profileNotFound: return .profileLess
    case .familyNotFound: return .familyLess
    default: return nil
    }
}
