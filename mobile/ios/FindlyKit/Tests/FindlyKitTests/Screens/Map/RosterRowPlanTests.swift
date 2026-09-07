import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §3.1 (I48, part 2) — `RosterRowPlan` is the pure decision
/// of what rows (and inter-row dividers) a single member's devices produce inside the Family Map's
/// roster: one `FindlyListRow` per device (or exactly one "no devices" row when there are none),
/// with a divider between a member's own device rows.
///
/// Before I48, `LiveMapScreen.memberRow` (rendering) and `LiveMapScreen.sheetStandardHeight`
/// (sizing) each independently re-derived this shape from `member.devices`, kept in agreement only
/// by a doc comment claiming they were "meant to be edited together". A reviewer traced both and
/// confirmed they matched — but nothing enforced it: `FindlyBottomSheetHeightPlanningTests` only
/// exercises the pure formula with hand-supplied counts, so a future edit to either side would have
/// drifted silently and the sheet would mis-size with no test failing. `RosterRowPlan` closes that:
/// both `memberRow` and `sheetStandardHeight` now build and read the SAME plan for the SAME member,
/// so there is exactly one place the shape is decided.
@MainActor
struct RosterRowPlanTests {

    private func device(_ id: String) -> DeviceLocation {
        DeviceLocation(
            deviceId: id, deviceName: "Device \(id)", lat: nil, lon: nil, accuracyM: nil,
            recordedAt: nil, receivedAt: nil, batteryPct: nil, source: nil,
            trackingEnabled: true, syncIntervalMinutes: 15, isStale: nil
        )
    }

    @Test func noDevices_yieldsExactlyOneSyntheticRow_andNoDividers() {
        let plan = RosterRowPlan.compute(devices: [])
        #expect(plan.rows.count == 1)
        #expect(plan.rows[0].device == nil)
        #expect(plan.rows[0].isFirst == true)
        #expect(plan.interRowDividerCount == 0)
    }

    @Test func oneDevice_yieldsExactlyOneRowForIt_markedFirst_andNoDividers() {
        let plan = RosterRowPlan.compute(devices: [device("a")])
        #expect(plan.rows.count == 1)
        #expect(plan.rows[0].device == device("a"))
        #expect(plan.rows[0].isFirst == true)
        #expect(plan.interRowDividerCount == 0)
    }

    @Test func multipleDevices_yieldsOneRowEach_onlyTheFirstMarkedFirst_dividersBetweenNotAfter() {
        let devices = [device("a"), device("b"), device("c")]
        let plan = RosterRowPlan.compute(devices: devices)

        #expect(plan.rows.count == 3)
        #expect(plan.rows.compactMap { $0.device } == devices)
        #expect(plan.rows.map { $0.isFirst } == [true, false, false])
        // 3 rows -> 2 dividers BETWEEN them; the divider that follows the whole member block is
        // `fullRoster`'s own separate, unconditional one (not this plan's concern — see its doc).
        #expect(plan.interRowDividerCount == 2)
    }

    @Test func interRowDividerCount_isAlwaysRowCountMinusOne_neverNegative() {
        #expect(RosterRowPlan.compute(devices: []).interRowDividerCount == 0)
        #expect(RosterRowPlan.compute(devices: [device("a")]).interRowDividerCount == 0)
        #expect(RosterRowPlan.compute(devices: [device("a"), device("b")]).interRowDividerCount == 1)
    }
}
