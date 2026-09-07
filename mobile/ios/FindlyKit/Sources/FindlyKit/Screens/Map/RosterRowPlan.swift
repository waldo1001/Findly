import Foundation

/// specs/010-app-shell-and-screen-ux.md §3.1 (I48, part 2) — the pure decision of what rows (and
/// inter-row dividers) a single member's devices produce inside the Family Map's roster: one
/// `FindlyListRow` per device (or exactly one "no devices" row when a member has none), with a
/// divider between a member's own device rows.
///
/// Before I48, `LiveMapScreen.memberRow` (rendering) and `LiveMapScreen.sheetStandardHeight`
/// (sizing, via `FindlyBottomSheetHeightPlanning.standardHeight`'s `rowCount`/`dividerCount`
/// parameters) each independently re-derived this shape from `member.devices`, kept in agreement
/// only by a doc comment claiming the two were "meant to be edited together". A reviewer traced
/// both and confirmed they matched at the time — but nothing enforced it: a future edit to either
/// side would drift silently, since `FindlyBottomSheetHeightPlanningTests` only exercises the pure
/// arithmetic with hand-supplied counts, not the real member/device shape.
///
/// `RosterRowPlan` closes that by being the ONE place the shape is decided: both `memberRow` and
/// `sheetStandardHeight` now build a plan for a given member's `devices` and read `rows`/
/// `interRowDividerCount` from it, rather than each re-deriving the shape from `member.devices`
/// itself. There is no longer a second source to drift out of sync — a shape change here is a
/// change both consumers see automatically, because both consume this type's output rather than
/// their own copy of the logic that produces it.
public struct RosterRowPlan: Equatable {
    public struct Row: Equatable {
        /// `nil` for the synthetic "no devices registered" row shown when a member has no devices.
        public let device: DeviceLocation?
        /// The first row in a member's block shows the member's own display name as its title;
        /// subsequent device rows show that device's own name instead (`LiveMapScreen.memberRow`'s
        /// pre-I48 `index == 0` check).
        public let isFirst: Bool
    }

    public let rows: [Row]

    /// Dividers BETWEEN this member's own rows only. The divider that follows the ENTIRE block —
    /// separating one member from the next — is `fullRoster`'s own unconditional
    /// `FindlyCardDivider()` after every member; that one is already a direct 1:1 with
    /// `members.count` on both the rendering and sizing sides, so it was never a second,
    /// independently-derived count at risk of drifting, and this type deliberately doesn't own it.
    public var interRowDividerCount: Int { max(0, rows.count - 1) }

    public static func compute(devices: [DeviceLocation]) -> RosterRowPlan {
        guard !devices.isEmpty else {
            return RosterRowPlan(rows: [Row(device: nil, isFirst: true)])
        }
        let rows = devices.enumerated().map { index, device in Row(device: device, isFirst: index == 0) }
        return RosterRowPlan(rows: rows)
    }
}
