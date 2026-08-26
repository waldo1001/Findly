import Foundation

/// specs/010-app-shell-and-screen-ux.md §1.1 — the launch-resolution table, extracted as a pure,
/// platform-agnostic component out of the deleted Home hub (which used to run its own probe from
/// `HomeViewModel.load()`, and only for the cold-start-restore path — an interactive sign-in went
/// straight to `.home` unconditionally, so a brand-new phone-auth signup with no profile yet used
/// to land on Home's OWN internal `.profileless` branch rather than being routed anywhere). Both
/// entry points (cold-start restore, 004 §2.6; interactive sign-in, 004 §4.1) now resolve through
/// this exact same table via `AppLaunchResolver`.
///
/// **Never a network type.** The probe outcome is classified by the caller (`AppLaunchResolver`,
/// which owns the `FindlyAPIClient` call and the `APIError` → outcome mapping) so this table itself
/// stays trivially, exhaustively unit-testable with no fake client, no async, no `Error` fixtures.
public enum ProfileProbeOutcome: Equatable, Sendable {
    /// `GET /families/me` succeeded — profile AND family both confirmed to exist.
    case confirmed
    /// A CONFIRMED `404 PROFILE_NOT_FOUND` (001 §1.5.3) — no `Users` profile row at all.
    case confirmedNoProfile
    /// A CONFIRMED `404 FAMILY_NOT_FOUND` (001 §1.5.4) — profile exists, `familyId` is null.
    case confirmedNoFamily
    /// Anything else at all: a timeout, a 5xx, a transient 401, a decode failure, an unrecognized
    /// error code. **MUST fail open to the Family Map** (010 §1.1) — a blip must never strand a
    /// valid user in onboarding, since retrying a GET can never fix what stranded them there.
    case inconclusive
}

public enum LaunchDestination: Equatable, Sendable {
    case signIn
    case familyMap
    case onboarding(OnboardingVariant)
}

/// Pure table lookup — no I/O, no `Error` type in its signature at all.
public enum LaunchGate {
    /// specs/010 §1.1's table, row by row:
    /// | Signed-in state | Root screen |
    /// | Not signed in | Sign-in |
    /// | profile + family | Family Map |
    /// | no profile | Onboarding (profile-less) |
    /// | profile, no family | Onboarding (family-less) |
    /// plus the fail-open rule: an inconclusive probe resolves exactly like a confirmed one.
    public static func resolve(isSignedIn: Bool, probe: ProfileProbeOutcome) -> LaunchDestination {
        guard isSignedIn else { return .signIn }
        switch probe {
        case .confirmed, .inconclusive:
            return .familyMap
        case .confirmedNoProfile:
            return .onboarding(.profileLess)
        case .confirmedNoFamily:
            return .onboarding(.familyLess)
        }
    }
}
