import Foundation

/// specs/010-app-shell-and-screen-ux.md §1.1 — the async orchestrator both entry points (cold-start
/// restore, 004 §2.6; interactive sign-in) call: runs the `GET /families/me` probe **before any
/// device registration** (never for a signed-out caller), classifies the result into a
/// `ProfileProbeOutcome`, and defers to the pure `LaunchGate` table for the actual routing decision.
/// On a successful probe, also populates `FamilyContextCache` (§1.2) so the drawer header never
/// needs a fetch of its own.
///
/// Stateless by design — a bag of static functions, not a type instance — because it holds no
/// state of its own between calls; the caller supplies the `FindlyAPIClient` (already a FindlyKit
/// protocol, mockable in tests) each time.
@MainActor
public enum AppLaunchResolver {
    /// - Parameter onConfirmedAuthFailure: specs/010-app-shell-and-screen-ux.md §1.1 (amended, row
    ///   A37) — invoked, before returning, when the probe confirms the caller is unauthorized
    ///   (`AUTH_MISSING_TOKEN`/`AUTH_INVALID_TOKEN`/`AUTH_TOKEN_EXPIRED`/`AUTH_FORBIDDEN`). Callers
    ///   wire this to the SAME wipe-then-sign-out shape `FindlyApp.swift`'s forced `onSignedOut`
    ///   closure already uses (`authProvider.signOut()` + `LocationRuntimeContainer.
    ///   wipeLocalState()`) — never a second implementation (the I43 lesson). Defaults to a no-op
    ///   so every existing call site/test that doesn't care is unaffected.
    public static func resolve(
        apiClient: FindlyAPIClient,
        isSignedIn: Bool,
        cache: FamilyContextCache? = nil,
        onConfirmedAuthFailure: () async -> Void = {}
    ) async -> LaunchDestination {
        guard isSignedIn else { return .signIn }
        let probe = await probeProfile(apiClient: apiClient, cache: cache)
        if probe == .confirmedAuthFailure {
            await onConfirmedAuthFailure()
        }
        return LaunchGate.resolve(isSignedIn: true, probe: probe)
    }

    private static func probeProfile(apiClient: FindlyAPIClient, cache: FamilyContextCache?) async -> ProfileProbeOutcome {
        do {
            let envelope = try await apiClient.getMyFamily()
            let response = envelope.data
            let myDisplayName = response.members.first(where: { $0.userId == response.me.userId })?.displayName ?? ""
            cache?.update(familyName: response.familyName, myDisplayName: myDisplayName, isParent: response.me.role == "parent")
            return .confirmed
        } catch {
            return classify(error)
        }
    }

    /// specs/010 §1.1 (amended, row A37) — a CONFIRMED 404 routes to Onboarding, a CONFIRMED auth
    /// failure routes to Sign-in (clearing the session); everything else (timeout, 5xx, a 401/403
    /// that arrived with no decodable error code at all, a decode failure, an as-yet-unrecognized
    /// code) fails open. The branch is on the typed `serverCode`, never the raw HTTP status — a
    /// `.server` case's code is only ever non-nil when the body actually decoded (`APIError.
    /// serverCode`'s doc), which is exactly the amendment's "no error code was received" test.
    static func classify(_ error: Error) -> ProfileProbeOutcome {
        switch (error as? APIError)?.serverCode {
        case .profileNotFound: return .confirmedNoProfile
        case .familyNotFound: return .confirmedNoFamily
        case .authMissingToken, .authInvalidToken, .authTokenExpired, .authForbidden:
            return .confirmedAuthFailure
        default: return .inconclusive
        }
    }
}
