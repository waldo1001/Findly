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
/// **Platform note — known, currently-permanent coverage boundary (I18 review finding #2).**
/// `FindlyKit/Package.swift` targets both `.iOS(.v16)` and `.macOS(.v13)` so the package builds &
/// tests headlessly on any host (see that file's own header comment), and this class compiles
/// against either via the `#if canImport(UIKit)/#elseif canImport(AppKit)` branches above. In
/// practice, though, every place that actually runs `swift test` today — this sandbox, and
/// `.github/workflows/ios.yml`'s `ios-package` job, the only CI job that runs `test` rather than
/// just `build` — invokes plain `swift build`/`swift test` with no `-destination`, which compiles
/// against the macOS host SDK. `canImport(UIKit)` is false there, so the `AppKit`/
/// `NSHostingController` branch is the ONLY one ever exercised, in this sandbox or in CI. (CI's
/// `ios-build` job does target an iOS Simulator destination, but it only runs `build`, never
/// `test`, and never touches `FindlyKitTests`.) This is not a temporary sandbox limitation that
/// resolves once a Simulator is available — it is the actual, permanent shape of today's test
/// coverage for this harness. Closing it requires a CI step that runs `xcodebuild test` (or
/// `swift test --destination ...`) against a real iOS Simulator, which is out of this task's scope
/// (tracked separately). The fallback itself is legitimate and intentional, not a stopgap:
/// `@StateObject`/`@ObservedObject` ownership semantics are platform-independent SwiftUI behavior,
/// both branches host the identical `Content` view through the identical SwiftUI update machinery,
/// and `Package.swift` already declared `.macOS(.v13)` before this task touched anything — so what
/// this harness proves about the I16 ownership contract holds on macOS today and will hold
/// identically on iOS once something actually runs this suite there.
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
