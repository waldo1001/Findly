import SwiftUI

/// specs/004-ios-client.md §2.3 — e.g. a device's live/stale/paused state (001 §5.2 `isStale`,
/// §5.1 `trackingEnabled`), plus a `danger` kind for alert-style chips.
///
/// design 2a "Ember/Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md): "Status is
/// never colour alone" — every chip renders a kind-specific glyph ahead of the caller's word, so
/// it still reads in greyscale. The caller's `text` stays free-form (existing screens pass e.g.
/// "Couldn't reach device — showing last known", not the handoff's literal "STALE"), matching how
/// this component was already used before I27; only the glyph and styling are new.
public enum StatusChipKind: Equatable {
    case online
    case stale
    case paused
    case danger
}

public struct StatusChip: View {
    @Environment(\.theme) private var theme
    private let text: String
    private let kind: StatusChipKind

    public init(_ text: String, kind: StatusChipKind) {
        self.text = text
        self.kind = kind
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text(glyph)
            Text(text)
        }
        // 10.5/700, uppercase, +0.3 tracking — the chip's own literal label spec (labelSmall is
        // close but not identical: 12/700/uppercase/+0.4).
        .font(.system(size: 10.5, weight: .bold))
        .tracking(0.3)
        .textCase(.uppercase)
        .foregroundColor(foregroundColor)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(background)
        .overlay(border)
        .clipShape(RoundedRectangle(cornerRadius: theme.corner.pill))
        // The word carries the same meaning the glyph and color do — never drop it for
        // VoiceOver just because the glyph is decorative-looking.
        .accessibilityElement(children: .combine)
    }

    private var glyph: String {
        switch kind {
        case .online: return "●"
        case .stale: return "▲"
        case .paused: return "▮▮"
        case .danger: return "✕"
        }
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .online: theme.colors.success
        case .stale: theme.colors.warning
        case .paused: Color.clear
        case .danger: theme.colors.danger
        }
    }

    @ViewBuilder
    private var border: some View {
        if kind == .paused {
            // The outline carries the row's whole status here (no fill) — a meaningful stroke,
            // not a decorative hairline, so it uses the stronger `outlineStrong` color.
            RoundedRectangle(cornerRadius: theme.corner.pill)
                .strokeBorder(theme.outlineStrong, lineWidth: 1.5)
        }
    }

    private var foregroundColor: Color {
        switch kind {
        case .online, .danger: return theme.colors.onDanger
        case .stale: return .white
        case .paused: return theme.colors.onSurface
        }
    }
}

#Preview("StatusChip — light") {
    HStack(spacing: 8) {
        StatusChip("Online", kind: .online)
        StatusChip("Stale", kind: .stale)
        StatusChip("Paused", kind: .paused)
        StatusChip("Alert", kind: .danger)
    }
    .padding()
    .background(Theme.light.colors.surface)
    .environment(\.theme, .light)
}

#Preview("StatusChip — dark") {
    HStack(spacing: 8) {
        StatusChip("Online", kind: .online)
        StatusChip("Stale", kind: .stale)
        StatusChip("Paused", kind: .paused)
        StatusChip("Alert", kind: .danger)
    }
    .padding()
    .background(Theme.dark.colors.surface)
    .environment(\.theme, .dark)
    .preferredColorScheme(.dark)
}
