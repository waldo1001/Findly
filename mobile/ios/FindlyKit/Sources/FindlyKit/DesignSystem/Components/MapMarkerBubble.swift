import SwiftUI

/// specs/004-ios-client.md §2.3 — a family member's position bubble on the live map.
///
/// design 2a "Ember/Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md) has three
/// states: `.normal` (fresh fix, filled `primary` pill + "● NOW" badge), `.stale` (dashed
/// `warning` outline, an age badge like "24m"), and `.noLocation` (a 52pt dashed circle with "?",
/// never placed on the map — shown only as a row's leading element for a device that has never
/// checked in).
public enum MapMarkerBubbleState: Equatable {
    case normal
    case stale
    case noLocation
}

public struct MapMarkerBubble: View {
    @Environment(\.theme) private var theme
    private let initials: String
    private let name: String?
    private let state: MapMarkerBubbleState
    private let badgeText: String?

    public init(initials: String, name: String? = nil, state: MapMarkerBubbleState = .normal, badgeText: String? = nil) {
        self.initials = initials
        self.name = name
        self.state = state
        self.badgeText = badgeText
    }

    /// Back-compat for the pre-I27 call site (Screens/Map/MapRendering.swift); I28 (screens wave)
    /// migrates callers to the fuller state-based initializer above.
    public init(initials: String, isStale: Bool) {
        self.init(initials: initials, state: isStale ? .stale : .normal)
    }

    public var body: some View {
        switch state {
        case .normal, .stale:
            pill
        case .noLocation:
            noLocationCircle
        }
    }

    private var pill: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                avatar
                if let name {
                    Text(name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(state == .normal ? theme.colors.onPrimary : theme.colors.onSurface)
                }
                if let badgeText {
                    badge(badgeText)
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .frame(height: 44)
            .background(pillBackground)
            .overlay(pillBorder)
            .clipShape(Capsule())
            .shadow(
                color: state == .normal ? Color.black.opacity(theme.elevation.level3.opacity) : .clear,
                radius: theme.elevation.level3.blur,
                y: theme.elevation.level3.y
            )

            // 7pt triangular tail.
            Triangle()
                .fill(state == .normal ? theme.colors.primary : theme.colors.surface)
                .frame(width: 14, height: 7)
        }
    }

    private var avatar: some View {
        Text(initials)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(theme.colors.onPrimary)
            .frame(width: 32, height: 32)
            .background(theme.colors.primary)
            .clipShape(Circle())
    }

    @ViewBuilder
    private var pillBackground: some View {
        switch state {
        case .normal: theme.colors.primary
        case .stale: theme.colors.surface
        case .noLocation: EmptyView()
        }
    }

    @ViewBuilder
    private var pillBorder: some View {
        if state == .stale {
            Capsule()
                .strokeBorder(theme.colors.warning, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
        }
    }

    private func badge(_ text: String) -> some View {
        Group {
            if state == .normal {
                // "● NOW" — fixed #52E39B fill / #062418 text in BOTH themes (design 2a contrast
                // trap #2: light `success` measures 1.2:1 here and must never be substituted in).
                HStack(spacing: 3) {
                    Text("●")
                    Text(text)
                }
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(.findlyMarkerOnlineDotOn)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(Color.findlyMarkerOnlineDot)
                .clipShape(Capsule())
            } else {
                HStack(spacing: 3) {
                    Text("▲")
                    Text(text)
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(theme.colors.warning)
            }
        }
    }

    /// "No location yet" — a device that has never checked in. Not placed on the map; used as a
    /// row's leading element instead of `MapMarkerBubble.pill`.
    private var noLocationCircle: some View {
        Text("?")
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(theme.colors.onSurface)
            .frame(width: 52, height: 52)
            .background(theme.colors.surfaceVariant)
            .clipShape(Circle())
            .overlay(
                Circle().strokeBorder(theme.outlineStrong, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            )
    }
}

/// design 2a "Ember/Dusk" — the geofence radius overlay on the map: a 2px `primary` stroke over a
/// 10%-opacity `primary` fill. A plain SwiftUI shape (no map-SDK dependency), so it lives in
/// DesignSystem/Components like the rest of the map-adjacent presentational pieces.
public struct GeofenceCircleOverlay: View {
    @Environment(\.theme) private var theme
    public init() {}
    public var body: some View {
        Circle()
            .fill(theme.colors.primary.opacity(0.10))
            .overlay(Circle().strokeBorder(theme.colors.primary, lineWidth: 2))
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

#Preview("MapMarkerBubble — light") {
    VStack(spacing: 24) {
        MapMarkerBubble(initials: "N", name: "Noor", state: .normal, badgeText: "NOW")
        MapMarkerBubble(initials: "S", name: "Sam", state: .stale, badgeText: "24m")
        MapMarkerBubble(initials: "?", state: .noLocation)
        GeofenceCircleOverlay().frame(width: 120, height: 120)
    }
    .padding()
    .background(Theme.light.colors.surface)
    .environment(\.theme, .light)
}

#Preview("MapMarkerBubble — dark") {
    VStack(spacing: 24) {
        MapMarkerBubble(initials: "N", name: "Noor", state: .normal, badgeText: "NOW")
        MapMarkerBubble(initials: "S", name: "Sam", state: .stale, badgeText: "24m")
        MapMarkerBubble(initials: "?", state: .noLocation)
        GeofenceCircleOverlay().frame(width: 120, height: 120)
    }
    .padding()
    .background(Theme.dark.colors.surface)
    .environment(\.theme, .dark)
    .preferredColorScheme(.dark)
}
