import SwiftUI

/// specs/004-ios-client.md I2 (001 §7.1–7.2) — the add/edit form for a single circular geofence:
/// name, icon (free string ≤ 30 chars, §7.1), coordinates, radius (100–5000 m per §7.2), and the
/// two notify flags. Composes ONLY design-system components; the radius `Slider` is tinted via
/// `theme.colors.primary` (a token reference, never a literal `Color`).
public struct GeofenceEditorView: View {
    @Environment(\.theme) private var theme
    @State private var name: String
    @State private var lat: String
    @State private var lon: String
    @State private var radiusM: Double
    @State private var icon: String
    @State private var notifyOnEnter: Bool
    @State private var notifyOnExit: Bool

    private let originalId: String?
    private let existingIds: Set<String>
    private let onSave: (Geofence) -> Void
    private let onCancel: () -> Void

    public init(geofence: Geofence?, existingIds: Set<String>, onSave: @escaping (Geofence) -> Void, onCancel: @escaping () -> Void) {
        self.originalId = geofence?.geofenceId
        self.existingIds = existingIds.subtracting(geofence.map { [$0.geofenceId] } ?? [])
        self._name = State(initialValue: geofence?.name ?? "")
        self._lat = State(initialValue: geofence.map { String($0.lat) } ?? "")
        self._lon = State(initialValue: geofence.map { String($0.lon) } ?? "")
        self._radiusM = State(initialValue: geofence?.radiusM ?? 150)
        self._icon = State(initialValue: geofence?.icon ?? "home")
        self._notifyOnEnter = State(initialValue: geofence?.notifyOnEnter ?? true)
        self._notifyOnExit = State(initialValue: geofence?.notifyOnExit ?? true)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    public var body: some View {
        content
            // specs/004 §2.5 — this view is presented MODALLY (a sheet), so it is not part of the
            // coordinator's navigation stack. SwiftUI propagates custom environment values into
            // sheet content, so without this clear its `FindlyNavBar` would render the app-level
            // back chevron and popping it would navigate the app *behind* a sheet that stays up.
            // Dismissal here is the explicit Cancel/Save buttons below, nothing else.
            .environment(\.navBarBackAction, nil)
    }

    private var content: some View {
        VStack(spacing: 0) {
            FindlyNavBar(originalId == nil ? "Add geofence" : "Edit geofence")
            ScrollView {
                VStack(spacing: theme.spacing.md) {
                    FindlyTextField("Name", text: $name, placeholder: "Home")
                    FindlyTextField("Icon", text: $icon, placeholder: "home")
                    FindlyTextField("Latitude", text: $lat, placeholder: "51.0543")
                    FindlyTextField("Longitude", text: $lon, placeholder: "3.7174")
                    VStack(alignment: .leading, spacing: theme.spacing.xs) {
                        Text("Radius: \(Int(radiusM))m")
                            .font(theme.typography.labelSmall)
                            .foregroundColor(theme.colors.onSurface.opacity(0.7))
                        Slider(value: $radiusM, in: 100...5000, step: 50)
                            .tint(theme.colors.primary)
                    }
                    FindlyToggleRow(title: "Notify on arrival", isOn: $notifyOnEnter)
                    FindlyToggleRow(title: "Notify on departure", isOn: $notifyOnExit)
                    HStack(spacing: theme.spacing.sm) {
                        FindlyButton("Cancel", style: .secondary, action: onCancel)
                        FindlyButton("Save", action: save)
                    }
                }
                .padding(theme.spacing.md)
            }
        }
        .background(theme.colors.surfaceVariant)
    }

    private func save() {
        guard let latValue = Double(lat), let lonValue = Double(lon) else { return }
        let id = originalId ?? GeofenceIdGenerating.makeId(from: name, existingIds: existingIds)
        // specs/001 §7.1 — icon is a free string ≤ 30 chars, client-rendered only; clamp
        // defensively (a review-gate finding — the field was previously captured but never
        // user-editable, so it silently stayed "home").
        let trimmedIcon = String(icon.prefix(30))
        let geofence = Geofence(
            geofenceId: id, name: name.isEmpty ? "Unnamed" : name, lat: latValue, lon: lonValue,
            radiusM: radiusM, icon: trimmedIcon.isEmpty ? "home" : trimmedIcon,
            notifyOnEnter: notifyOnEnter, notifyOnExit: notifyOnExit
        )
        onSave(geofence)
    }
}
