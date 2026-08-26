import SwiftUI

/// specs/004-ios-client.md §3.4 (001 §12.10; 005 §3) — composes ONLY design-system components +
/// the injected `MapRendering` base layer, exactly like `LiveMapScreen`. **Position-only**: roster
/// rows show display name + role + live/stale chip — no device rows, no battery, because
/// `GroupMemberLocation` simply doesn't carry those fields.
///
/// specs/010-app-shell-and-screen-ux.md §3.2 (I35) — adopts the SAME full-bleed + `FindlyBottomSheet`
/// layout and the SAME camera policy as `LiveMapScreen`, through the same renderer seam. No drawer,
/// no "Locate now" (005 §3: group rosters are position-only — Locate's push-to-locate flow is a
/// family concept this screen never had and this task doesn't extend to groups); selection still
/// highlights + zooms per §3.4/§3.5's camera rules.
public struct GroupMapScreen: View {
    @Environment(\.theme) private var theme
    @Environment(\.navBarBackAction) private var backAction
    // `@StateObject`, NOT `@ObservedObject` — see `HomeScreen`'s doc for the full failure mode
    // (I16). `RootView` constructs this screen's view model inline and re-evaluates on every
    // in-app navigation; `@StateObject` + `@autoclosure` keeps the first instance for this view's
    // lifetime instead of silently discarding the one `.task` observes.
    @StateObject private var viewModel: GroupMapViewModel
    private let renderer: any MapRendering
    private let onExit: () -> Void
    @State private var sheetDetent: FindlyBottomSheetDetent = .standard
    @State private var now = Date()
    private static let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private static let isoFormatter = ISO8601DateFormatter()

    public init(viewModel: @autoclosure @escaping () -> GroupMapViewModel, renderer: any MapRendering, onExit: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.renderer = renderer
        self.onExit = onExit
    }

    public var body: some View {
        Group {
            switch viewModel.state {
            case .expired:
                // 005 §2.3 — the group ended while this screen was open; there's nothing to
                // retry, and there's no map surface worth keeping up either (unlike an ordinary
                // load error, §9).
                ErrorStateView(message: "This group has ended.", retryTitle: "Back to groups", onRetry: onExit)
            default:
                mapWithChromeAndSheet
            }
        }
        .task { await viewModel.load() }
        .onReceive(Self.ticker) { date in now = date }
    }

    /// specs/010 §3.2/§3.4 (amended 2026-08-26, row I39) — mirrors `LiveMapScreen`'s
    /// `mapWithChromeAndSheet` exactly: the `GeometryReader` is the render boundary that resolves
    /// `viewModel.mapViewportSizePt` for the pure `MapRegion(fitting:viewSizePt:)` translation.
    private var mapWithChromeAndSheet: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                renderer.makeMapView(region: $viewModel.region, annotations: viewModel.annotations)
                    .ignoresSafeArea()

                topChrome
                    .padding(.horizontal, theme.spacing.md)
                    .padding(.top, theme.spacing.sm)
            }
            .onAppear { viewModel.mapViewportSizePt = geometry.size }
            .onChange(of: geometry.size) { viewModel.mapViewportSizePt = $0 }
        }
        // specs/010 §3.4 (I39 review fix 1) — `.ignoresSafeArea()` on the CHILD map view alone left
        // the `GeometryReader` itself safe-area-constrained, so `mapViewportSizePt` under-reported
        // the true full-bleed extent by roughly the status bar/notch + home indicator (almost
        // entirely on the height/latitude axis) -- the fixed padding was then exact against the
        // measured frame, not the frame the user actually sees. Ignoring the safe area on the
        // reader itself is the standard idiom for measuring the true full-bleed size. Chained
        // BEFORE `.findlyBottomSheet` so the sheet's own occlusion still never shrinks the
        // measurement (unchanged from before this fix).
        .ignoresSafeArea()
        .findlyBottomSheet(selection: $sheetDetent) { detent in
            rosterSheetContent(detent: detent)
        }
    }

    private var topChrome: some View {
        HStack(spacing: theme.spacing.sm) {
            if let backAction {
                floatingIconButton(systemName: "chevron.backward", accessibilityLabel: "Back", action: backAction)
            }
            titlePill
            Spacer()
            floatingIconButton(systemName: "scope", accessibilityLabel: "Fit all", action: { viewModel.fitAll() })
        }
    }

    private var titlePill: some View {
        Text("Group map")
            .font(theme.typography.bodyMedium.font)
            .foregroundColor(theme.colors.onSurface)
            .padding(.horizontal, theme.spacing.md)
            .frame(height: 48)
            .background(theme.colors.surface)
            .clipShape(Capsule())
            .shadow(
                color: theme.elevation.level2.color.opacity(theme.elevation.level2.opacity),
                radius: theme.elevation.level2.blur, y: theme.elevation.level2.y
            )
    }

    private func floatingIconButton(systemName: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(theme.colors.onSurface)
                .frame(width: 48, height: 48)
                .background(theme.colors.surface)
                .clipShape(Circle())
                .shadow(
                    color: theme.elevation.level2.color.opacity(theme.elevation.level2.opacity),
                    radius: theme.elevation.level2.blur, y: theme.elevation.level2.y
                )
        }
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func rosterSheetContent(detent: FindlyBottomSheetDetent) -> some View {
        switch viewModel.state {
        case .loading:
            LoadingStateView(message: "Loading map…")
        case .error(let message):
            ErrorStateView(message: message) {
                Task { await viewModel.load() }
            }
        case .expired:
            EmptyView()
        case .loaded(let members):
            if detent == .minimized {
                minimizedRoster(members: members)
            } else {
                fullRoster(members: members)
            }
        }
    }

    /// specs/010 §3.1/§3.2 (review fix 1) — the family map's minimized-detent avatar stack applies
    /// here too: same components, same fix, same `RosterAvatarStackPlan` cap/overflow semantics.
    private func minimizedRoster(members: [GroupMemberLocation]) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Text("Group")
                .font(theme.typography.titleMedium.font)
                .foregroundColor(theme.colors.onSurface)
            Text(summaryLine(for: members))
                .font(theme.typography.bodyMedium.font)
                .foregroundColor(theme.onSurfaceMuted)
            RosterAvatarStack(displayNames: members.map(\.displayName))
        }
        .padding(theme.spacing.md)
    }

    private func fullRoster(members: [GroupMemberLocation]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Group")
                    .font(theme.typography.titleMedium.font)
                    .foregroundColor(theme.colors.onSurface)
                Spacer()
                Button("Refresh") { Task { await viewModel.load() } }
                    .font(theme.typography.bodyMedium.font)
                    .foregroundColor(theme.colors.primary)
            }
            .padding(theme.spacing.md)

            ScrollView {
                if members.isEmpty {
                    EmptyStateView(title: "No one here yet", message: "Positions appear once members start sharing their location.")
                        .padding(.vertical, theme.spacing.md)
                } else {
                    VStack(spacing: 0) {
                        ForEach(members, id: \.userId) { member in
                            memberRow(member)
                            FindlyCardDivider()
                        }
                    }
                }
            }
        }
    }

    private func memberRow(_ member: GroupMemberLocation) -> some View {
        let isSelected = member.userId == viewModel.selectedUserId
        return Button {
            viewModel.selectMember(member.userId)
        } label: {
            FindlyListRow(title: member.displayName, subtitle: subtitle(for: member), avatarText: Self.initials(for: member.displayName)) {
                statusChip(for: member)
            }
            .background(isSelected ? theme.colors.surfaceVariant : Color.clear)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func summaryLine(for members: [GroupMemberLocation]) -> String {
        let located = members.filter { $0.location != nil }.count
        return "\(located) of \(members.count) sharing their location"
    }

    private func subtitle(for member: GroupMemberLocation) -> String {
        guard let location = member.location else { return member.role.capitalized }
        let relative = RelativeTimeFormatter.format(recordedAtIso: location.recordedAt, nowIso: Self.isoFormatter.string(from: now))
        return "\(member.role.capitalized) · \(relative)"
    }

    private func statusChip(for member: GroupMemberLocation) -> StatusChip {
        guard let location = member.location else {
            return StatusChip("No position", kind: .paused)
        }
        return location.isStale ? StatusChip("Stale", kind: .stale) : StatusChip("Live", kind: .online)
    }

    private static func initials(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }
        return String(trimmed.prefix(2)).uppercased()
    }
}
