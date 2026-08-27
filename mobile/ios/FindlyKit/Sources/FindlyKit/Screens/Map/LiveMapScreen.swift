import SwiftUI

/// specs/004-ios-client.md I2 (001 §5.2) — composes ONLY design-system components + the injected
/// `MapRendering` base layer. `renderer` is stored as `any MapRendering` (not a generic parameter)
/// so callers can swap map providers without specializing this type.
///
/// specs/010-app-shell-and-screen-ux.md §3.1 (I35) — the map is full-bleed (the retired 1.4
/// aspect-ratio card is gone) with the roster in a `FindlyBottomSheet`; the map renders
/// unconditionally regardless of `viewModel.state` (§9: "the sheet shows the error state; the map
/// surface stays") — only the SHEET's content switches on loading/error/loaded.
public struct LiveMapScreen: View {
    @Environment(\.theme) private var theme
    // `@StateObject`, NOT `@ObservedObject` — see `HomeScreen`'s doc for the full failure mode
    // (I16). `RootView` constructs this screen's view model inline and re-evaluates on every
    // in-app navigation; `@StateObject` + `@autoclosure` keeps the first instance for this view's
    // lifetime instead of silently discarding the one `.task` observes. This is exactly the
    // instance `.findlyBottomSheet`'s content closure below captures, so detent changes (010
    // §3.1's I16 rule) never disturb it — proven generically by
    // `FindlyBottomSheetDetentOwnershipTests`.
    @StateObject private var viewModel: LiveMapViewModel
    private let renderer: any MapRendering
    /// specs/010-app-shell-and-screen-ux.md §1.2 — the SAME shared instance `RootView` populates
    /// from the launch probe / `FamilyMembersViewModel`, read here for the drawer header + the
    /// "Invite someone" parent gate. `@ObservedObject`, not `@StateObject`: unlike a per-screen
    /// view model, this is one long-lived instance the caller always hands in — there is no
    /// factory-re-invoked-on-every-re-render risk (the I16 concern) to guard against here.
    @ObservedObject private var familyContext: FamilyContextCache
    /// specs/010-app-shell-and-screen-ux.md §1.2 (I34) — the Family Map is the ONLY screen that
    /// renders the ☰ button / owns the drawer.
    @State private var isDrawerOpen = false
    /// specs/010 §3.1 — a plain `@State`; SwiftUI already guarantees this survives every body
    /// re-evaluation of this same view identity (including one triggered by a detent drag itself),
    /// which is exactly the "never re-create" property `FindlyBottomSheetDetentOwnershipTests`
    /// proves generically for the `@StateObject` case.
    @State private var sheetDetent: FindlyBottomSheetDetent = .standard
    /// specs/010 §3.1 — "humanized relative times ... recomputed on a 30 s ticker (never per
    /// frame)". A plain `@State` driven by `.onReceive`, not a per-frame `Date()` read inside
    /// `body` — the ticker fires at most once every 30 s regardless of how often SwiftUI
    /// re-renders this view for unrelated reasons.
    @State private var now = Date()
    private static let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private static let isoFormatter = ISO8601DateFormatter()

    private let onSelectHistory: () -> Void
    private let onSelectGeofences: () -> Void
    private let onSelectDevices: () -> Void
    private let onSelectFamily: () -> Void
    private let onSelectInviteSomeone: () -> Void
    private let onSelectGroups: () -> Void
    private let onSelectPrivacySettings: () -> Void
    /// specs/010 §3.5 — "Locate now" in the sheet header routes to the existing Locate screen
    /// (001 §6, unchanged) for the selected member.
    private let onLocateNow: (String, String) -> Void
    /// specs/010-app-shell-and-screen-ux.md §2.1 (I34) — fires once `viewModel.state` reaches
    /// `.routeToOnboarding`, so `RootView` can reset the stack to the corresponding Onboarding
    /// variant. Defaults to a no-op so existing previews/tests that don't care about this need not
    /// supply it.
    private let onProfileDeadEnd: (OnboardingVariant) -> Void

    public init(
        viewModel: @autoclosure @escaping () -> LiveMapViewModel,
        renderer: any MapRendering,
        familyContext: FamilyContextCache,
        onSelectHistory: @escaping () -> Void = {},
        onSelectGeofences: @escaping () -> Void = {},
        onSelectDevices: @escaping () -> Void = {},
        onSelectFamily: @escaping () -> Void = {},
        onSelectInviteSomeone: @escaping () -> Void = {},
        onSelectGroups: @escaping () -> Void = {},
        onSelectPrivacySettings: @escaping () -> Void = {},
        onLocateNow: @escaping (String, String) -> Void = { _, _ in },
        onProfileDeadEnd: @escaping (OnboardingVariant) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.renderer = renderer
        self.familyContext = familyContext
        self.onSelectHistory = onSelectHistory
        self.onSelectGeofences = onSelectGeofences
        self.onSelectDevices = onSelectDevices
        self.onSelectFamily = onSelectFamily
        self.onSelectInviteSomeone = onSelectInviteSomeone
        self.onSelectGroups = onSelectGroups
        self.onSelectPrivacySettings = onSelectPrivacySettings
        self.onLocateNow = onLocateNow
        self.onProfileDeadEnd = onProfileDeadEnd
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            mapWithChromeAndSheet

            if isDrawerOpen {
                FindlyNavDrawer(
                    familyName: familyContext.familyName ?? "",
                    myDisplayName: familyContext.myDisplayName ?? "",
                    items: FindlyNavDrawerBuilder.items(isParent: familyContext.isParent ?? false),
                    selectedId: "familyMap",
                    onSelect: { id in
                        isDrawerOpen = false
                        handleDrawerSelection(id)
                    },
                    onDismiss: { isDrawerOpen = false }
                )
            }
        }
        .task { await viewModel.load() }
        .onChange(of: routingVariant) { variant in
            if let variant { onProfileDeadEnd(variant) }
        }
        .onReceive(Self.ticker) { date in now = date }
    }

    /// specs/010 §3.1 — full-bleed map (edge-to-edge behind system bars) with the ☰ button + family
    /// pill floating above it, and the roster sheet on top of everything. The map renders
    /// unconditionally; only the sheet's content switches on `viewModel.state` (§9).
    ///
    /// specs/010 §3.4 (amended 2026-08-27, row I45) — the `GeometryReader` is the render boundary
    /// that resolves `viewModel.mapViewportSizePt`: `MapCameraPolicy`/`MapRegion(fitting:)` stay
    /// pure and have no live view size of their own, so this is the one place (mirroring Android's
    /// `GoogleMapRenderer` resolving `LocalDensity`) that can hand the real point size down before
    /// the next camera command is translated into a region. The reader itself is deliberately
    /// safe-area-respecting (see the trailing doc below) — only the map child ignores it, so
    /// `topChrome` and the sheet chained after this lay out against the true safe area.
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
        // every detent, ☰/⌖ drawn under the Dynamic Island and untappable). I39 put
        // `.ignoresSafeArea()` on the reader itself to fix the measurement, but that pulls the
        // READER'S ENTIRE SUBTREE out of the safe area — including `topChrome` (laid out under the
        // notch) and this `.findlyBottomSheet` (sized against a frame that overruns the home
        // indicator). The reader now respects the safe area again — `topChrome` and the sheet are
        // correct — and `mapViewportSizePt` is instead recovered arithmetically via
        // `MapViewport.bled` from `geometry.safeAreaInsets` (see that type's doc for why that's
        // lossless). Chained BEFORE `.findlyBottomSheet`, same as before, so the sheet's own
        // occlusion still never shrinks the measurement.
        .findlyBottomSheet(selection: $sheetDetent) { detent in
            rosterSheetContent(detent: detent)
        }
    }

    private func bledViewportSize(_ geometry: GeometryProxy) -> CGSize {
        MapViewport.bled(constrained: geometry.size, safeAreaInsets: geometry.safeAreaInsets)
    }

    private var topChrome: some View {
        HStack(spacing: theme.spacing.sm) {
            menuButton
            familyPill
            Spacer()
            fitAllButton
        }
    }

    /// design 2a "Ember/Dusk" (§3.1, §7.3): "48pt/dp circular, `surface` fill, `level2` shadow —
    /// replacing the handoff's 'settings button'". A one-off floating control, not a
    /// `DesignSystem/Components` type (the batch's three new named components are
    /// `FindlyNavDrawer`/`FindlyBottomSheet`/`FindlyDropdownField` only) — same "screen-level
    /// composition, theme tokens applied directly" precedent as this file's existing member card.
    private var menuButton: some View {
        Button(action: { isDrawerOpen = true }) {
            Image(systemName: "line.3.horizontal")
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
        .accessibilityLabel("Menu")
    }

    private var familyPill: some View {
        Text(familyPillText)
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

    private var familyPillText: String {
        let name = familyContext.familyName ?? "Family"
        guard case .loaded(let members) = viewModel.state else { return name }
        return "\(name) · \(members.count) member\(members.count == 1 ? "" : "s")"
    }

    /// specs/010 §3.4 — the explicit fit-all action (a small floating ⌖-class button) that
    /// re-runs the camera policy over the currently loaded points.
    private var fitAllButton: some View {
        Button(action: { viewModel.fitAll() }) {
            Image(systemName: "scope")
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
        .accessibilityLabel("Fit all")
    }

    private var routingVariant: OnboardingVariant? {
        if case .routeToOnboarding(let variant) = viewModel.state { return variant }
        return nil
    }

    @ViewBuilder
    private func rosterSheetContent(detent: FindlyBottomSheetDetent) -> some View {
        switch viewModel.state {
        case .loading, .routeToOnboarding:
            // specs/010 §2.1 — MUST NOT render a retryable error card; `onProfileDeadEnd` above
            // navigates away the instant this state is reached, so this is transient.
            LoadingStateView(message: "Loading map…")
        case .error(let message):
            ErrorStateView(message: message) {
                Task { await viewModel.load() }
            }
        case .loaded(let members):
            if detent == .minimized {
                minimizedRoster(members: members)
            } else {
                fullRoster(members: members)
            }
        }
    }

    /// specs/010 §3.1 — the minimized detent's content: grabber (drawn by the system drag
    /// indicator, not this view), "Family" title, summary line, `Locate now` for the selected
    /// member when one is selected, avatar stack.
    private func minimizedRoster(members: [MemberLocations]) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Text("Family")
                .font(theme.typography.titleMedium.font)
                .foregroundColor(theme.colors.onSurface)
            Text(summaryLine(for: members))
                .font(theme.typography.bodyMedium.font)
                .foregroundColor(theme.onSurfaceMuted)
            if let selectedMember = selectedMember(in: members) {
                FindlyButton("Locate now", style: .secondary) {
                    onLocateNow(selectedMember.userId, selectedMember.displayName)
                }
            }
            RosterAvatarStack(displayNames: members.map(\.displayName))
        }
        .padding(theme.spacing.md)
    }

    /// specs/010 §3.1 — the standard/expanded detents' content: header + the full member list
    /// (the list scrolls at the expanded/"large" detent; at standard it's clipped by the sheet's
    /// own 440pt height, matching the handoff).
    private func fullRoster(members: [MemberLocations]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Family")
                    .font(theme.typography.titleMedium.font)
                    .foregroundColor(theme.colors.onSurface)
                Spacer()
                Button("Refresh") { Task { await viewModel.load() } }
                    .font(theme.typography.bodyMedium.font)
                    .foregroundColor(theme.colors.primary)
            }
            .padding(theme.spacing.md)

            if let selectedMember = selectedMember(in: members) {
                FindlyButton("Locate now", style: .secondary) {
                    onLocateNow(selectedMember.userId, selectedMember.displayName)
                }
                .padding(.horizontal, theme.spacing.md)
                .padding(.bottom, theme.spacing.sm)
            }

            ScrollView {
                if members.isEmpty {
                    emptyRoster
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

    private var emptyRoster: some View {
        VStack(spacing: theme.spacing.md) {
            EmptyStateView(title: "No family members yet", message: "Invite someone to see them here.")
            if familyContext.isParent == true {
                FindlyButton("Invite", style: .secondary) { onSelectInviteSomeone() }
                    .padding(.horizontal, theme.spacing.md)
            }
        }
        .padding(.vertical, theme.spacing.md)
    }

    /// specs/010 §3.5 — tapping a member's roster row selects them (and, via `viewModel`, zooms to
    /// their freshest located device).
    private func memberRow(_ member: MemberLocations) -> some View {
        let isSelected = member.userId == viewModel.selectedUserId
        return Button {
            viewModel.selectMember(member.userId)
        } label: {
            VStack(spacing: 0) {
                if member.devices.isEmpty {
                    FindlyListRow(title: member.displayName, subtitle: "No devices registered", avatarText: Self.initials(for: member.displayName))
                } else {
                    ForEach(Array(member.devices.enumerated()), id: \.element.deviceId) { index, device in
                        FindlyListRow(
                            title: index == 0 ? member.displayName : device.deviceName,
                            subtitle: subtitle(for: device),
                            avatarText: Self.initials(for: member.displayName)
                        ) {
                            statusChip(for: device)
                        }
                        if index < member.devices.count - 1 {
                            FindlyCardDivider()
                        }
                    }
                }
            }
            .background(isSelected ? theme.colors.surfaceVariant : Color.clear)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func selectedMember(in members: [MemberLocations]) -> MemberLocations? {
        guard let selectedUserId = viewModel.selectedUserId else { return nil }
        return members.first { $0.userId == selectedUserId }
    }

    private func summaryLine(for members: [MemberLocations]) -> String {
        let located = members.filter { member in member.devices.contains { $0.lat != nil && $0.lon != nil } }.count
        return "\(located) of \(members.count) sharing their location"
    }

    private func subtitle(for device: DeviceLocation) -> String? {
        guard let recordedAt = device.recordedAt else { return "No location yet" }
        return RelativeTimeFormatter.format(recordedAtIso: recordedAt, nowIso: Self.isoFormatter.string(from: now))
    }

    private func statusChip(for device: DeviceLocation) -> StatusChip {
        if !device.trackingEnabled {
            return StatusChip("Paused", kind: .paused)
        } else if device.isStale ?? true {
            return StatusChip("Stale", kind: .stale)
        } else {
            return StatusChip("Live", kind: .online)
        }
    }

    /// specs/010 §1.2 — "Selecting a destination closes the drawer and pushes that screen onto the
    /// existing stack" (already done by the caller-supplied `onSelectX` closures below); "Family
    /// map (current)" is a no-op here since we're already on it.
    private func handleDrawerSelection(_ id: String) {
        switch id {
        case "familyMap": break
        case "history": onSelectHistory()
        case "geofences": onSelectGeofences()
        case "devices": onSelectDevices()
        case "family": onSelectFamily()
        case "inviteSomeone": onSelectInviteSomeone()
        case "groups": onSelectGroups()
        case "privacyData": onSelectPrivacySettings()
        default: break
        }
    }

    private static func initials(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }
        return String(trimmed.prefix(2)).uppercased()
    }
}
