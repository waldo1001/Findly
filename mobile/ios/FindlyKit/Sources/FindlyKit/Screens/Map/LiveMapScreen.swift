import SwiftUI

/// specs/004-ios-client.md I2 (001 §5.2) — composes ONLY design-system components + the injected
/// `MapRendering` base layer. `renderer` is stored as `any MapRendering` (not a generic parameter)
/// so callers can swap map providers without specializing this type.
public struct LiveMapScreen: View {
    @Environment(\.theme) private var theme
    // `@StateObject`, NOT `@ObservedObject` — see `HomeScreen`'s doc for the full failure mode
    // (I16). `RootView` constructs this screen's view model inline and re-evaluates on every
    // in-app navigation; `@StateObject` + `@autoclosure` keeps the first instance for this view's
    // lifetime instead of silently discarding the one `.task` observes.
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
    private let onSelectHistory: () -> Void
    private let onSelectGeofences: () -> Void
    private let onSelectDevices: () -> Void
    private let onSelectFamily: () -> Void
    private let onSelectInviteSomeone: () -> Void
    private let onSelectGroups: () -> Void
    private let onSelectPrivacySettings: () -> Void
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
        self.onProfileDeadEnd = onProfileDeadEnd
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                FindlyNavBar("Family map", menuAction: { isDrawerOpen = true })
                content
            }
            .background(theme.colors.surfaceVariant)

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

    private var routingVariant: OnboardingVariant? {
        if case .routeToOnboarding(let variant) = viewModel.state { return variant }
        return nil
    }

    @ViewBuilder
    private var content: some View {
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
            ScrollView {
                VStack(spacing: theme.spacing.md) {
                    renderer.makeMapView(region: $viewModel.region, annotations: viewModel.annotations)
                        .aspectRatio(1.4, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: theme.corner.lg))
                        .padding(.horizontal, theme.spacing.md)

                    if members.isEmpty {
                        EmptyStateView(title: "No family members yet", message: "Invite someone to see them here.")
                    } else {
                        ForEach(members, id: \.userId) { member in
                            FindlyCard {
                                VStack(alignment: .leading, spacing: theme.spacing.sm) {
                                    Text(member.displayName)
                                        .font(theme.typography.titleMedium.font)
                                        .foregroundColor(theme.colors.onSurface)
                                    if member.devices.isEmpty {
                                        Text("No devices registered")
                                            .font(theme.typography.bodyMedium.font)
                                            .foregroundColor(theme.colors.onSurface.opacity(0.7))
                                    } else {
                                        ForEach(member.devices, id: \.deviceId) { device in
                                            FindlyListRow(title: device.deviceName, subtitle: subtitle(for: device)) {
                                                statusChip(for: device)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, theme.spacing.md)
            }
        }
    }

    private func subtitle(for device: DeviceLocation) -> String? {
        guard let recordedAt = device.recordedAt else { return "No location yet" }
        return "Last seen \(recordedAt)"
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
}
