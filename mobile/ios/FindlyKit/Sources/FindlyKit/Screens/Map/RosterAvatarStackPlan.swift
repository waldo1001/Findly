import Foundation

/// specs/010-app-shell-and-screen-ux.md §3.1 (normative — the `FindlyBottomSheet` minimized
/// detent's content list; `HANDOFF.md:151` lists "avatar stack" on equal footing with grabber/
/// title/summary/Locate-now, and 010 deliberately kept it while dropping the handoff's "Drag up
/// for details" hint — a curated inclusion, not an oversight). Pure decision of which members'
/// initials to show and how many overflow, shared by `LiveMapScreen`'s minimized roster header and
/// `GroupMapScreen`'s — both already carry `displayName` (no new data needed). Mirrors Android's
/// `RosterAvatarStackPlan.kt` exactly (same cap, same overflow semantics): §10 requires
/// cross-platform parity for the SAME normative element, not an independently-chosen number.
public enum RosterAvatarStackPlan {
    public static let maxVisible = 4

    public struct Plan: Equatable {
        public let visibleInitials: [String]
        public let overflowCount: Int

        public init(visibleInitials: [String], overflowCount: Int) {
            self.visibleInitials = visibleInitials
            self.overflowCount = overflowCount
        }
    }

    public static func compute(displayNames: [String], maxVisible: Int = RosterAvatarStackPlan.maxVisible) -> Plan {
        let visible = displayNames.prefix(maxVisible).map(initialsFor)
        let overflow = max(displayNames.count - visible.count, 0)
        return Plan(visibleInitials: Array(visible), overflowCount: overflow)
    }

    /// Same short-label convention as `LiveMapViewModel.initials(for:)`/`GroupMapViewModel.initials(for:)`
    /// and Android's `GoogleMapRenderer.kt`'s marker-bubble `initialsFor`.
    public static func initialsFor(_ displayName: String) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }
        return String(trimmed.prefix(2)).uppercased()
    }
}
