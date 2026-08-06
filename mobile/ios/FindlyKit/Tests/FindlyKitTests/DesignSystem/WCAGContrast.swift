#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import SwiftUI

/// WCAG 2.1 contrast-ratio support for the design-token contrast test suite (specs/004-ios-client
/// §2.1, backlog task I29). This exists **only** to let `ColorContrastPairingsTests.swift` fail the
/// build when a declared token pairing drops below its WCAG threshold — see
/// `design/findly-design-system/2a-ember-dusk/HANDOFF.md`, whose own contrast table was wrong in
/// four ways that would have shipped (see `ColorContrastPairingsTests.swift` for the pinned
/// regressions). Test-only by design (I29 scope): production code never needs raw RGB components
/// back out of a `Color`.
enum WCAGContrast {

    /// `SwiftUI.Color` doesn't expose its RGB components — this is the "minimal accessor" the I29
    /// task anticipated needing. Only reliable for colors built from fixed literals (as every
    /// token color in `ColorTokens.swift` / `Color.findlyX` is, via `Color(hex:)`), not for
    /// dynamic/system colors whose components depend on trait collection or appearance — none of
    /// the pairings asserted here are dynamic.
    static func srgbComponents(of color: Color) -> (r: Double, g: Double, b: Double) {
        #if canImport(UIKit)
        let platformColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        platformColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
        #elseif canImport(AppKit)
        let platformColor = NSColor(color)
        // NSColor(Color) can resolve into a color space that doesn't support
        // getRed(_:green:blue:alpha:) directly (e.g. a catalog/dynamic space) — convert to
        // calibrated sRGB first so this never crashes on a colorspace mismatch. `swift test` on a
        // plain macOS host (no Xcode/simulator — see Package.swift) runs this AppKit path.
        guard let srgb = platformColor.usingColorSpace(.sRGB) else {
            fatalError("WCAGContrast.srgbComponents: could not resolve \(color) into the sRGB color space")
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
        #else
        fatalError("WCAGContrast.srgbComponents: neither UIKit nor AppKit is available on this platform")
        #endif
    }

    /// sRGB → linear-light channel, per the WCAG 2.1 definition of relative luminance
    /// (https://www.w3.org/TR/WCAG21/#dfn-relative-luminance).
    private static func linearize(_ channel: Double) -> Double {
        channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    /// WCAG 2.1 relative luminance.
    static func relativeLuminance(of color: Color) -> Double {
        let (r, g, b) = srgbComponents(of: color)
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    /// WCAG 2.1 contrast ratio: `(L1 + 0.05) / (L2 + 0.05)`, where `L1` is the lighter of the two
    /// relative luminances. Order of the two colors passed in doesn't matter.
    static func ratio(_ a: Color, _ b: Color) -> Double {
        let la = relativeLuminance(of: a)
        let lb = relativeLuminance(of: b)
        let (l1, l2) = la >= lb ? (la, lb) : (lb, la)
        return (l1 + 0.05) / (l2 + 0.05)
    }
}
