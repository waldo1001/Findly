import SwiftUI

/// specs/004-ios-client.md I2 (001 §4.2–4.3), specs/010-app-shell-and-screen-ux.md §4.2 (I36) —
/// composes ONLY design-system components. Sync-interval selection is a `FindlyDropdownField`
/// over the 001 §1.4 values (replacing the pre-010 horizontally-scrolling `FindlyButton` chip
/// row); pause is a `FindlyToggleRow`; rename is a single aligned field+Save row (replacing the
/// pre-010 layout, where `FindlyTextField`'s own stacked label sat beside a bare button and threw
/// the pair's vertical centers out of alignment — §4.2's defect this task exists to fix). All
/// three are hidden (read-only) for a non-parent viewer, matching §4.3's parent-vs-owner
/// permission split. Each card's own mutation errors render on that card via
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

    private var intervalDropdown: some View {
        FindlyDropdownField(
            label: "Sync interval",
            // `?? 0` is a neutral (nothing disabled), not invented, fallback for a branch that is
            // unreachable by construction: this card only renders once `state` is `.loaded`, and
            // `viewModel.minSyncIntervalMinutes` is set from the SAME envelope, in the SAME method,
            // before `state` becomes `.loaded` (specs/001 §9 — never a plan-specific literal here).
            options: SyncIntervalDropdownPlan.options(minSyncIntervalMinutes: viewModel.minSyncIntervalMinutes ?? 0),
            selection: device.syncIntervalMinutes,
            onSelect: { minutes in
                Task { await viewModel.setSyncInterval(deviceId: device.deviceId, minutes: minutes) }
            }
        )
    }

    /// specs/010-app-shell-and-screen-ux.md §4.2 — "one horizontal row containing the
    /// device-name input and a Save button, both the same control height (52 pt), vertically
    /// centered on each other." Deliberately NOT `FindlyTextField` here: that component's own
    /// stacked label-above-field layout is exactly what threw the pair's vertical centers out of
    /// alignment before this task — see `DeviceRenameField`'s doc for why a screen-local,
    /// label-less input (placeholder + accessibility label only, per this same bullet) is used
    /// instead of changing the shared component's contract for every other call site.
    private var renameRow: some View {
        HStack(alignment: .center, spacing: theme.spacing.sm) {
            DeviceRenameField(placeholder: device.deviceName, text: $renameDraft)
            FindlyButton("Save", style: .secondary) {
                let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { await viewModel.rename(deviceId: device.deviceId, name: trimmed) }
            }
            .frame(width: 96)
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

/// specs/010-app-shell-and-screen-ux.md §4.2 — the rename row's input: same box geometry as
/// `FindlyTextField` (52pt height, `surfaceVariant` fill, `outlineStrong`/`primary` border,
/// `corner.md` radius) but WITHOUT that component's stacked label-above-field row, which is what
/// misaligns the row against a same-height Save button. Not promoted to a `FindlyTextField`
/// variant/parameter because no other of `FindlyTextField`'s dozen-plus call sites want this
/// layout — §4.2 asks for one specific row, not a new general-purpose design-system option — so
/// this stays screen-local, reading `@Environment(\.theme)` the same way every other
/// `Screens/`-level view in this codebase already does (e.g. this file's own card text above).
private struct DeviceRenameField: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .disabled(!isEnabled)
            .focused($isFocused)
            .font(theme.typography.bodyLarge.font)
            .foregroundColor(isEnabled ? theme.colors.onSurface : .findlyTextFieldDisabledText)
            .padding(.horizontal, theme.spacing.sm)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(isEnabled ? theme.colors.surfaceVariant : .findlyTextFieldDisabledFill)
            .clipShape(RoundedRectangle(cornerRadius: theme.corner.md))
            .overlay(
                RoundedRectangle(cornerRadius: theme.corner.md)
                    .strokeBorder(borderColor, lineWidth: 1.5)
            )
            // The label lives here, not in a stacked `Text` above the field (§4.2's explicit
            // instruction) — VoiceOver still announces "Device name" regardless of the current
            // draft, matching how every other labeled control in this codebase names itself.
            .accessibilityLabel("Device name")
    }

    private var borderColor: Color {
        guard isEnabled else { return .findlyTextFieldDisabledBorder }
        return isFocused ? theme.colors.primary : theme.outlineStrong
    }
}
