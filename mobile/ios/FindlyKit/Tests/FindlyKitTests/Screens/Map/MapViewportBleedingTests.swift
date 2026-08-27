import Testing
@testable import FindlyKit
import SwiftUI
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// specs/010-app-shell-and-screen-ux.md §3.4 (I45 fix — TestFlight 220 regression). I39 made
/// `LiveMapScreen`/`GroupMapScreen`'s `GeometryReader` itself `.ignoresSafeArea()` to recover the
/// true full-bleed viewport size, but that pulled the reader's whole subtree (`topChrome`, the
/// `FindlyBottomSheet`) out of the safe area with it — the ☰/⌖ chrome drawn under the Dynamic
/// Island and untappable, the roster sheet leaving dead space at the bottom of every detent.
///
/// The actual safe-area LAYOUT behavior (chrome position, sheet sizing against a live view
/// hierarchy) is not unit-testable here — `swift test` is headless with no real window/notch to
/// lay out against, exactly as I39 correctly noted for the padding-vs-frame problem it solved.
/// What IS pure and testable is the arithmetic `MapViewport.bled` performs to recover the
/// full-bleed size from a constrained size + the insets that were subtracted to produce it —
/// this pins that math so it can't silently regress back to using the constrained size (which is
/// the exact bug this fix corrects: the sheet detent / camera fit math depends on getting the
/// truly full-bleed size, not the safe-area-shrunk one).
@MainActor
struct MapViewportBleedingTests {

    @Test func bled_addsAllFourInsetsBackOntoTheConstrainedSize() {
        let constrained = CGSize(width: 350, height: 700)
        let insets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)

        let bled = MapViewport.bled(constrained: constrained, safeAreaInsets: insets)
        let expectedHeight: CGFloat = 700 + 59 + 34

        #expect(bled.width == 350)
        #expect(bled.height == expectedHeight)
    }

    @Test func bled_addsLeadingAndTrailingInsetsToo_forLandscapeNotchOffsets() {
        // A landscape orientation on a notched device puts the safe-area cutout on the
        // leading/trailing edges instead of top/bottom — the fix must not assume portrait.
        let constrained = CGSize(width: 700, height: 350)
        let insets = EdgeInsets(top: 0, leading: 47, bottom: 21, trailing: 47)

        let bled = MapViewport.bled(constrained: constrained, safeAreaInsets: insets)
        let expectedWidth: CGFloat = 700 + 47 + 47
        let expectedHeight: CGFloat = 350 + 21

        #expect(bled.width == expectedWidth)
        #expect(bled.height == expectedHeight)
    }

    @Test func bled_isANoOp_whenThereAreNoSafeAreaInsets() {
        // e.g. an iPad/older device with no notch and no home indicator — the constrained size IS
        // already the full-bleed size, and the fix must not add spurious padding.
        let constrained = CGSize(width: 1024, height: 768)

        let bled = MapViewport.bled(constrained: constrained, safeAreaInsets: EdgeInsets())

        #expect(bled == constrained)
    }
}
