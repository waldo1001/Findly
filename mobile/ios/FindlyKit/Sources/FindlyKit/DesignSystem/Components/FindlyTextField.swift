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
///
/// specs/010-app-shell-and-screen-ux.md §4.2 (review fix, I36 round 2) — `label` is now optional:
/// a `nil` label omits the stacked label row entirely, for a single aligned field+control row
/// (e.g. the Devices screen's rename row, next to a same-height Save button) where a
/// label-above-field stack would misalign the pair. Every existing call site passes `label`
/// positionally as a non-optional `String` literal, which Swift promotes to `String?`
/// automatically, so none of them needed to change. Mirrors Android's `FindlyTextField.kt`
/// (`label: String? = null` since A2) and its merged `DevicesScreen.kt`, which already solves
/// this identical layout with a `nil`-label call.
public struct FindlyTextField: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool
    private let label: String?
    @Binding private var text: String
    private let placeholder: String
    private let errorMessage: String?

    public init(_ label: String?, text: Binding<String>, placeholder: String = "", errorMessage: String? = nil) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.errorMessage = errorMessage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            if let label {
                Text(label)
                    .font(theme.typography.labelSmall.font)
                    .tracking(theme.typography.labelSmall.tracking)
                    .foregroundColor(theme.onSurfaceMuted)
            }
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
                // §4.2: "carries its label via placeholder + accessibility label" when there is
                // no stacked label Text above it — explicit here (rather than relying on
                // TextField's own default title-as-accessibility-label behavior) so VoiceOver
                // naming is guaranteed regardless of SwiftUI version. Harmless when `label` is
                // present: it names the field exactly what the visible label already says.
                .accessibilityLabel(label ?? placeholder)
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
        // specs/010-app-shell-and-screen-ux.md §4.2 — the label-less form (nil label), used
        // beside a same-height Save button in a single aligned row (Devices screen rename row).
        FindlyTextField(nil, text: .constant("Eric's phone"), placeholder: "Device name")
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
        FindlyTextField(nil, text: .constant("Eric's phone"), placeholder: "Device name")
    }
    .padding()
    .background(Theme.dark.colors.surface)
    .environment(\.theme, .dark)
    .preferredColorScheme(.dark)
}
