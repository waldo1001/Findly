import SwiftUI

/// specs/004-ios-client.md §2.3 — e.g. a device's live/stale/paused state (001 §5.2 `isStale`,
/// §5.1 `trackingEnabled`).
public enum StatusChipKind: Equatable {
    case online
    case stale
    case paused
}

public struct StatusChip: View {
    @Environment(\.theme) private var theme
    private let text: String
    private let kind: StatusChipKind

    public init(_ text: String, kind: StatusChipKind) {
        self.text = text
        self.kind = kind
    }

    public var body: some View {
        Text(text)
            .font(theme.typography.labelSmall)
            .padding(.horizontal, theme.spacing.sm)
            .padding(.vertical, theme.spacing.xs)
            .background(backgroundColor)
            .foregroundColor(theme.colors.onPrimary)
            .clipShape(RoundedRectangle(cornerRadius: theme.corner.pill))
    }

    private var backgroundColor: Color {
        switch kind {
        case .online: return theme.colors.success
        case .stale: return theme.colors.warning
        case .paused: return theme.colors.outline
        }
    }
}

// #Preview blocks intentionally omitted: this session's build/test verification environment has
// only Xcode Command Line Tools (no Xcode.app), which lacks the `PreviewsMacros` compiler plugin
// `#Preview` needs — even an empty `#Preview {}` fails to compile here. Adding light/dark previews
// back is a trivial, non-blocking follow-up once a real Xcode toolchain is available (see
// specs/004-ios-client.md §2.3); the package must build clean in THIS environment first.
