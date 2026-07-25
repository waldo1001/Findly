import SwiftUI

/// specs/004-ios-client.md §2.3 — a recoverable-error state with an optional retry action.
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
            Text(message)
                .font(theme.typography.bodyMedium)
                .foregroundColor(theme.colors.danger)
                .multilineTextAlignment(.center)
            if let onRetry {
                FindlyButton(retryTitle, style: .secondary, action: onRetry)
            }
        }
        .padding(theme.spacing.xl)
    }
}

// #Preview blocks intentionally omitted: this session's build/test verification environment has
// only Xcode Command Line Tools (no Xcode.app), which lacks the `PreviewsMacros` compiler plugin
// `#Preview` needs — even an empty `#Preview {}` fails to compile here. Adding light/dark previews
// back is a trivial, non-blocking follow-up once a real Xcode toolchain is available (see
// specs/004-ios-client.md §2.3); the package must build clean in THIS environment first.
