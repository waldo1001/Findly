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
}
