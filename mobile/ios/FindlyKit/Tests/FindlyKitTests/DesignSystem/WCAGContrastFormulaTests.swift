import SwiftUI
import Testing
@testable import FindlyKit

/// I29 (specs/004-ios-client §2.1): before trusting `WCAGContrast.ratio` against any real token
/// pairing, sanity-check it against a published reference. WebAIM's contrast checker (and the
/// WCAG 2.1 formula worked by hand) gives `#767676` on `#FFFFFF` = **4.54:1** exactly. If this
/// formula can't reproduce that one well-known number, every other assertion in
/// `ColorContrastPairingsTests.swift` is worthless — this test exists to fail loudly, first, if
/// that's ever true again.
struct WCAGContrastFormulaTests {

    @Test func sanityCheck_publishedReferenceGrayOnWhite_is454() {
        let ratio = WCAGContrast.ratio(Color(hex: 0x767676), Color(hex: 0xFFFFFF))
        #expect(
            abs(ratio - 4.54) < 0.01,
            """
            WCAGContrast.ratio computed \(ratio):1 for the published reference pairing #767676 on \
            #FFFFFF, but the correct WCAG 2.1 answer is 4.54:1 (WebAIM). The formula itself is \
            wrong — every other contrast assertion in this test suite is worthless until this one \
            is fixed, because they all depend on the same `WCAGContrast.ratio` function.
            """
        )
    }

    // MARK: - Formula edge cases (I29 code-review round 2 MINOR — the sanity check above only
    // covered the one WebAIM reference pairing; both reviewers noted the two textbook boundary
    // cases were untested. Android has the identical gap and is being told the same thing.)

    /// The maximum possible WCAG contrast ratio: pure black on pure white.
    @Test func edgeCase_blackOnWhite_is21to1() {
        let ratio = WCAGContrast.ratio(.black, .white)
        #expect(abs(ratio - 21.0) < 0.01, "black-on-white must measure 21:1 — the formula's own ceiling.")
    }

    /// Identical colors carry zero contrast against themselves — the formula's own floor,
    /// independent of which color it is (unlike black-on-black, which is also 1:1 but could
    /// coincidentally pass if the formula degenerated to always returning the minimum).
    @Test func edgeCase_identicalColors_is1to1() {
        #expect(abs(WCAGContrast.ratio(Color(hex: 0x3A46C8), Color(hex: 0x3A46C8)) - 1.0) < 0.0001)
        #expect(abs(WCAGContrast.ratio(.white, .white) - 1.0) < 0.0001)
    }
}
