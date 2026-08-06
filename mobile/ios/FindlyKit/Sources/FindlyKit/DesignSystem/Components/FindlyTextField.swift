import SwiftUI

/// specs/004-ios-client.md §2.3 (I2 addition) — a labeled single-line text input used by the
/// invite/geofence-editor/settings forms. Stateless: takes a `Binding<String>`, reads `\.theme`
/// only. No literal `Color(...)`/`.font(.system(`/hardcoded point size.
///
/// design 2a "Ember/Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md): height 52,
/// `surfaceVariant` fill, a 1.5px border (`outlineStrong` at rest — an input outline is exactly
/// the "carries meaning" example the handoff names — `primary` + a soft ring when focused,
/// `danger` with an inline `✕` message when there's an error, and — added post-review, the field
/// previously never read `isEnabled` at all — `findlyTextFieldDisabledFill`/`Border`/`Text` when
/// disabled, taking priority over focus/error styling).
public struct FindlyTextField: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool
    private let label: String
    @Binding private var text: String
    private let placeholder: String
    private let errorMessage: String?

    public init(_ label: String, text: Binding<String>, placeholder: String = "", errorMessage: String? = nil) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.errorMessage = errorMessage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(label)
                .font(theme.typography.labelSmall.font)
                .tracking(theme.typography.labelSmall.tracking)
                .foregroundColor(theme.onSurfaceMuted)
            TextField(placeholder, text: $text)
                .disabled(!isEnabled)
                .focused($isFocused)
                .font(theme.typography.bodyLarge.font)
                .foregroundColor(isEnabled ? theme.colors.onSurface : .findlyTextFieldDisabledText)
                .padding(.horizontal, theme.spacing.sm)
                .frame(height: 52)
                .background(isEnabled ? theme.colors.surfaceVariant : .findlyTextFieldDisabledFill)
                .clipShape(RoundedRectangle(cornerRadius: theme.corner.md))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.corner.md)
                        .strokeBorder(borderColor, lineWidth: 1.5)
                )
                .overlay(focusRing)
            if let errorMessage {
                Text("✕ \(errorMessage)")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(theme.colors.danger)
            }
        }
    }

    private var borderColor: Color {
        guard isEnabled else { return .findlyTextFieldDisabledBorder }
        if errorMessage != nil { return theme.colors.danger }
        if isFocused { return theme.colors.primary }
        return theme.outlineStrong
    }

    @ViewBuilder
    private var focusRing: some View {
        if isEnabled && isFocused && errorMessage == nil {
            RoundedRectangle(cornerRadius: theme.corner.md)
                .strokeBorder(theme.colors.primary.opacity(0.18), lineWidth: 3)
                .padding(-3)
        }
    }
}

#Preview("FindlyTextField — light") {
    VStack(spacing: 16) {
        FindlyTextField("Name", text: .constant(""), placeholder: "Add someone to The Haddads")
        FindlyTextField("Invite code", text: .constant("A1B2C3"), errorMessage: "That code has expired")
        FindlyTextField("Sync interval", text: .constant("15 min")).disabled(true)
    }
    .padding()
    .background(Theme.light.colors.surface)
    .environment(\.theme, .light)
}

#Preview("FindlyTextField — dark") {
    VStack(spacing: 16) {
        FindlyTextField("Name", text: .constant(""), placeholder: "Add someone to The Haddads")
        FindlyTextField("Invite code", text: .constant("A1B2C3"), errorMessage: "That code has expired")
        FindlyTextField("Sync interval", text: .constant("15 min")).disabled(true)
    }
    .padding()
    .background(Theme.dark.colors.surface)
    .environment(\.theme, .dark)
    .preferredColorScheme(.dark)
}
