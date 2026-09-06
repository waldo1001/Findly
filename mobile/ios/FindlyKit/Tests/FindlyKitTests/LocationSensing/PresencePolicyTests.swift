import Testing
@testable import FindlyKit

/// specs/009-device-runtime.md §1.3 (amended 2026-09-06, 000 §D19) — "For `syncIntervalMinutes` ∈
/// {5, 10, 15, 30} a device MUST keep a low-power presence while tracking is enabled and
/// background-location permission is granted"; "Intervals 60, 120 and 1440 keep the original
/// opportunistic path... with NO presence — this is the battery-first option and MUST stay
/// selectable." Pure decision logic, mirroring Android's `PresenceRequirementPolicy`/
/// `SyncStrategySelector` split (here collapsed into one function since iOS has no separate
/// "ideal vs. effective" distinction — When-In-Use is simply not enough, full stop, there is no
/// iOS fallback strategy the way Android falls back to WorkManager).
struct PresencePolicyTests {

    @Test func everyLiveInterval_withAlwaysAndTrackingOn_requiresPresence() {
        for minutes in [5, 10, 15, 30] {
            #expect(PresencePolicy.isRequired(syncIntervalMinutes: minutes, authorization: .always, trackingEnabled: true), "interval \(minutes) should require presence")
        }
    }

    @Test func everyBatterySaverInterval_neverRequiresPresence_evenWithAlwaysAndTrackingOn() {
        for minutes in [60, 120, 1440] {
            #expect(!PresencePolicy.isRequired(syncIntervalMinutes: minutes, authorization: .always, trackingEnabled: true), "interval \(minutes) must stay opportunistic-only")
        }
    }

    @Test func whenInUseAuthorization_neverRequiresPresence_regardlessOfInterval() {
        // §1.3: "background-location permission is granted" — When-In-Use cannot sustain a
        // background session (mirrors BackgroundLocationPolicy's Always-only gates).
        for minutes in [5, 10, 15, 30] {
            #expect(!PresencePolicy.isRequired(syncIntervalMinutes: minutes, authorization: .whenInUse, trackingEnabled: true))
        }
    }

    @Test func notDeterminedOrDeniedAuthorization_neverRequiresPresence() {
        for authorization: LocationAuthorization in [.notDetermined, .denied] {
            #expect(!PresencePolicy.isRequired(syncIntervalMinutes: 15, authorization: authorization, trackingEnabled: true))
        }
    }

    @Test func trackingDisabled_neverRequiresPresence_evenOnALiveIntervalWithAlways() {
        // specs/009 §1.3 closing paragraph: "Presence MUST stop immediately on pause..."
        #expect(!PresencePolicy.isRequired(syncIntervalMinutes: 15, authorization: .always, trackingEnabled: false))
    }
}
