/// I18 — a minimal, reusable recorder for the SwiftUI-rendering-harness ownership-proof technique:
/// capture, in render order, some piece of state a probed view's `body` currently observes (e.g. a
/// per-instance token identifying WHICH view-model instance is alive), by calling `record` from
/// inside that `body`. Comparing successive recorded values is how a test tells "the view kept
/// observing the same instance across a re-render" from "it swapped to a new one" — the exact
/// distinction the I16 `@StateObject`/`@ObservedObject` ownership bug turns on (see
/// `ViewModelOwnershipContractTests`).
///
/// Promoted out of `ViewModelOwnershipContractTests` (I18 review finding #3) into its own file so
/// I34-I37's view-layer work can reuse this hook directly against `SwiftUIRenderingHarness`
/// instead of each reinventing it.
public final class ObservationLog<Element> {
    public private(set) var observed: [Element] = []
    public init() {}
    public func record(_ element: Element) { observed.append(element) }
}
