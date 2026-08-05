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

    public init(viewModel: @autoclosure @escaping () -> LiveMapViewModel, renderer: any MapRendering) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.renderer = renderer
    }

    public var body: some View {
        VStack(spacing: 0) {
            FindlyNavBar("Family map")
            content
        }
        .background(theme.colors.surfaceVariant)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
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
                                        .font(theme.typography.titleMedium)
                                        .foregroundColor(theme.colors.onSurface)
                                    if member.devices.isEmpty {
                                        Text("No devices registered")
                                            .font(theme.typography.bodyMedium)
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
