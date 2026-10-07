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
    /// specs/010-app-shell-and-screen-ux.md §2.1 / §3.6 (I59 review F1) — fires once
    /// `viewModel.state` reaches `.routeToOnboarding`: a confirmed `404 PROFILE_NOT_FOUND` (group
    /// screens need a profile, not a family — `FAMILY_NOT_FOUND` is an ordinary failure here), seen
    /// on the first load OR on any later refresh. `RootView` resets the stack to the Onboarding root.
    private let onProfileDeadEnd: (OnboardingVariant) -> Void
    @State private var sheetDetent: FindlyBottomSheetDetent = .standard
    @State private var now = Date()
    private static let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private static let isoFormatter = ISO8601DateFormatter()
    /// specs/010 §3.2/§3.6 (I59) — see `LiveMapScreen.scenePhase`: the group map refreshes under the
    /// same rules, through the same `MapRefreshDriver`.
    @Environment(\.scenePhase) private var scenePhase

    public init(
        viewModel: @autoclosure @escaping () -> GroupMapViewModel,
        renderer: any MapRendering,
        onExit: @escaping () -> Void,
        onProfileDeadEnd: @escaping (OnboardingVariant) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.renderer = renderer
        self.onExit = onExit
        self.onProfileDeadEnd = onProfileDeadEnd
    }

    public var body: some View {
        // A `ZStack`, not a `Group` (I59 review F6): the §3.6 lifecycle modifiers below must describe
        // the SCREEN, whichever branch is showing. A `Group` hands its modifiers to its children, so
        // swapping the map for the "group has ended" card could read as one view disappearing and
        // another appearing (a stray `disappeared()` + a fresh `appeared()`); a `ZStack` is one stable
        // view whose identity survives the swap. With a single child per branch it lays out exactly
        // like the bare child did.
        ZStack {
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
        // specs/010 §3.2/§3.6 (rows A55/I59) — identical wiring to `LiveMapScreen`: three lifecycle
        // signals forwarded to `viewModel.refreshDriver`, which owns every decision. They sit on the
        // stable `ZStack` above, so they keep describing the screen while `.expired` swaps the map for
        // the "group has ended" card (the view model ends polling itself on every confirmed state
        // change — `410 GROUP_EXPIRED`, `404 GROUP_NOT_FOUND`, `404 PROFILE_NOT_FOUND`).
        .task {
            syncSheetHeight()
            await viewModel.refreshDriver.appeared(phase: MapRefreshPolicy.ScenePhase(scenePhase))
        }
        .onDisappear { viewModel.refreshDriver.disappeared() }
        .onChange(of: scenePhase) { newPhase in
            syncSheetHeight()
            Task { await viewModel.refreshDriver.scenePhaseChanged(MapRefreshPolicy.ScenePhase(newPhase)) }
        }
        .onChange(of: routingVariant) { variant in
            if let variant { onProfileDeadEnd(variant) }
        }
        .onReceive(Self.ticker) { date in now = date }
    }

    private var routingVariant: OnboardingVariant? {
        if case .routeToOnboarding(let variant) = viewModel.state { return variant }
        return nil
    }

    /// specs/010 §3.4 "Occlusion model" (I49) — mirrors `LiveMapScreen.syncSheetHeight` exactly.
    private func syncSheetHeight() {
        viewModel.sheetHeightPt = currentSheetHeightPt
    }

    /// specs/010 §3.4 (I49) — mirrors `LiveMapScreen.currentSheetHeightPt` exactly.
    private var currentSheetHeightPt: CGFloat {
        switch sheetDetent {
        case .minimized: return sheetMinimizedHeight
        case .standard: return max(min(sheetStandardHeight, viewModel.mapViewportSizePt.height), sheetMinimizedHeight + 1)
        case .expanded: return viewModel.mapViewportSizePt.height * Self.expandedHeightFraction
        }
    }

    private static let expandedHeightFraction: CGFloat = 0.92

    /// specs/010 §3.2/§3.4 (amended 2026-08-27, row I45) — mirrors `LiveMapScreen`'s
    /// `mapWithChromeAndSheet` exactly: the `GeometryReader` is the render boundary that resolves
    /// `viewModel.mapViewportSizePt` for the pure `MapRegion(fitting:viewSizePt:)` translation. The
    /// reader itself is deliberately safe-area-respecting (see the trailing doc below) — only the
    /// map child ignores it, so `topChrome` and the sheet chained after this lay out against the
    /// true safe area.
    private var mapWithChromeAndSheet: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                renderer.makeMapView(region: $viewModel.region, annotations: viewModel.annotations)
                    .ignoresSafeArea()

                topChrome
                    .padding(.horizontal, theme.spacing.md)
                    .padding(.top, theme.spacing.sm)
            }
            .onAppear { viewModel.mapViewportSizePt = bledViewportSize(geometry) }
            .onChange(of: geometry.size) { _ in viewModel.mapViewportSizePt = bledViewportSize(geometry) }
            // Rotation is already covered by the `geometry.size` observer above (width/height swap
            // fires it), but a resized-window host (iPad Stage Manager / split view / an external
            // display's differing notch) can in principle change `safeAreaInsets` — e.g. moving to
            // a screen with no home indicator — while the reported point size stays identical.
            // `EdgeInsets` is `Equatable`, so this costs nothing when it never fires in practice.
            .onChange(of: geometry.safeAreaInsets) { _ in viewModel.mapViewportSizePt = bledViewportSize(geometry) }
        }
        // specs/010 §3.4 (I45 fix — TestFlight 220 regression: dead sheet space at the bottom of
        // every detent, ⌖/back drawn under the Dynamic Island and untappable). I39 put
        // `.ignoresSafeArea()` on the reader itself to fix the measurement, but that pulls the
        // READER'S ENTIRE SUBTREE out of the safe area — including `topChrome` (laid out under the
        // notch) and this `.findlyBottomSheet` (sized against a frame that overruns the home
        // indicator). The reader now respects the safe area again — `topChrome` and the sheet are
        // correct — and `mapViewportSizePt` is instead recovered arithmetically via
        // `MapViewport.bled` from `geometry.safeAreaInsets` (see that type's doc for why that's
        // lossless). Chained BEFORE `.findlyBottomSheet`, same as before, so the sheet's own
        // occlusion still never shrinks the measurement.
        // specs/010 §3.2/§3.1 (I46) — same measured-height detents as the Family Map (no drawer
        // here to dismiss the sheet for, §3.2's own doc: "No drawer").
        .findlyBottomSheet(
            selection: $sheetDetent,
            minimizedHeight: sheetMinimizedHeight,
            standardHeight: sheetStandardHeight,
            standardHeightCap: viewModel.mapViewportSizePt.height
        ) { detent in
            rosterSheetContent(detent: detent)
        }
    }

    /// specs/010 §3.1/§3.2 (I46) — computed, not measured; see `FindlyBottomSheet`'s header doc for
    /// why. Group rosters never show `Locate now` (§3.2: position-only, no push-to-locate flow).
    private var sheetMinimizedHeight: CGFloat {
        guard case .loaded = viewModel.state else { return 160 }
        return FindlyBottomSheetHeightPlanning.minimizedHeight(
            typography: theme.typography, spacing: theme.spacing, showsLocateNow: false
        )
    }

    /// specs/010 §3.1/§3.2 (I46) — `fullRoster`'s shape here is simpler than the Family Map's: one
    /// `FindlyListRow` and one divider per member (position-only, no per-device sub-rows).
    private var sheetStandardHeight: CGFloat {
        guard case .loaded(let members) = viewModel.state else { return 320 }
        return FindlyBottomSheetHeightPlanning.standardHeight(
            typography: theme.typography, spacing: theme.spacing, showsLocateNow: false,
            rowCount: members.count, dividerCount: members.count
        )
    }

    private func bledViewportSize(_ geometry: GeometryProxy) -> CGSize {
        MapViewport.bled(constrained: geometry.size, safeAreaInsets: geometry.safeAreaInsets)
    }

    private var topChrome: some View {
        HStack(spacing: theme.spacing.sm) {
            if let backAction {
                floatingIconButton(systemName: "chevron.backward", accessibilityLabel: "Back", action: backAction)
            }
            titlePill
            Spacer()
            floatingIconButton(systemName: "scope", accessibilityLabel: "Fit all", action: {
                syncSheetHeight()
                viewModel.fitAll()
            })
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
        case .loading, .routeToOnboarding:
            // specs/010 §2.1 — MUST NOT render a retryable error card for a confirmed
            // `PROFILE_NOT_FOUND`; the screen routes away the instant this state is reached, so
            // this is transient.
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
                Button("Refresh") {
                    syncSheetHeight()
                    Task { await viewModel.load() }
                }
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
            syncSheetHeight()
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
