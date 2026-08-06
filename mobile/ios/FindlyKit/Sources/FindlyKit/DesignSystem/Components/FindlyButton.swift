import SwiftUI

/// specs/004-ios-client.md §2.3 — stateless, presentational. Reads `\.theme` only; takes content
/// via parameters. Zero knowledge of view models/networking/navigation.
///
/// design 2a "Ember/Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md): primary,
/// secondary and destructive. Destructive is never a filled red button — it's the secondary
/// geometry with a `danger`-colored border and label.
public enum FindlyButtonStyleKind: Equatable {
    case primary
    case secondary
    case destructive
}

public struct FindlyButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool
    private let title: String
    private let style: FindlyButtonStyleKind
    private let action: () -> Void

    public init(_ title: String, style: FindlyButtonStyleKind = .primary, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            // 16/600 — the button label size in the handoff's component specimen; not one of the
            // six named type roles (closest, titleMedium, is 18/600), so it's literal here rather
            // than borrowed from a role that doesn't match.
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(foregroundColor)
                .frame(maxWidth: .infinity)
                // Height 52 (48 inline in a header row is a screen-level composition choice, out
                // of scope here — I27 ships the standalone 52pt button).
                .frame(height: 52)
                .background(background)
                .overlay(border)
                .clipShape(RoundedRectangle(cornerRadius: theme.corner.pill))
                .overlay(focusRing)
        }
        .buttonStyle(FindlyOpacityDimButtonStyle())
        .focused($isFocused)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary:
            RoundedRectangle(cornerRadius: theme.corner.pill)
                .fill(isEnabled ? theme.colors.primary : theme.colors.surfaceVariant)
                // level2 shadow tinted with `primary` on light (rgba(58,70,200,.35) — exactly
                // `theme.colors.primary` at 35% there); the same expression carries the tint
                // through to dark automatically since `theme.colors.primary` is scheme-resolved.
                // Disabled buttons never cast a shadow.
                .shadow(
                    color: isEnabled ? theme.colors.primary.opacity(0.35) : .clear,
                    radius: theme.elevation.level2.blur,
                    y: theme.elevation.level2.y
                )
        case .secondary, .destructive:
            Color.clear
        }
    }

    @ViewBuilder
    private var border: some View {
        switch style {
        case .primary:
            EmptyView()
        case .secondary:
            RoundedRectangle(cornerRadius: theme.corner.pill)
                .strokeBorder(theme.outlineStrong, lineWidth: 1.5)
        case .destructive:
            RoundedRectangle(cornerRadius: theme.corner.pill)
                .strokeBorder(theme.colors.danger, lineWidth: 1.5)
        }
    }

    /// Focused: 3px `surface` ring then 3px `rgba(primary,.55)` — a double ring so it separates
    /// from the button's own fill before the tinted outer ring starts.
    @ViewBuilder
    private var focusRing: some View {
        if isFocused {
            RoundedRectangle(cornerRadius: theme.corner.pill)
                .strokeBorder(theme.colors.surface, lineWidth: 3)
                .padding(-3)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.corner.pill)
                        .strokeBorder(theme.colors.primary.opacity(0.55), lineWidth: 3)
                        .padding(-6)
                )
        }
    }

    private var foregroundColor: Color {
        guard isEnabled else { return Color(hex: 0x8D93AB) }
        switch style {
        case .primary: return theme.colors.onPrimary
        case .secondary: return theme.colors.onSurface
        case .destructive: return theme.colors.danger
        }
    }
}

/// design 2a "Ember/Dusk": iOS presses dim to 0.85 opacity rather than the ripple/fill-swap the
/// handoff's cross-platform mock shows — the explicit iOS/Android divergence this handoff calls
/// out ("Presses: opacity dim on iOS, ripple on Android. Do not cross-port.").
struct FindlyOpacityDimButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

#Preview("FindlyButton — light") {
    VStack(spacing: 16) {
        FindlyButton("Continue", style: .primary) {}
        FindlyButton("Continue", style: .primary) {}.disabled(true)
        FindlyButton("Not now", style: .secondary) {}
        FindlyButton("Remove Lina's iPad", style: .destructive) {}
    }
    .padding()
    .background(Theme.light.colors.surface)
    .environment(\.theme, .light)
}

#Preview("FindlyButton — dark") {
    VStack(spacing: 16) {
        FindlyButton("Continue", style: .primary) {}
        FindlyButton("Continue", style: .primary) {}.disabled(true)
        FindlyButton("Not now", style: .secondary) {}
        FindlyButton("Remove Lina's iPad", style: .destructive) {}
    }
    .padding()
    .background(Theme.dark.colors.surface)
    .environment(\.theme, .dark)
    .preferredColorScheme(.dark)
}
