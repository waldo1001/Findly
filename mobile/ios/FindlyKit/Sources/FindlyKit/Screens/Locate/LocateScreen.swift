import SwiftUI

/// specs/004-ios-client.md I2 (001 §6) — composes ONLY design-system components. Kicks off a
/// locate request on appear and cancels the poll loop on disappear (`onDisappear`).
public struct LocateScreen: View {
    @Environment(\.theme) private var theme
    // `@StateObject`, NOT `@ObservedObject` — see `HomeScreen`'s doc for the full failure mode
    // (I16). `RootView` constructs this screen's view model inline and re-evaluates on every
    // in-app navigation; `@StateObject` + `@autoclosure` keeps the first instance for this view's
    // lifetime instead of silently discarding the one `.task` observes.
    @StateObject private var viewModel: LocateViewModel
    private let target: LocateTarget
    private let targetDisplayName: String
    /// specs/010-app-shell-and-screen-ux.md §2.1 (I34) — fires once `viewModel.status` reaches
    /// `.routeToOnboarding`.
    private let onProfileDeadEnd: (OnboardingVariant) -> Void

    public init(
        viewModel: @autoclosure @escaping () -> LocateViewModel,
        target: LocateTarget,
        targetDisplayName: String,
        onProfileDeadEnd: @escaping (OnboardingVariant) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.target = target
        self.targetDisplayName = targetDisplayName
        self.onProfileDeadEnd = onProfileDeadEnd
    }

    public var body: some View {
        VStack(spacing: theme.spacing.lg) {
            FindlyNavBar("Locate \(targetDisplayName)")
            content
            Spacer()
        }
        .background(theme.colors.surfaceVariant)
        .task { await viewModel.requestLocate(target: target) }
        .onDisappear { viewModel.cancel() }
        .onChange(of: routingVariant) { variant in
            if let variant { onProfileDeadEnd(variant) }
        }
    }

    private var routingVariant: OnboardingVariant? {
        if case .routeToOnboarding(let variant) = viewModel.status { return variant }
        return nil
    }

    private var content: some View {
        VStack(spacing: theme.spacing.md) {
            statusView
            if let lastKnown = viewModel.lastKnown {
                FindlyCard {
                    VStack(alignment: .leading, spacing: theme.spacing.xs) {
                        Text("Last known")
                            .font(theme.typography.titleMedium.font)
                            .foregroundColor(theme.colors.onSurface)
                        Text("\(lastKnown.lat), \(lastKnown.lon)")
                            .font(theme.typography.bodyMedium.font)
                            .foregroundColor(theme.colors.onSurface.opacity(0.7))
                        Text(lastKnown.recordedAt)
                            .font(theme.typography.labelSmall.font)
                            .foregroundColor(theme.colors.onSurface.opacity(0.7))
                    }
                }
            }
            FindlyButton("Locate again", style: .secondary) {
                Task { await viewModel.requestLocate(target: target) }
            }
        }
        .padding(.horizontal, theme.spacing.xl)
    }

    @ViewBuilder
    private var statusView: some View {
        switch viewModel.status {
        case .requesting, .routeToOnboarding:
            LoadingStateView(message: "Requesting location…")
        case .pending:
            LoadingStateView(message: "Last known, updating…")
        case .fulfilled:
            if let fix = viewModel.fulfilledFix {
                FindlyCard {
                    VStack(alignment: .leading, spacing: theme.spacing.xs) {
                        Text("Found!")
                            .font(theme.typography.titleMedium.font)
                            .foregroundColor(theme.colors.onSurface)
                        Text("\(fix.lat), \(fix.lon)")
                            .font(theme.typography.bodyMedium.font)
                            .foregroundColor(theme.colors.onSurface.opacity(0.7))
                    }
                }
            } else {
                StatusChip("Live", kind: .online)
            }
        case .pushFailed:
            StatusChip("Couldn't reach device — showing last known", kind: .stale)
        case .expired:
            StatusChip("Request expired", kind: .paused)
        case .failed(let message):
            ErrorStateView(message: message) {
                Task { await viewModel.requestLocate(target: target) }
            }
        }
    }
}
