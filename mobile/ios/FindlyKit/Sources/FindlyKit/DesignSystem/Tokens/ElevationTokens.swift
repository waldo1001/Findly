import SwiftUI

/// SwiftUI has no native "elevation" concept — each level is a shadow spec components apply via
/// `.shadow(color:radius:x:y:)`-style modifiers, reading only these tokens (specs/004-ios-client.md
/// §2.1). `color` is neutral black at every level in both themes (design 2a "Ember/Dusk" —
/// "Shadows are neutral black in both themes. Do not tint them.") unless a component explicitly
/// documents a tinted override, e.g. `FindlyButton`'s primary style.
public struct ElevationLevel: Equatable {
    public var blur: CGFloat
    public var y: CGFloat
    public var opacity: Double
    public var color: Color

    public init(blur: CGFloat, y: CGFloat, opacity: Double, color: Color = .black) {
        self.blur = blur
        self.y = y
        self.opacity = opacity
        self.color = color
    }
}

public struct ElevationTokens: Equatable {
    public var level0: ElevationLevel
    public var level1: ElevationLevel
    public var level2: ElevationLevel
    public var level3: ElevationLevel

    public init(level0: ElevationLevel, level1: ElevationLevel, level2: ElevationLevel, level3: ElevationLevel) {
        self.level0 = level0
        self.level1 = level1
        self.level2 = level2
        self.level3 = level3
    }

    // design 2a "Ember/Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md) — blur/y/color
    // are scheme-independent; only opacity differs (dark needs a stronger shadow to read against a
    // dark surface), which is why `.light` and `.dark` are separate instances rather than one
    // `.standard` shared value.
    public static let light = ElevationTokens(
        level0: ElevationLevel(blur: 0, y: 0, opacity: 0),
        level1: ElevationLevel(blur: 8, y: 2, opacity: 0.10),
        level2: ElevationLevel(blur: 24, y: 8, opacity: 0.14),
        level3: ElevationLevel(blur: 48, y: 16, opacity: 0.18)
    )

    public static let dark = ElevationTokens(
        level0: ElevationLevel(blur: 0, y: 0, opacity: 0),
        level1: ElevationLevel(blur: 8, y: 2, opacity: 0.30),
        level2: ElevationLevel(blur: 24, y: 8, opacity: 0.45),
        level3: ElevationLevel(blur: 48, y: 16, opacity: 0.60)
    )
}
