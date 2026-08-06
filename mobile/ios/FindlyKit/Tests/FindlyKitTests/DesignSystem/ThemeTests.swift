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

    @Test func typographySpacingAndCornerAreIdenticalAcrossSchemes() {
        // Typography, spacing and corner radius don't change with color scheme (specs/004 §2.1).
        #expect(Theme.light.typography == Theme.dark.typography)
        #expect(Theme.light.spacing == Theme.dark.spacing)
        #expect(Theme.light.corner == Theme.dark.corner)
    }

    // design 2a "Ember/Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md): elevation
    // opacity is scheme-dependent (dark needs a stronger shadow to read against a dark surface),
    // so — unlike typography/spacing/corner — light and dark elevation are NOT identical. This is
    // a deliberate change from the previous (2026-07-20) single shared `ElevationTokens.standard`.
    @Test func elevationDiffersBetweenSchemes_opacityOnly() {
        #expect(Theme.light.elevation != Theme.dark.elevation)
        // blur/y/color are scheme-independent — only opacity should differ.
        #expect(Theme.light.elevation.level1.blur == Theme.dark.elevation.level1.blur)
        #expect(Theme.light.elevation.level1.y == Theme.dark.elevation.level1.y)
        #expect(Theme.light.elevation.level1.color == Theme.dark.elevation.level1.color)
        #expect(Theme.light.elevation.level1.opacity != Theme.dark.elevation.level1.opacity)
    }

    @Test func elevationLevelsAreMonotonicallyIncreasing_light() {
        let e = ElevationTokens.light
        #expect(e.level0.blur <= e.level1.blur)
        #expect(e.level1.blur <= e.level2.blur)
        #expect(e.level2.blur <= e.level3.blur)
        #expect(e.level0.opacity <= e.level1.opacity)
        #expect(e.level1.opacity <= e.level2.opacity)
        #expect(e.level2.opacity <= e.level3.opacity)
    }

    @Test func elevationLevelsAreMonotonicallyIncreasing_dark() {
        let e = ElevationTokens.dark
        #expect(e.level0.blur <= e.level1.blur)
        #expect(e.level1.blur <= e.level2.blur)
        #expect(e.level2.blur <= e.level3.blur)
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
