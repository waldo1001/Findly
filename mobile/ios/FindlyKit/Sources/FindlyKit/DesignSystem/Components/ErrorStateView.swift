import SwiftUI

/// specs/004-ios-client.md §2.3 — a recoverable-error state with an optional retry action.
///
/// design 2a "Ember/Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md), shared geometry
/// with Empty/Loading: radius `lg`, fill `surfaceVariant`, 22pt padding. Leads with `▲` in
/// `warning` rather than a red icon — "not red — an unreachable device is not an error state for
/// the user" — a calm, reassuring tone even for genuinely broken states (the handoff's stated
/// emotional tone: "calm, warm, trustworthy... not a surveillance dashboard"). `danger` stays
/// reserved for destructive confirmations elsewhere. "Raw server text never reaches the screen" is
/// a view-model concern (`message` here is always caller-composed, human copy already).
public struct ErrorStateView: View {
    @Environment(\.theme) private var theme
    private let message: String
    private let retryTitle: String
    private let onRetry: (() -> Void)?

    public init(message: String, retryTitle: String = "Retry", onRetry: (() -> Void)? = nil) {
        self.message = message
        self.retryTitle = retryTitle
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(spacing: theme.spacing.md) {
            HStack(alignment: .top, spacing: theme.spacing.xs) {
                Text("▲")
                    .foregroundColor(theme.colors.warning)
                Text(message)
                    .foregroundColor(theme.colors.onSurface)
            }
            .font(theme.typography.bodyMedium.font)
            .multilineTextAlignment(.leading)
            if let onRetry {
                FindlyButton(retryTitle, style: .secondary, action: onRetry)
            }
        }
        .padding(22)
        .background(theme.colors.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: theme.corner.lg))
    }
}

#Preview("ErrorStateView — light") {
    ErrorStateView(message: "We couldn't reach Sam's Pixel. It may be off or out of signal.", retryTitle: "Try again") {}
        .padding()
        .background(Theme.light.colors.surface)
        .environment(\.theme, .light)
}

#Preview("ErrorStateView — dark") {
    ErrorStateView(message: "We couldn't reach Sam's Pixel. It may be off or out of signal.", retryTitle: "Try again") {}
        .padding()
        .background(Theme.dark.colors.surface)
        .environment(\.theme, .dark)
        .preferredColorScheme(.dark)
}
