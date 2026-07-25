import CoreImage
import SwiftUI

/// specs/007-public-join-links.md §4, specs/004-ios-client.md §3.5 — renders a QR code of the
/// group's https join link ENTIRELY on-device via CoreImage's `CIQRCodeGenerator`. Using a
/// networked QR-generation service would leak the join code (a live join capability) to a third
/// party — a hard security/privacy requirement, not a style choice (007 §4, docs/security-review-
/// checklist.md). There is no network import, no `URLSession`, no third-party dependency anywhere
/// in this file — dependency review can confirm that directly.
public enum GroupJoinQRCode {
    /// Renders `text` (expected: the exact `https://{host}/g#{code}` link, 007 §7) as a QR code
    /// image, scaled up from CoreImage's native 1-point-per-module output so it's actually
    /// legible/scannable. Returns `nil` if CoreImage can't produce an image for pathological input
    /// — callers should treat `nil` as "no QR available" rather than crash.
    public static func cgImage(for text: String, scale: CGFloat = 10) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }

        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        return context.createCGImage(transformed, from: transformed.extent)
    }
}

/// Thin SwiftUI wrapper around `GroupJoinQRCode.cgImage(for:)`. Untested per this project's
/// established convention (Views aren't unit-tested, only ViewModels/pure logic, specs/004 §9);
/// verified via `swift build --build-tests` compiling clean, same as other framework-level code
/// this CLT-only host can't exercise at runtime.
public struct GroupJoinQRCodeView: View {
    private let cgImage: CGImage?

    public init(text: String) {
        self.cgImage = GroupJoinQRCode.cgImage(for: text)
    }

    public var body: some View {
        if let cgImage {
            Image(decorative: cgImage, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .accessibilityLabel("QR code to join this group")
        }
    }
}
