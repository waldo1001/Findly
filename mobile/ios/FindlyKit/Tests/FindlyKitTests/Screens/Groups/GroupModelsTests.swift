import Foundation
import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §3.4 — the pure, presentation-adjacent helpers `GroupsListScreen` and
/// `CreateGroupScreen` render from: the 005 §2.1 policy copy, the state→chip mapping, and the
/// `endsAt` countdown text. None of these touch `DesignSystem` directly (no `Color`/`Font`), so
/// they're plain-value unit tests, same shape as `MapModels`'s.
struct GroupExpiryPolicyTests {

    @Test func policyCopy_matchesSpec005Verbatim() {
        // specs/005-temporary-groups.md §2.1 — clients MUST show this verbatim at creation.
        #expect(GroupExpiryPolicy.delete.policyCopy == "When the group ends, everything about it disappears.")
        #expect(GroupExpiryPolicy.grace.policyCopy == "When the group ends it goes read-only for a few days so the owner can revive it; then everything disappears.")
        #expect(GroupExpiryPolicy.archive.policyCopy == "When the group ends, everyone's locations are deleted; the member list stays as a keepsake.")
    }

    @Test func rawValue_matchesWireFormat() {
        // specs/001 §12.1 — expiryPolicy ∈ {delete, grace, archive}, sent verbatim on the wire.
        #expect(GroupExpiryPolicy.delete.rawValue == "delete")
        #expect(GroupExpiryPolicy.grace.rawValue == "grace")
        #expect(GroupExpiryPolicy.archive.rawValue == "archive")
    }

    @Test func allCases_listsAllThreePolicies() {
        #expect(GroupExpiryPolicy.allCases == [.delete, .grace, .archive])
    }
}

struct GroupStateChipTests {

    @Test func kind_active_isOnline() {
        #expect(GroupStateChip.kind(for: "active") == .online)
    }

    @Test func kind_ended_isStale() {
        // "ended" = the grace-policy read-only window (005 §2.2) — rendered like a stale device,
        // not a hard failure.
        #expect(GroupStateChip.kind(for: "ended") == .stale)
    }

    @Test func kind_archived_isPaused() {
        #expect(GroupStateChip.kind(for: "archived") == .paused)
    }

    @Test func kind_unknownState_defaultsToPaused() {
        #expect(GroupStateChip.kind(for: "something-unexpected") == .paused)
    }

    @Test func label_capitalizesEachKnownState() {
        #expect(GroupStateChip.label(for: "active") == "Active")
        #expect(GroupStateChip.label(for: "ended") == "Ended")
        #expect(GroupStateChip.label(for: "archived") == "Archived")
    }
}

struct GroupCountdownTests {
    private let iso = ISO8601DateFormatter()

    @Test func text_daysAndHoursRemaining() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let endsAt = now.addingTimeInterval(3 * 86400 + 4 * 3600)
        #expect(GroupCountdown.text(from: iso.string(from: endsAt), now: now) == "Ends in 3d 4h")
    }

    @Test func text_exactDaysNoHours() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let endsAt = now.addingTimeInterval(5 * 86400)
        #expect(GroupCountdown.text(from: iso.string(from: endsAt), now: now) == "Ends in 5d")
    }

    @Test func text_hoursAndMinutesRemaining() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let endsAt = now.addingTimeInterval(2 * 3600 + 15 * 60)
        #expect(GroupCountdown.text(from: iso.string(from: endsAt), now: now) == "Ends in 2h 15m")
    }

    @Test func text_minutesOnly() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let endsAt = now.addingTimeInterval(45 * 60)
        #expect(GroupCountdown.text(from: iso.string(from: endsAt), now: now) == "Ends in 45m")
    }

    @Test func text_pastEndsAt_returnsEnded() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let endsAt = now.addingTimeInterval(-3600)
        #expect(GroupCountdown.text(from: iso.string(from: endsAt), now: now) == "Ended")
    }

    @Test func text_exactlyAtEndsAt_returnsEnded() {
        // state() edge (005 §2.2): `now >= endsAt` is already non-active — the boundary itself
        // must read as "Ended", not "Ends in 0m".
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(GroupCountdown.text(from: iso.string(from: now), now: now) == "Ended")
    }

    @Test func text_unparseableString_returnsEmptyRatherThanCrashing() {
        #expect(GroupCountdown.text(from: "not-a-date", now: Date()) == "")
    }
}
