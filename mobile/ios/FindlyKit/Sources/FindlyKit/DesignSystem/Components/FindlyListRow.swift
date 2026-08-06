import SwiftUI

/// specs/004-ios-client.md §2.3 — a generic list row (member, device, geofence, history entry…).
///
/// design 2a "Ember/Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md): min height 60,
/// an optional 40×40 leading avatar circle (initial, `primary` fill for "self" rows, `surfaceVariant`
/// otherwise), title 16/600, subtitle 13/400 in `Theme.onSurfaceMuted`, disabled rows dim to 45%.
public struct FindlyListRow<Trailing: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    private let title: String
    private let subtitle: String?
    private let avatarText: String?
    private let isSelf: Bool
    private let trailing: Trailing

    public init(
        title: String,
        subtitle: String? = nil,
        avatarText: String? = nil,
        isSelf: Bool = false,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.avatarText = avatarText
        self.isSelf = isSelf
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: theme.spacing.md) {
            if let avatarText {
                avatar(initial: avatarText)
            }
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(theme.colors.onSurface)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(theme.onSurfaceMuted)
                }
            }
            Spacer(minLength: theme.spacing.sm)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 60)
        .background(theme.colors.surface)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func avatar(initial: String) -> some View {
        Text(initial)
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(isSelf ? theme.colors.onPrimary : theme.colors.onSurface)
            .frame(width: 40, height: 40)
            .background(isSelf ? theme.colors.primary : theme.colors.surfaceVariant)
            .clipShape(Circle())
    }
}

#Preview("FindlyListRow — light") {
    VStack(spacing: 0) {
        FindlyListRow(title: "Noor", subtitle: "Home · just now", avatarText: "N", isSelf: true) {
            StatusChip("ONLINE", kind: .online)
        }
        FindlyCardDivider()
        FindlyListRow(title: "Sam", subtitle: "Oak Street · 24 min ago", avatarText: "S") {
            StatusChip("STALE", kind: .stale)
        }
        FindlyCardDivider()
        FindlyListRow(title: "Dad", subtitle: "Sharing paused by Dad", avatarText: "D") {
            StatusChip("PAUSED", kind: .paused)
        }
        .disabled(true)
    }
    .padding()
    .background(Theme.light.colors.surface)
    .environment(\.theme, .light)
}

#Preview("FindlyListRow — dark") {
    VStack(spacing: 0) {
        FindlyListRow(title: "Noor", subtitle: "Home · just now", avatarText: "N", isSelf: true) {
            StatusChip("ONLINE", kind: .online)
        }
        FindlyCardDivider()
        FindlyListRow(title: "Sam", subtitle: "Oak Street · 24 min ago", avatarText: "S") {
            StatusChip("STALE", kind: .stale)
        }
    }
    .padding()
    .background(Theme.dark.colors.surface)
    .environment(\.theme, .dark)
    .preferredColorScheme(.dark)
}
