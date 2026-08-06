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
    ///
    /// **Both platform branches below deliberately have the same rigor** (I29 code-review round 2,
    /// MAJOR finding): pin the color space to sRGB explicitly rather than trusting whatever space
    /// `UIColor`/`NSColor` happened to resolve into, and check the conversion's success rather than
    /// silently reading zeroed components (which would read as opaque black — a false pass or a
    /// false fail, indistinguishable from a real black token, with no signal that anything went
    /// wrong). This matters because `swift test` on a bare macOS host (this package's primary test
    /// gate — see Package.swift) only ever exercises the `#elseif canImport(AppKit)` branch;
    /// `#if canImport(UIKit)` — the platform the app actually ships on — only runs when a developer
    /// points Xcode at a Simulator/device destination, which no CI job in `.github/workflows/
    /// ios.yml` currently does (`ios-package` runs `swift test` on bare macOS, `ios-build` runs
    /// `xcodebuild build` but never `xcodebuild test`). Until that CI gap closes, an unchecked
    /// UIKit branch would be effectively unverified dead code for the one platform that matters.
    static func srgbComponents(of color: Color) -> (r: Double, g: Double, b: Double) {
        #if canImport(UIKit)
        guard let sRGBSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            fatalError("WCAGContrast.srgbComponents: sRGB CGColorSpace unavailable on this platform")
        }
        let platformColor = UIColor(color)
        guard let convertedCGColor = platformColor.cgColor.converted(to: sRGBSpace, intent: .defaultIntent, options: nil) else {
            fatalError("WCAGContrast.srgbComponents: could not convert \(color) into the sRGB color space")
        }
        let srgbColor = UIColor(cgColor: convertedCGColor)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard srgbColor.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            fatalError("WCAGContrast.srgbComponents: UIColor.getRed failed for \(color) — not representable as RGB even after forcing the sRGB color space")
        }
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
        // NSColor.getRed(_:green:blue:alpha:) is `Void`, not `Bool` (unlike UIColor's — the
        // asymmetry MAJOR 1 was about is in the color-space coercion, not this call's signature).
        // It traps at runtime rather than failing silently if `srgb` weren't RGB-representable,
        // which `usingColorSpace(.sRGB)` above already guarantees.
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

    /// WCAG 2.1 relative luminance from raw (already 0...1, sRGB, non-premultiplied) components.
    private static func relativeLuminance(r: Double, g: Double, b: Double) -> Double {
        0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    /// WCAG 2.1 relative luminance of an opaque `Color`.
    static func relativeLuminance(of color: Color) -> Double {
        let (r, g, b) = srgbComponents(of: color)
        return relativeLuminance(r: r, g: g, b: b)
    }

    private static func ratio(fromLuminances la: Double, _ lb: Double) -> Double {
        let (l1, l2) = la >= lb ? (la, lb) : (lb, la)
        return (l1 + 0.05) / (l2 + 0.05)
    }

    /// WCAG 2.1 contrast ratio: `(L1 + 0.05) / (L2 + 0.05)`, where `L1` is the lighter of the two
    /// relative luminances. Order of the two colors passed in doesn't matter. Assumes both colors
    /// are fully opaque as rendered — for a foreground drawn with `.opacity()`, use
    /// `ratio(foreground:alpha:background:)` instead, which composites first.
    static func ratio(_ a: Color, _ b: Color) -> Double {
        ratio(fromLuminances: relativeLuminance(of: a), relativeLuminance(of: b))
    }

    /// The contrast ratio for a `foreground` drawn at `alpha` opacity over `background`, measured
    /// against that same `background` — i.e. what actually reaches the eye, not the foreground
    /// color's own (irrelevant, since it's translucent) luminance.
    ///
    /// Added for I29 code-review round 2, MAJOR finding: `PermissionBannerView` draws
    /// `theme.colors.onSurface.opacity(...)` rather than an opaque token, and
    /// `srgbComponents`/`relativeLuminance` never read alpha — asserting those pairings directly
    /// would have silently scored the translucent color as if it were fully opaque, over-reporting
    /// its real contrast. Composites in sRGB (gamma, non-linear) space — a plain per-channel
    /// `alpha·fg + (1-alpha)·bg` blend of the 0...1 sRGB component values — because that is how
    /// UIKit/SwiftUI actually composite `.opacity()` (blending happens on the encoded/gamma pixel
    /// values, not in linear light), not the physically-idealized linear-light blend. Verified
    /// during I29 round 2 against an independently-computed reference for both banner pairings.
    static func ratio(foreground: Color, alpha: Double, background: Color) -> Double {
        precondition((0...1).contains(alpha), "WCAGContrast.ratio(foreground:alpha:background:): alpha must be in 0...1, got \(alpha)")
        let (fr, fg, fb) = srgbComponents(of: foreground)
        let (br, bg, bb) = srgbComponents(of: background)
        let compositedLuminance = relativeLuminance(
            r: alpha * fr + (1 - alpha) * br,
            g: alpha * fg + (1 - alpha) * bg,
            b: alpha * fb + (1 - alpha) * bb
        )
        return ratio(fromLuminances: compositedLuminance, relativeLuminance(of: background))
    }
}
