import SwiftUI

/// specs/004-ios-client.md §2.3 — a generic elevated surface container.
///
/// design 2a "Ember/Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md): radius `md`,
/// fill `surfaceVariant`, **no border, no shadow**. Cards are containers for rows; when the
/// content is a list of `FindlyListRow`s the caller separates them with a 1px `outline` divider
/// (`FindlyCard.divider`), not a gap — `FindlyCard` itself stays a plain generic container since
/// it has no way to see how many rows its content closure produces.
public struct FindlyCard<Content: View>: View {
    @Environment(\.theme) private var theme
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(theme.spacing.md)
            .background(theme.colors.surfaceVariant)
            .clipShape(RoundedRectangle(cornerRadius: theme.corner.md))
    }
}

/// The 1px hairline that separates rows inside a `FindlyCard`. Decorative (row separation carries
/// no state), so the plain, lower-contrast `outline` token is correct here — not `outlineStrong`.
/// A top-level type (not nested in `FindlyCard`) because a type nested under a generic struct
/// forces every call site to specify that struct's generic parameter to use it.
public struct FindlyCardDivider: View {
    @Environment(\.theme) private var theme
    public init() {}
    public var body: some View {
        Rectangle()
            .fill(theme.colors.outline)
            .frame(height: 1)
    }
}

#Preview("FindlyCard — light") {
    FindlyCard {
        VStack(spacing: 0) {
            FindlyListRow(title: "Noor", subtitle: "Home · just now")
            FindlyCardDivider()
            FindlyListRow(title: "Sam", subtitle: "Oak Street · 24 min ago")
        }
    }
    .padding()
    .background(Theme.light.colors.surface)
    .environment(\.theme, .light)
}

#Preview("FindlyCard — dark") {
    FindlyCard {
        VStack(spacing: 0) {
            FindlyListRow(title: "Noor", subtitle: "Home · just now")
            FindlyCardDivider()
            FindlyListRow(title: "Sam", subtitle: "Oak Street · 24 min ago")
        }
    }
    .padding()
    .background(Theme.dark.colors.surface)
    .environment(\.theme, .dark)
    .preferredColorScheme(.dark)
}
