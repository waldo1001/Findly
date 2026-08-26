import SwiftUI

/// specs/010-app-shell-and-screen-ux.md §3.1's roster-header avatar stack — shared by
/// `LiveMapScreen`'s minimized roster header and `GroupMapScreen`'s (both already carry
/// `displayName`; no new data needed). Not a `DesignSystem/Components` type (the batch's three
/// new named components are `FindlyNavDrawer`/`FindlyBottomSheet`/`FindlyDropdownField` only) —
/// same "screen-level composition, theme tokens applied directly" precedent as this file's other
/// one-off chrome, and the same split Android uses (`RosterAvatarStackPlan.kt` pure, the
/// `RosterAvatarStack` composable colocated with the screens that render it).
///
/// Renders `RosterAvatarStackPlan`'s decision with existing theme tokens only —
/// `primary`/`onPrimary` for a member's initials circle (the same pair `MapMarkerBubble`'s
/// online-marker avatar circle uses), `surfaceVariant`/`onSurface` for the overflow "+N" circle,
/// `surface` as the separating border between overlapping circles (the sheet's own background) —
/// no new token names. Internal (not `public`): both call sites live in this module.
struct RosterAvatarStack: View {
    @Environment(\.theme) private var theme
    let displayNames: [String]

    var body: some View {
        if !displayNames.isEmpty {
            let plan = RosterAvatarStackPlan.compute(displayNames: displayNames)
            HStack(spacing: 0) {
                ForEach(Array(plan.visibleInitials.enumerated()), id: \.offset) { index, initials in
                    avatarCircle(text: initials, fill: theme.colors.primary, textColor: theme.colors.onPrimary)
                        .offset(x: CGFloat(index) * -8)
                }
                if plan.overflowCount > 0 {
                    avatarCircle(text: "+\(plan.overflowCount)", fill: theme.colors.surfaceVariant, textColor: theme.colors.onSurface)
                        .offset(x: CGFloat(plan.visibleInitials.count) * -8)
                }
            }
        }
    }

    private func avatarCircle(text: String, fill: Color, textColor: Color) -> some View {
        Text(text)
            .font(theme.typography.labelSmall.font)
            .foregroundColor(textColor)
            .frame(width: 32, height: 32)
            .background(fill)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(theme.colors.surface, lineWidth: 2))
    }
}
