import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §3.1 (normative — the handoff's minimized-detent content
/// list includes "avatar stack" on equal footing with grabber/title/summary/Locate-now,
/// `HANDOFF.md:151`; 010 deliberately kept it while dropping the handoff's "Drag up for details"
/// hint, a curated inclusion, not an oversight). `RosterAvatarStackPlan` is the pure decision of
/// which initials to show and how many members overflow — `LiveMapScreen`'s and `GroupMapScreen`'s
/// minimized roster headers render whatever this returns. Mirrors Android's
/// `RosterAvatarStackPlanTest.kt` case-for-case, including the cap (4) and overflow semantics.
@MainActor
struct RosterAvatarStackPlanTests {

    @Test func emptyRoster_yieldsNoVisibleAvatarsAndNoOverflow() {
        let plan = RosterAvatarStackPlan.compute(displayNames: [])
        #expect(plan.visibleInitials == [])
        #expect(plan.overflowCount == 0)
    }

    @Test func fewerMembersThanTheMax_showAllOfThemWithNoOverflow() {
        let plan = RosterAvatarStackPlan.compute(displayNames: ["Eric", "Noor"], maxVisible: 4)
        #expect(plan.visibleInitials == ["ER", "NO"])
        #expect(plan.overflowCount == 0)
    }

    @Test func exactlyTheMax_showsAllOfThemWithNoOverflow() {
        let plan = RosterAvatarStackPlan.compute(displayNames: ["Aaa", "Bbb", "Ccc", "Ddd"], maxVisible: 4)
        #expect(plan.visibleInitials == ["AA", "BB", "CC", "DD"])
        #expect(plan.overflowCount == 0)
    }

    @Test func moreMembersThanTheMax_capsVisibleAvatarsAndCountsTheOverflow() {
        let plan = RosterAvatarStackPlan.compute(
            displayNames: ["Eric", "Noor", "Alex", "Sam", "Kai", "Zoe"],
            maxVisible: 4
        )
        #expect(plan.visibleInitials == ["ER", "NO", "AL", "SA"])
        #expect(plan.overflowCount == 2)
    }

    @Test func aBlankDisplayName_rendersANeutralQuestionMark_neverACrash() {
        let plan = RosterAvatarStackPlan.compute(displayNames: ["   "])
        #expect(plan.visibleInitials == ["?"])
        #expect(plan.overflowCount == 0)
    }

    @Test func initials_areTheFirstTwoCharactersUppercased_matchingTheMarkerConvention() {
        #expect(RosterAvatarStackPlan.initialsFor("eric") == "ER")
        #expect(RosterAvatarStackPlan.initialsFor("n") == "N")
        #expect(RosterAvatarStackPlan.initialsFor("") == "?")
    }

    @Test func defaultMaxVisibleIs4() {
        #expect(RosterAvatarStackPlan.maxVisible == 4)
    }
}
