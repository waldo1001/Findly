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
    public static func resolve(
        apiClient: FindlyAPIClient,
        isSignedIn: Bool,
        cache: FamilyContextCache? = nil
    ) async -> LaunchDestination {
        guard isSignedIn else { return .signIn }
        let probe = await probeProfile(apiClient: apiClient, cache: cache)
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

    /// specs/010 §1.1 — only a CONFIRMED 404 routes away from the Family Map; everything else
    /// (timeout, 5xx, a transient 401, a decode failure, an as-yet-unrecognized code) fails open.
    static func classify(_ error: Error) -> ProfileProbeOutcome {
        switch (error as? APIError)?.serverCode {
        case .profileNotFound: return .confirmedNoProfile
        case .familyNotFound: return .confirmedNoFamily
        default: return .inconclusive
        }
    }
}
