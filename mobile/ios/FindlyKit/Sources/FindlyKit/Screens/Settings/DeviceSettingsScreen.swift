import SwiftUI

/// specs/004-ios-client.md I2 (001 §4.2–4.3) — composes ONLY design-system components. Sync-
/// interval selection is a row of `FindlyButton` toggles (the allowed §1.4 values); pause is a
/// `FindlyToggleRow`; rename is a `FindlyTextField` + "Save name" button. All three are hidden
/// (read-only) for a non-parent viewer, matching §4.3's parent-vs-owner permission split.
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
                if let lastActionError = viewModel.lastActionError {
                    ErrorStateView(message: lastActionError)
                }
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
                    intervalPicker
                    renameRow
                }
            }
        }
    }

    private var renameRow: some View {
        HStack(spacing: theme.spacing.sm) {
            FindlyTextField("Device name", text: $renameDraft, placeholder: device.deviceName)
            FindlyButton("Save name", style: .secondary) {
                Task { await viewModel.rename(deviceId: device.deviceId, name: renameDraft) }
            }
            .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var intervalPicker: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text("Sync interval")
                .font(theme.typography.labelSmall.font)
                .foregroundColor(theme.colors.onSurface.opacity(0.7))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing.sm) {
                    ForEach(DeviceSettingsViewModel.allowedSyncIntervals, id: \.self) { minutes in
                        FindlyButton(label(for: minutes), style: minutes == device.syncIntervalMinutes ? .primary : .secondary) {
                            Task { await viewModel.setSyncInterval(deviceId: device.deviceId, minutes: minutes) }
                        }
                    }
                }
            }
        }
    }

    private func label(for minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 1440 { return "\(minutes / 60)h" }
        return "1d"
    }
}
