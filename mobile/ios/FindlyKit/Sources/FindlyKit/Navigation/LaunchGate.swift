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
    /// A CONFIRMED `AUTH_MISSING_TOKEN`/`AUTH_INVALID_TOKEN`/`AUTH_TOKEN_EXPIRED`/`AUTH_FORBIDDEN`
    /// (001 §10; specs/010-app-shell-and-screen-ux.md §1.1, amended by row A37) — the backend has
    /// told us the caller is unauthorized. **MUST NOT fail open** — rendering the app shell for a
    /// confirmed-unauthorized caller would just 401 every screen individually, a working-looking
    /// app that fetches nothing. `AppLaunchResolver` clears the local session before this reaches
    /// `LaunchGate`; the table below only decides where it routes.
    case confirmedAuthFailure
    /// Anything else at all: a timeout, a 5xx, or a 401/403 that arrived with **no decodable error
    /// code at all** (a decode failure, an unrecognized code). **MUST fail open to the Family
    /// Map** (010 §1.1) — a blip must never strand a valid user in onboarding, since retrying a GET
    /// can never fix what stranded them there. Distinguishing this from [confirmedAuthFailure] is
    /// by typed error code, never HTTP status alone (010 §1.1's amendment) — see
    /// `AppLaunchResolver.classify`.
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
        // specs/010-app-shell-and-screen-ux.md §1.1 (amended, row A37): a CONFIRMED auth failure
        // is not an inconclusive probe — it MUST route to Sign-in, never fail open to the map.
        // `AppLaunchResolver` clears the session before this destination is applied.
        case .confirmedAuthFailure:
            return .signIn
        }
    }
}
