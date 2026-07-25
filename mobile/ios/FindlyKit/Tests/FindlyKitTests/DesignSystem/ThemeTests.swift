import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §2.1, §2.2 — both `Theme.light` and `Theme.dark` MUST populate every
/// token from day one, and the color tokens MUST actually differ between schemes (a design system
/// that ships identical light/dark colors isn't really shipping dark mode).
struct ThemeTests {

    @Test func lightAndDarkThemesBothExist_andAreDistinct() {
        #expect(Theme.light != Theme.dark)
        #expect(Theme.light.colors != Theme.dark.colors)
    }

    @Test func typographyIsIdenticalAcrossSchemes() {
        // Typography doesn't change with color scheme (specs/004 §2.1).
        #expect(Theme.light.typography == Theme.dark.typography)
        #expect(Theme.light.spacing == Theme.dark.spacing)
        #expect(Theme.light.corner == Theme.dark.corner)
        #expect(Theme.light.elevation == Theme.dark.elevation)
    }

    @Test func elevationLevelsAreMonotonicallyIncreasing() {
        let e = ElevationTokens.standard
        #expect(e.level0.radius <= e.level1.radius)
        #expect(e.level1.radius <= e.level2.radius)
        #expect(e.level2.radius <= e.level3.radius)
        #expect(e.level0.opacity <= e.level1.opacity)
        #expect(e.level1.opacity <= e.level2.opacity)
        #expect(e.level2.opacity <= e.level3.opacity)
    }

    @Test func spacingScaleIsMonotonicallyIncreasing() {
        let s = SpacingTokens.standard
        #expect(s.xs < s.sm)
        #expect(s.sm < s.md)
        #expect(s.md < s.lg)
        #expect(s.lg < s.xl)
        #expect(s.xl < s.xxl)
    }
}
