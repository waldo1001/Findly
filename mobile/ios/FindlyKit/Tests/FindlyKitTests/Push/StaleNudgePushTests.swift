import Testing
@testable import FindlyKit

/// specs/011 §4.4; specs/009 §5.6; 001 §8.8 — `STALE_NUDGE` is a visible OS-rendered push: parsed as
/// its own type, never runs a data handler, and its banner is suppressed while foregrounded.
struct StaleNudgePushTests {
    @Test func staleNudge_parses() {
        #expect(PushMessageType.from(["type": "STALE_NUDGE"]) == .staleNudge)
    }

    @Test func foreground_staleNudge_isSuppressed() {
        #expect(ForegroundPresentationPolicy.decision(for: ["type": "STALE_NUDGE"]) == .suppress)
    }

    @Test func foreground_otherTypes_andUnknown_stillShowBannerAndSound() {
        for type in ["GEOFENCE_EVENT", "LOCATE_REQUEST", "SETTINGS_CHANGED", "SOMETHING_NEW"] {
            #expect(ForegroundPresentationPolicy.decision(for: ["type": type]) == .bannerAndSound)
        }
        #expect(ForegroundPresentationPolicy.decision(for: [:]) == .bannerAndSound)
    }
}
