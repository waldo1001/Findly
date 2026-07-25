import SwiftUI

/// specs/004-ios-client.md §2.3 — a family member's position bubble on the live map (I2 consumes
/// this; the shape ships now as part of the design-system contract).
public struct MapMarkerBubble: View {
    @Environment(\.theme) private var theme
    private let initials: String
    private let isStale: Bool

    public init(initials: String, isStale: Bool = false) {
        self.initials = initials
        self.isStale = isStale
    }

    public var body: some View {
        Text(initials)
            .font(theme.typography.labelSmall)
            .foregroundColor(theme.colors.onPrimary)
            .padding(theme.spacing.sm)
            .background(isStale ? theme.colors.outline : theme.colors.primary)
            .clipShape(Circle())
            .shadow(
                color: theme.colors.onSurface.opacity(theme.elevation.level2.opacity),
                radius: theme.elevation.level2.radius,
                y: theme.elevation.level2.y
            )
    }
}

// #Preview blocks intentionally omitted: this session's build/test verification environment has
// only Xcode Command Line Tools (no Xcode.app), which lacks the `PreviewsMacros` compiler plugin
// `#Preview` needs — even an empty `#Preview {}` fails to compile here. Adding light/dark previews
// back is a trivial, non-blocking follow-up once a real Xcode toolchain is available (see
// specs/004-ios-client.md §2.3); the package must build clean in THIS environment first.
