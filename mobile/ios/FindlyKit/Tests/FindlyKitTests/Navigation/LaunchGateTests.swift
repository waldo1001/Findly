import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §1.1 — the pure launch-resolution table, extracted out of
/// the deleted Home hub so both cold-start restore and interactive sign-in resolve identically.
/// Table-driven per the 010 §10 test checklist: every row of §1.1's table, plus the fail-open rule
/// for an inconclusive probe.
struct LaunchGateTests {

    @Test func notSignedIn_alwaysRoutesToSignIn_regardlessOfProbe() {
        #expect(LaunchGate.resolve(isSignedIn: false, probe: .confirmed) == .signIn)
        #expect(LaunchGate.resolve(isSignedIn: false, probe: .confirmedNoProfile) == .signIn)
        #expect(LaunchGate.resolve(isSignedIn: false, probe: .confirmedNoFamily) == .signIn)
        #expect(LaunchGate.resolve(isSignedIn: false, probe: .confirmedAuthFailure) == .signIn)
        #expect(LaunchGate.resolve(isSignedIn: false, probe: .inconclusive) == .signIn)
    }

    @Test func signedIn_confirmedProfileAndFamily_routesToFamilyMap() {
        #expect(LaunchGate.resolve(isSignedIn: true, probe: .confirmed) == .familyMap)
    }

    @Test func signedIn_confirmedNoProfile_routesToProfileLessOnboarding() {
        #expect(LaunchGate.resolve(isSignedIn: true, probe: .confirmedNoProfile) == .onboarding(.profileLess))
    }

    @Test func signedIn_confirmedNoFamily_routesToFamilyLessOnboarding() {
        #expect(LaunchGate.resolve(isSignedIn: true, probe: .confirmedNoFamily) == .onboarding(.familyLess))
    }

    /// The rule this whole component exists to enforce: a blip (timeout, 5xx, transient 401, decode
    /// failure) must NEVER strand a valid user in onboarding, since retrying a GET cannot fix
    /// whatever caused it. Only a CONFIRMED 404 may route away from the map.
    @Test func signedIn_inconclusiveProbe_failsOpenToFamilyMap() {
        #expect(LaunchGate.resolve(isSignedIn: true, probe: .inconclusive) == .familyMap)
    }

    /// specs/010-app-shell-and-screen-ux.md §1.1 (amended, row A37): a CONFIRMED auth failure is
    /// NOT an inconclusive probe — it MUST route to Sign-in, never fail open to the map. This is
    /// the one row the pre-amendment table had no answer for at all.
    @Test func signedIn_confirmedAuthFailure_routesToSignIn() {
        #expect(LaunchGate.resolve(isSignedIn: true, probe: .confirmedAuthFailure) == .signIn)
    }
}
