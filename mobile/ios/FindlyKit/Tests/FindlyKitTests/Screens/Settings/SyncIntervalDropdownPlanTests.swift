import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §4.2, specs/001-api-contract.md §1.4/§9 — the pure logic
/// behind the Devices screen's sync-interval `FindlyDropdownField`. `CLAUDE.md` is explicit that
/// every limit is read from `features` (`PLAN_MATRIX`-derived), never hardcoded at a call site, so
/// this type takes the floor as a parameter and asserts nothing about what its value should be.
@MainActor
struct SyncIntervalDropdownPlanTests {

    @Test func allowedMinutes_isExactlyThe001Section1_4Set_inAscendingOrder() {
        #expect(SyncIntervalDropdownPlan.allowedMinutes == [5, 10, 15, 30, 60, 120, 1440])
    }

    @Test func label_matchesTheExact001Section4_2Wording() {
        #expect(SyncIntervalDropdownPlan.label(for: 5) == "5 min")
        #expect(SyncIntervalDropdownPlan.label(for: 10) == "10 min")
        #expect(SyncIntervalDropdownPlan.label(for: 15) == "15 min")
        #expect(SyncIntervalDropdownPlan.label(for: 30) == "30 min")
        #expect(SyncIntervalDropdownPlan.label(for: 60) == "1 hour")
        #expect(SyncIntervalDropdownPlan.label(for: 120) == "2 hours")
        #expect(SyncIntervalDropdownPlan.label(for: 1440) == "1 day")
    }

    @Test func floorAtTheLowestAllowedValue_enablesEveryOption() {
        let options = SyncIntervalDropdownPlan.options(minSyncIntervalMinutes: 5)

        #expect(options.map(\.value) == SyncIntervalDropdownPlan.allowedMinutes)
        #expect(options.allSatisfy { $0.isEnabled })
        #expect(options.allSatisfy { $0.disabledReason == nil })
    }

    @Test func floorAbove10_disablesOnly5And10_withANonNilReasonNamingTheFloor() {
        let options = SyncIntervalDropdownPlan.options(minSyncIntervalMinutes: 15)

        let byValue = Dictionary(uniqueKeysWithValues: options.map { ($0.value, $0) })
        #expect(byValue[5]?.isEnabled == false)
        #expect(byValue[10]?.isEnabled == false)
        #expect(byValue[15]?.isEnabled == true)
        #expect(byValue[30]?.isEnabled == true)
        #expect(byValue[60]?.isEnabled == true)
        #expect(byValue[120]?.isEnabled == true)
        #expect(byValue[1440]?.isEnabled == true)

        #expect(byValue[5]?.disabledReason?.contains("15 min") == true)
        #expect(byValue[10]?.disabledReason?.contains("15 min") == true)
        #expect(byValue[15]?.disabledReason == nil)
    }

    @Test func aHarshFloor_disablesEverythingBelowIt_leavingOnlyTheTopValueEnabled() {
        let options = SyncIntervalDropdownPlan.options(minSyncIntervalMinutes: 1440)

        let byValue = Dictionary(uniqueKeysWithValues: options.map { ($0.value, $0) })
        for minutes in [5, 10, 15, 30, 60, 120] {
            #expect(byValue[minutes]?.isEnabled == false, "\(minutes) should be disabled below the 1440 floor")
        }
        #expect(byValue[1440]?.isEnabled == true)
    }

    @Test func titlesMatchTheLabelFormatter_forEveryOption() {
        let options = SyncIntervalDropdownPlan.options(minSyncIntervalMinutes: 5)
        for option in options {
            #expect(option.title == SyncIntervalDropdownPlan.label(for: option.value))
        }
    }
}
