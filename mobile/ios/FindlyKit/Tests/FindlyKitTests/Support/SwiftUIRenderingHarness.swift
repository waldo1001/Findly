import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// I18 (specs/004-ios-client.md §2, specs/010-app-shell-and-screen-ux.md §3.1) — a small homegrown
/// SwiftUI rendering harness, living entirely inside `FindlyKitTests` (test-target-only; it is not
/// exported from the `FindlyKit` library product). `Package.swift` MUST keep declaring zero
/// external dependencies — this hosts real SwiftUI content in the platform's real hosting
/// controller (`UIHostingController` on iOS, `NSHostingController` on macOS — see the platform
/// note below) and forces a real layout pass, rather than adding ViewInspector,
/// swift-snapshot-testing, or any hand-rolled tree-walker.
///
/// **Why this exists.** Before I18, every test in this target exercised a plain-Swift
/// `ObservableObject` directly — `viewModel.load()`, then assert on `viewModel.state`. That style
/// is structurally blind to I16: "`RootView.body` hands a screen a freshly-constructed view model
/// on every re-evaluation; `@StateObject` keeps the first instance, `@ObservedObject` swaps to the
/// new one every time" is a fact about SwiftUI's own view-diffing engine, not about the view
/// model's logic. No amount of testing `HomeViewModel` in isolation can observe that a *view*
/// holding it as `@ObservedObject` loses track of the instance that actually finished loading.
/// Only hosting the real view and re-rendering it — which is what this harness does — can.
///
/// **What this is not.** No reference images, no pixel/snapshot diffing, no accessibility-tree
/// inspection. Tests assert on state/identity the probed view itself reports (e.g. via a plain
/// recorder object captured in its `body`), not on rendered pixels.
///
/// **Platform note.** `FindlyKit/Package.swift` targets both `.iOS(.v16)` and `.macOS(.v13)` so
/// the package builds & tests headlessly on any host (see that file's own header comment). This
/// sandbox has Xcode but no usable Simulator, so `swift test` links and runs against the macOS
/// host toolchain, where `UIKit` does not exist — only `AppKit`'s `NSHostingController` is
/// reachable here. Both branches host the identical `Content` view and drive the identical
/// SwiftUI update machinery (`@StateObject`/`@ObservedObject` semantics are platform-independent),
/// so the harness's behavior — and what it proves about the ownership contract below — is the same
/// on either platform; only the concrete hosting-controller type differs.
@MainActor
public final class SwiftUIRenderingHarness<Content: View> {
    #if canImport(UIKit)
    private let hostingController: UIHostingController<Content>
    #elseif canImport(AppKit)
    private let hostingController: NSHostingController<Content>
    #endif

    /// Hosts `view` and forces one full layout pass immediately, matching what a real window does
    /// before the first frame is drawn — without this, SwiftUI defers body evaluation to a later
    /// run-loop turn that a synchronous test would never observe.
    public init(_ view: Content, size: CGSize = CGSize(width: 400, height: 800)) {
        #if canImport(UIKit)
        hostingController = UIHostingController(rootView: view)
        hostingController.view.frame = CGRect(origin: .zero, size: size)
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        #elseif canImport(AppKit)
        hostingController = NSHostingController(rootView: view)
        hostingController.view.setFrameSize(size)
        hostingController.view.layoutSubtreeIfNeeded()
        #endif
    }

    /// Replaces the hosted root view with a new value of the SAME `Content` type and forces
    /// another synchronous layout pass. This is the harness's stand-in for what a real app's root
    /// view does on every in-app navigation: `RootView.body` re-evaluates and produces a brand new
    /// screen struct value at the same position in the view tree. Whether the view underneath
    /// treats that as "the same identity, please update in place" (preserving `@StateObject`
    /// storage) or not (an `@ObservedObject` simply re-reads whatever it was just handed) is
    /// exactly the I16 ownership contract this harness exists to exercise.
    public func update(_ view: Content) {
        hostingController.rootView = view
        #if canImport(UIKit)
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        #elseif canImport(AppKit)
        hostingController.view.layoutSubtreeIfNeeded()
        #endif
    }
}
