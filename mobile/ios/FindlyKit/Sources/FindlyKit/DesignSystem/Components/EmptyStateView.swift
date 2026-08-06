import SwiftUI

/// specs/004-ios-client.md §2.3 — the "nothing here yet" state (e.g. no devices, no geofences).
///
/// design 2a "Ember/Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md), shared geometry
/// for Empty/Loading/Error: radius `lg`, fill `surfaceVariant`, 22pt padding, title 18/600, body
/// 15/400 at ~1.5x line height in `Theme.onSurfaceMuted`, a single optional action.
public struct EmptyStateView: View {
    @Environment(\.theme) private var theme
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let onAction: (() -> Void)?

    public init(title: String, message: String, actionTitle: String? = nil, onAction: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.onAction = onAction
    }

    public var body: some View {
        VStack(spacing: theme.spacing.sm) {
            Text(title)
                .font(theme.typography.titleMedium.font)
                .foregroundColor(theme.colors.onSurface)
            Text(message)
                .font(theme.typography.bodyMedium.font)
                // 15pt body at a ~1.5x (22.5pt) line height — `.lineSpacing` adds the *extra*
                // space SwiftUI has no direct "line height" primitive for.
                .lineSpacing(theme.typography.bodyMedium.size * 1.5 - theme.typography.bodyMedium.size)
                .foregroundColor(theme.onSurfaceMuted)
                .multilineTextAlignment(.center)
            if let actionTitle, let onAction {
                FindlyButton(actionTitle, style: .secondary, action: onAction)
                    .padding(.top, theme.spacing.xs)
            }
        }
        .padding(22)
        .background(theme.colors.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: theme.corner.lg))
    }
}

#Preview("EmptyStateView — light") {
    EmptyStateView(title: "No devices yet", message: "No devices added", actionTitle: "Invite") {}
        .padding()
        .background(Theme.light.colors.surface)
        .environment(\.theme, .light)
}

#Preview("EmptyStateView — dark") {
    EmptyStateView(title: "No devices yet", message: "No devices added", actionTitle: "Invite") {}
        .padding()
        .background(Theme.dark.colors.surface)
        .environment(\.theme, .dark)
        .preferredColorScheme(.dark)
}
