import SwiftUI

/// specs/004-ios-client.md §2.3.
///
/// design 2a "Ember/Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md), shared geometry
/// with Empty/Error: radius `lg`, fill `surfaceVariant`, 22pt padding. A 6pt bar in `primary` on a
/// `surface` track — determinate when `progress` is supplied, indeterminate otherwise.
public struct LoadingStateView: View {
    @Environment(\.theme) private var theme
    private let message: String
    private let progress: Double?

    public init(message: String = "Loading…", progress: Double? = nil) {
        self.message = message
        self.progress = progress
    }

    public var body: some View {
        VStack(spacing: theme.spacing.sm) {
            progressBar
            Text(message)
                .font(theme.typography.bodyMedium.font)
                .foregroundColor(theme.onSurfaceMuted)
        }
        .padding(22)
        .background(theme.colors.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: theme.corner.lg))
    }

    @ViewBuilder
    private var progressBar: some View {
        if let progress {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(theme.colors.primary)
                .background(theme.colors.surface)
                .frame(height: 6)
                .clipShape(Capsule())
        } else {
            ProgressView()
                .tint(theme.colors.primary)
        }
    }
}

#Preview("LoadingStateView — light") {
    VStack(spacing: 16) {
        LoadingStateView(message: "Asking Sam's Pixel…")
        LoadingStateView(message: "Exporting…", progress: 0.6)
    }
    .padding()
    .background(Theme.light.colors.surface)
    .environment(\.theme, .light)
}

#Preview("LoadingStateView — dark") {
    VStack(spacing: 16) {
        LoadingStateView(message: "Asking Sam's Pixel…")
        LoadingStateView(message: "Exporting…", progress: 0.6)
    }
    .padding()
    .background(Theme.dark.colors.surface)
    .environment(\.theme, .dark)
    .preferredColorScheme(.dark)
}
