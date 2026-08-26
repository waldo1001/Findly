import SwiftUI

/// specs/010-app-shell-and-screen-ux.md §1.2/§3.1, specs/004-ios-client.md §2.3 — the Family Map's
/// (and Group Map's, §3.2) roster sheet: three detents at the handoff's normative heights —
/// **minimized 186pt**, **standard 440pt**, **expanded** (the platform "large" detent) — backed
/// by the real `.presentationDetents` API, not a hand-rolled draggable view. The map stays fully
/// rendered and interactive BEHIND the sheet at every detent (§3.1: "'maximize the map' is the
/// minimized detent, not a separate mode") via `presentationBackgroundInteraction` (iOS 16.4+;
/// this app's deployment target is 16.0, so 16.0–16.3 loses background interactivity while the
/// sheet holds first responder — a graceful platform-version limitation, not a spec violation the
/// implementation can close: no 16.0-compatible substitute exists).
///
/// Presented via `.sheet` because that is the only SwiftUI primitive `.presentationDetents`
/// attaches to — but always up (`isPresented` pinned to `true`, `interactiveDismissDisabled()`),
/// so from the user's perspective there is no "closed" state, only the minimized detent. Every
/// other design-system component in this file is a `View` a caller embeds; this one is a `View`
/// EXTENSION (`.findlyBottomSheet`) because the presentation itself has to attach to the presenter
/// (the full-bleed map), which is exactly SwiftUI's own shape for `.sheet`/`.alert`.
///
/// **Detent changes MUST NOT unmount the list or re-create view models (the I16 `@StateObject`
/// ownership rule, 010 §3.1).** This component has no view-model concerns of its own — it renders
/// only whatever `content` the caller supplies, unchanged, on every detent change. The ownership
/// obligation lives entirely in the CALLER (`LiveMapScreen`/`GroupMapScreen`): as long as the
/// content closure captures an outer `@StateObject`, rather than constructing a fresh view model
/// inside the closure, that instance survives every detent change — proven in
/// `FindlyBottomSheetDetentOwnershipTests` via the I18 rendering harness.
public enum FindlyBottomSheetDetent: CaseIterable, Equatable {
    case minimized
    case standard
    case expanded

    var presentationDetent: PresentationDetent {
        switch self {
        case .minimized: return .height(186)
        case .standard: return .height(440)
        case .expanded: return .large
        }
    }

    static let allPresentationDetents = Set(Self.allCases.map(\.presentationDetent))
}

public extension View {
    /// - Parameters:
    ///   - selection: the currently-selected detent — typically a plain `@State` on the caller,
    ///     since SwiftUI's own `@State` persistence across body re-evaluations of the same view
    ///     identity already handles "the value survives a detent drag"; this component's own
    ///     concern is only the presentation wiring, not the state's storage.
    ///   - content: the sheet's content, given the current detent so it can render the handoff's
    ///     three different layouts (§3.1: minimized/standard/expanded show progressively more).
    func findlyBottomSheet<SheetContent: View>(
        selection: Binding<FindlyBottomSheetDetent>,
        @ViewBuilder content: @escaping (FindlyBottomSheetDetent) -> SheetContent
    ) -> some View {
        modifier(FindlyBottomSheetModifier(selection: selection, sheetContent: content))
    }
}

private struct FindlyBottomSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var selection: FindlyBottomSheetDetent
    let sheetContent: (FindlyBottomSheetDetent) -> SheetContent

    /// `PresentationDetent` itself carries no case label to switch on (it's a value type wrapping
    /// a height/fraction), so round-tripping the system's selection binding back to our own enum
    /// matches on the concrete detent VALUES this component itself created — safe because
    /// `allPresentationDetents` is the exact, closed set `.presentationDetents` was given below.
    private func detent(for presentationDetent: PresentationDetent) -> FindlyBottomSheetDetent {
        FindlyBottomSheetDetent.allCases.first { $0.presentationDetent == presentationDetent } ?? selection
    }

    func body(content: Content) -> some View {
        content.sheet(isPresented: .constant(true)) {
            FindlyBottomSheetChrome(content: sheetContent(selection))
                .presentationDetents(
                    FindlyBottomSheetDetent.allPresentationDetents,
                    selection: Binding(
                        get: { selection.presentationDetent },
                        set: { selection = detent(for: $0) }
                    )
                )
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
                .findlyBottomSheetBackgroundInteractionIfAvailable()
        }
    }
}

private extension View {
    @ViewBuilder
    func findlyBottomSheetBackgroundInteractionIfAvailable() -> some View {
        if #available(iOS 16.4, macOS 14.0, *) {
            self.presentationBackgroundInteraction(.enabled)
        } else {
            self
        }
    }
}

/// The sheet's own root container — themed background only; every other visual (title, rows,
/// buttons) is the caller's `content`, since this component has zero knowledge of what a roster
/// looks like (§2.3: "zero knowledge of view models, networking, or navigation").
private struct FindlyBottomSheetChrome<Content: View>: View {
    @Environment(\.theme) private var theme
    let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(theme.colors.surface)
    }
}
