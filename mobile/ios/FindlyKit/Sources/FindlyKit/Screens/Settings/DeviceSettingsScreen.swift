import SwiftUI

/// specs/004-ios-client.md I2 (001 §4.2–4.3), specs/010-app-shell-and-screen-ux.md §4.2 (I36) —
/// composes ONLY design-system components. Sync-interval selection is a `FindlyDropdownField`
/// over the 001 §1.4 values (replacing the pre-010 horizontally-scrolling `FindlyButton` chip
/// row); pause is a `FindlyToggleRow`; rename is a single aligned field+Save row using
/// `FindlyTextField(nil, ...)` (review fix, I36 round 2 — `label` is now optional on the shared
/// component itself, so the stacked label row that used to sit beside a bare button and throw
/// the pair's vertical centers out of alignment is simply omitted, rather than duplicated in a
/// screen-local type). All three are hidden (read-only) for a non-parent viewer, matching §4.3's
/// parent-vs-owner permission split. Each card's own mutation errors render on that card via
/// `viewModel.error(forDeviceId:)` — the pre-010 shared top-of-list `lastActionError` banner is
/// retired, not left alongside this.
public struct DeviceSettingsScreen: View {
    @Environment(\.theme) private var theme
    // `@StateObject`, NOT `@ObservedObject` — see `HomeScreen`'s doc for the full failure mode
    // (I16). `RootView` constructs this screen's view model inline and re-evaluates on every
    // in-app navigation; `@StateObject` + `@autoclosure` keeps the first instance for this view's
    // lifetime instead of silently discarding the one `.task` observes.
    @StateObject private var viewModel: DeviceSettingsViewModel
    /// specs/010-app-shell-and-screen-ux.md §2.1 (I34) — fires once `viewModel.state` reaches
    /// `.routeToOnboarding`.
    private let onProfileDeadEnd: (OnboardingVariant) -> Void

    public init(
        viewModel: @autoclosure @escaping () -> DeviceSettingsViewModel,
        onProfileDeadEnd: @escaping (OnboardingVariant) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.onProfileDeadEnd = onProfileDeadEnd
    }

    public var body: some View {
        VStack(spacing: 0) {
            FindlyNavBar("Devices")
            content
        }
        .background(theme.colors.surfaceVariant)
        .task { await viewModel.load() }
        .onChange(of: routingVariant) { variant in
            if let variant { onProfileDeadEnd(variant) }
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
            LoadingStateView(message: "Loading devices…")
        case .error(let message):
            ErrorStateView(message: message) {
                Task { await viewModel.load() }
            }
        case .loaded(let devices):
            list(devices)
        }
    }

    private func list(_ devices: [DeviceListItem]) -> some View {
        ScrollView {
            VStack(spacing: theme.spacing.md) {
                if devices.isEmpty {
                    EmptyStateView(title: "No devices yet", message: "Devices register automatically after sign-in.")
                } else {
                    ForEach(devices, id: \.deviceId) { device in
                        DeviceCardView(viewModel: viewModel, device: device)
                    }
                }
            }
            .padding(theme.spacing.md)
        }
    }
}

/// One device's card — its own `View` (rather than a plain function returning `some View`) so the
/// rename draft's `@State` is scoped per-row instead of colliding across every device in the list.
private struct DeviceCardView: View {
    @Environment(\.theme) private var theme
    @ObservedObject var viewModel: DeviceSettingsViewModel
    let device: DeviceListItem
    @State private var renameDraft: String

    init(viewModel: DeviceSettingsViewModel, device: DeviceListItem) {
        self.viewModel = viewModel
        self.device = device
        self._renameDraft = State(initialValue: device.deviceName)
    }

    var body: some View {
        FindlyCard {
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                HStack {
                    Text(device.deviceName)
                        .font(theme.typography.titleMedium.font)
                        .foregroundColor(theme.colors.onSurface)
                    Spacer()
                    StatusChip(device.trackingEnabled ? "Active" : "Paused", kind: device.trackingEnabled ? .online : .paused)
                }
                Text("Owner: \(device.ownerDisplayName)")
                    .font(theme.typography.bodyMedium.font)
                    .foregroundColor(theme.colors.onSurface.opacity(0.7))
                if viewModel.isParent {
                    FindlyToggleRow(
                        title: "Tracking enabled",
                        isOn: Binding(
                            get: { device.trackingEnabled },
                            set: { newValue in Task { await viewModel.setTrackingEnabled(deviceId: device.deviceId, newValue) } }
                        )
                    )
                    intervalDropdown
                    renameRow
                }
                // specs/010-app-shell-and-screen-ux.md §4.2 (I36): "Errors from this card's
                // mutations render on this card, not pooled at the top of the list" — the retired
                // shared `lastActionError` banner used to sit above the whole list in
                // `DeviceSettingsScreen.list(_:)`; this is its sole replacement, scoped to this
                // device's own card only.
                if let cardError = viewModel.error(forDeviceId: device.deviceId) {
                    cardErrorText(cardError)
                }
            }
        }
    }

    /// specs/010-app-shell-and-screen-ux.md §4.2/§9 (review fix, I36 round 2) — passes the floor
    /// straight through as `Int?`, no `?? 0`: a `nil` floor now fails CLOSED inside
    /// `SyncIntervalDropdownPlan.options` (every option individually disabled), and the whole
    /// field is ALSO disabled here as a second, belt-and-braces gate — mirroring Android's
    /// `SyncIntervalOptions`, which disables both the per-option state and the dropdown's own
    /// `enabled` flag. `?? 0` was wrong: a floor of 0 disables nothing, failing OPEN.
    private var intervalDropdown: some View {
        FindlyDropdownField(
            label: "Sync interval",
            options: SyncIntervalDropdownPlan.options(minSyncIntervalMinutes: viewModel.minSyncIntervalMinutes),
            selection: device.syncIntervalMinutes,
            onSelect: { minutes in
                Task { await viewModel.setSyncInterval(deviceId: device.deviceId, minutes: minutes) }
            }
        )
        .disabled(viewModel.minSyncIntervalMinutes == nil)
    }

    /// specs/010-app-shell-and-screen-ux.md §4.2 — "one horizontal row containing the
    /// device-name input and a Save button, both the same control height (52 pt), vertically
    /// centered on each other." Uses the shared `FindlyTextField` with `label: nil` (review fix,
    /// I36 round 2) — its stacked label row is what threw this pair's vertical centers out of
    /// alignment before this task, and a `nil` label omits that row entirely rather than
    /// duplicating the component's box geometry in a screen-local type. The static "Device name"
    /// placeholder doubles as the field's accessibility label (§4.2's "placeholder + accessibility
    /// label" wording) via `FindlyTextField`'s own `label ?? placeholder` fallback.
    private var renameRow: some View {
        HStack(alignment: .center, spacing: theme.spacing.sm) {
            FindlyTextField(nil, text: $renameDraft, placeholder: "Device name")
            FindlyButton("Save", style: .secondary) {
                let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { await viewModel.rename(deviceId: device.deviceId, name: trimmed) }
            }
            .frame(width: 96) // fixed so it doesn't split the row 50/50 with the equally-greedy text field
            .disabled(!DeviceRenamePlan.isSaveEnabled(draft: renameDraft, currentName: device.deviceName))
        }
    }

    private func cardErrorText(_ message: String) -> some View {
        HStack(alignment: .top, spacing: theme.spacing.xs) {
            Text("✕")
            Text(message)
        }
        .font(theme.typography.bodyMedium.font)
        .foregroundColor(theme.colors.danger)
    }
}
