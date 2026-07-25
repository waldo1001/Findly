import CoreGraphics

/// SwiftUI has no native "elevation" concept — each level is a shadow spec components apply via
/// `.shadow(radius:x:y:)`-style modifiers, reading only these tokens (specs/004-ios-client.md §2.1).
public struct ElevationLevel: Equatable {
    public var radius: CGFloat
    public var y: CGFloat
    public var opacity: Double

    public init(radius: CGFloat, y: CGFloat, opacity: Double) {
        self.radius = radius
        self.y = y
        self.opacity = opacity
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

    public static let standard = ElevationTokens(
        level0: ElevationLevel(radius: 0, y: 0, opacity: 0),
        level1: ElevationLevel(radius: 2, y: 1, opacity: 0.08),
        level2: ElevationLevel(radius: 4, y: 2, opacity: 0.12),
        level3: ElevationLevel(radius: 8, y: 4, opacity: 0.16)
    )
}
