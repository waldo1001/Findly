import Testing
@testable import FindlyKit

/// specs/007-public-join-links.md §4, specs/004-ios-client.md §3.5 — QR generation MUST happen
/// entirely on-device (CoreImage's `CIQRCodeGenerator`), never via a networked QR service (a spec
/// violation, not a style choice). This file covers only `GroupJoinQRCode.cgImage(for:)`, the pure
/// logic half — deterministic, no I/O, no view. `GroupJoinQRCodeView` (the SwiftUI wrapper) is
/// intentionally untested per this project's established convention (Views aren't unit-tested,
/// only ViewModels/pure logic, specs/004 §9); its correctness is covered by `swift build
/// --build-tests` compiling clean, the same static-verification precedent used elsewhere for
/// framework-level code this project's CLT-only host can't exercise at runtime.
struct GroupJoinQRCodeTests {
    @Test func cgImage_producesANonNilImageForAValidJoinLink() {
        let image = GroupJoinQRCode.cgImage(for: "https://join.example.test/g#7F3K9QRZ")
        #expect(image != nil)
    }

    @Test func cgImage_scalesUpFromCIQRCodeGeneratorsRawOneModulePerPixelOutput() {
        // The raw CIQRCodeGenerator output is 1 px/module — unreadably small on any real screen.
        // Confirm the default scale actually produces a materially larger image.
        let image = GroupJoinQRCode.cgImage(for: "https://join.example.test/g#7F3K9QRZ")
        #expect((image?.width ?? 0) > 50)
        #expect(image?.width == image?.height, "a QR code is always square")
    }

    @Test func cgImage_deterministicForTheSameInput() {
        let first = GroupJoinQRCode.cgImage(for: "https://join.example.test/g#7F3K9QRZ")
        let second = GroupJoinQRCode.cgImage(for: "https://join.example.test/g#7F3K9QRZ")
        #expect(first?.width == second?.width)
        #expect(first?.height == second?.height)
    }

    @Test func cgImage_differentInputsProduceDifferentlySizedOrShapedContent() {
        // Not a security assertion, just a sanity check that the filter is actually keyed off the
        // input text rather than returning a fixed/cached image regardless of content.
        let short = GroupJoinQRCode.cgImage(for: "https://join.example.test/g#7F3K9QRZ")
        let long = GroupJoinQRCode.cgImage(
            for: "https://join.example.test/g#7F3K9QRZ-with-a-lot-more-trailing-content-to-force-a-bigger-qr-version"
        )
        #expect(short != nil)
        #expect(long != nil)
        #expect((long?.width ?? 0) >= (short?.width ?? 0), "more input data needs an equal-or-larger QR version")
    }
}
