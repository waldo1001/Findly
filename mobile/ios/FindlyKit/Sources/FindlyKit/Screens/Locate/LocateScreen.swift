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
            // specs/009 §5.1 "Requester side": a definitive fulfil within the request window
            // ("fresh") — no age caption.
            foundCard(caption: nil)
        case .late:
            // specs/009 §5.1 "Requester side": rendered exactly like `.fulfilled` plus an age
            // caption.
            foundCard(caption: viewModel.resolvedPosition.map { LocateAgeCaption.forRecordedAt($0.recordedAt) })
        case .unreachable:
            // I51 review fix (Blocking, finding 1): 001 §6.2 assigns "couldn't reach the device"
            // copy specifically to a `pushFailed` wire status — a request that was delivered and
            // simply never answered ("expired", or any other non-pushFailed terminal) must not be
            // told the opposite of the truth. Mirrors Android's `LocateScreen` branching on the
            // terminal state's raw wire status.
            // I51 re-review fix (Minor, finding 2): mirrors Android's `LocateScreen`/`FindlyStatusChip`
            // tone mapping (Warning = stale, Neutral = paused) — an ordinary expiry isn't as serious as
            // a device that couldn't be reached, so it gets the calmer `.paused` tone. The suffixed
            // copy stays: Android uses the same "— showing last known" wording for both outcomes, and
            // post-B26 it's literally true here too since the fallback leaves the last-known position
            // on screen.
            if viewModel.wireStatus == .pushFailed {
                StatusChip("Couldn't reach the device — showing last known", kind: .stale)
            } else {
                StatusChip("Request expired — showing last known", kind: .paused)
            }
        case .failed(let message):
            ErrorStateView(message: message) {
                Task { await viewModel.requestLocate(target: target) }
            }
        }
    }

    /// I51 review fix (Minor, finding 5): the `.fulfilled`/`.late` card bodies were identical but
    /// for one caption line — collapsed here so the two cannot drift. `caption` is `nil` for
    /// `.fulfilled` (no age line) and the age caption for `.late`.
    @ViewBuilder
    private func foundCard(caption: String?) -> some View {
        if let position = viewModel.resolvedPosition {
            FindlyCard {
                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    Text("Found!")
                        .font(theme.typography.titleMedium.font)
                        .foregroundColor(theme.colors.onSurface)
                    Text("\(position.lat), \(position.lon)")
                        .font(theme.typography.bodyMedium.font)
                        .foregroundColor(theme.colors.onSurface.opacity(0.7))
                    if let caption {
                        Text(caption)
                            .font(theme.typography.labelSmall.font)
                            .foregroundColor(theme.colors.onSurface.opacity(0.7))
                    }
                }
            }
        } else {
            StatusChip("Live", kind: .online)
        }
    }
}
