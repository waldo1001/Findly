import SwiftUI

/// specs/004-ios-client.md I2 (001 §7.1–7.2) — retroactive `Identifiable` conformance (keyed on the
/// server-assigned `geofenceId`) so `Geofence` values can drive `.sheet(item:)` in the editor below;
/// `Geofence` itself stays defined in `Networking/Endpoints/GeofencesEndpoints.swift` (I1).
extension Geofence: Identifiable {
    public var id: String { geofenceId }
}

/// specs/004-ios-client.md I2 — the geofences list + add/edit/delete editor. Composes ONLY
/// design-system components; local `drafts` holds in-progress edits until "Save changes" commits
/// them via the ETag-aware `GeofencesViewModel.save(_:)`.
public struct GeofencesScreen: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var viewModel: GeofencesViewModel
    @State private var drafts: [Geofence] = []
    @State private var editing: Geofence?
    @State private var isAddingNew = false

    public init(viewModel: GeofencesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            FindlyNavBar("Geofences")
            content
        }
        .background(theme.colors.surfaceVariant)
        .task { await viewModel.load() }
        .onChange(of: loadedGeofences) { drafts = $0 }
        .sheet(item: $editing) { geofence in
            GeofenceEditorView(
                geofence: geofence, existingIds: Set(drafts.map(\.geofenceId)),
                onSave: { updated in upsert(updated); editing = nil },
                onCancel: { editing = nil }
            )
        }
        .sheet(isPresented: $isAddingNew) {
            GeofenceEditorView(
                geofence: nil, existingIds: Set(drafts.map(\.geofenceId)),
                onSave: { created in drafts.append(created); isAddingNew = false },
                onCancel: { isAddingNew = false }
            )
        }
    }

    private var loadedGeofences: [Geofence] {
        if case .loaded(let geofences, _) = viewModel.state { return geofences }
        return []
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingStateView(message: "Loading geofences…")
        case .error(let message):
            ErrorStateView(message: message) {
                Task { await viewModel.load() }
            }
        case .loaded:
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: theme.spacing.md) {
                if case .versionConflict(let serverGeofences, _) = viewModel.conflict {
                    ErrorStateView(message: "Someone else updated the geofences.", retryTitle: "Use latest") {
                        viewModel.acceptServerVersion()
                        drafts = serverGeofences
                    }
                }
                if drafts.isEmpty {
                    EmptyStateView(title: "No geofences yet", message: "Add one to get notified when family arrives or leaves.")
                } else {
                    ForEach(drafts) { geofence in
                        FindlyListRow(title: geofence.name, subtitle: "\(Int(geofence.radiusM))m radius") {
                            HStack(spacing: theme.spacing.sm) {
                                FindlyButton("Edit", style: .secondary) { editing = geofence }
                                FindlyButton("Delete", style: .secondary) { delete(geofence) }
                            }
                        }
                    }
                }
                FindlyButton("Add geofence") { isAddingNew = true }
                FindlyButton(viewModel.isSaving ? "Saving…" : "Save changes", style: .secondary) {
                    Task { await viewModel.save(drafts) }
                }
                .disabled(viewModel.isSaving)
            }
            .padding(theme.spacing.md)
        }
    }

    private func upsert(_ geofence: Geofence) {
        if let index = drafts.firstIndex(where: { $0.geofenceId == geofence.geofenceId }) {
            drafts[index] = geofence
        } else {
            drafts.append(geofence)
        }
    }

    private func delete(_ geofence: Geofence) {
        drafts.removeAll { $0.geofenceId == geofence.geofenceId }
    }
}
