import SwiftUI

/// specs/010-app-shell-and-screen-ux.md §1.2/§3.1 (amended 2026-08-27, row I46 — `39e92a4`),
/// specs/004-ios-client.md §2.3 — the Family Map's (and Group Map's, §3.2) roster sheet: three
/// detents backed by the real `.presentationDetents` API, not a hand-rolled draggable view. The
/// map stays fully rendered and interactive BEHIND the sheet at every detent (§3.1: "'maximize the
/// map' is the minimized detent, not a separate mode") via `presentationBackgroundInteraction`
/// (iOS 16.4+; this app's deployment target is 16.0, so 16.0–16.3 loses background interactivity
/// while the sheet holds first responder — a graceful platform-version limitation, not a spec
/// violation the implementation can close: no 16.0-compatible substitute exists).
///
/// **§3.1 as amended by I46: each detent's CONTENTS stay normative, its HEIGHT does not.** The
/// handoff's fixed 186pt/440pt values assumed a fuller roster than a real family has, leaving dead
/// space below the content at both detents on a 4-member family — "a detent MUST NOT render empty
/// space below its own content" is now an explicit spec rule. So `minimized`/`standard` are sized
/// to caller-supplied heights rather than a literal. `expanded` stays the platform "large" detent,
/// unchanged.
///
/// **Why these heights are computed, not runtime-measured.** The first implementation of this fix
/// measured content height with a hidden, zero-opacity "probe" copy of the sheet's content behind a
/// `GeometryReader`/`PreferenceKey`, alongside the real visible copy. That works for plain content,
/// but reproduces to **zero** for a `ForEach` over the same data model rendered a second time in the
/// same presentation (`.sheet`'s hosting controller appears to collapse the second, simultaneous
/// occurrence of matching `ForEach` item identities to a degenerate size — reproduced with a bare
/// `ForEach(_, id:)` over plain `Text` rows, no design-system component involved) and separately for
/// any view carrying `@FocusState` (`FindlyButton`) rendered twice at once for the same reason. The
/// roster this sheet exists to show is exactly a `ForEach` over the family's members, so that
/// technique is unusable here — shipping it would silently fall back to a stale default height
/// whenever the roster is non-trivial, the exact class of bug this row exists to fix. Instead,
/// `FindlyBottomSheetHeightPlanning` computes both heights analytically from the same fixed
/// component metrics (`FindlyListRow`'s documented 60pt row, `FindlyButton`'s documented 52pt,
/// `FindlyCardDivider`'s 1pt, the roster avatar stack's 32pt, and the `titleMedium`/`bodyMedium`
/// type roles' declared `lineHeight`) that the caller's own content already renders with — no
/// runtime measurement, so nothing to oscillate and no duplicate-identity landmine to hit.
///
/// `standard` is additionally capped via `standardHeightCap` (§3.1: "capped at the platform 'large'
/// detent so a big family cannot overflow it") — callers pass their own measured viewport height
/// (the same value already threaded through for camera-fitting, §3.4) as a close, already-available
/// approximation of what `.large` would offer; when omitted the default is unbounded and the system
/// itself still won't present a `.height` beyond the sheet's maximum extent.
///
/// Presented via `.sheet` because that is the only SwiftUI primitive `.presentationDetents`
/// attaches to. `isPresented` is a caller-supplied binding (default always-`true`) rather than the
/// permanently-pinned constant this component used before I46: the Family Map needs to dismiss this
/// sheet while its navigation drawer is open (§1.2 — a `.sheet` presents above the ENTIRE view
/// hierarchy, so no z-order change can put an in-hierarchy overlay like the drawer above it) and
/// restore it, at whatever detent it was on, when the drawer closes. `interactiveDismissDisabled()`
/// still applies whenever the sheet IS presented, so a user can never swipe it away themselves —
/// only a caller toggling `isPresented` can.
///
/// Every other design-system component in this file is a `View` a caller embeds; this one is a
/// `View` EXTENSION (`.findlyBottomSheet`) because the presentation itself has to attach to the
/// presenter (the full-bleed map), which is exactly SwiftUI's own shape for `.sheet`/`.alert`.
///
/// **Detent changes MUST NOT unmount the list or re-create view models (the I16 `@StateObject`
/// ownership rule, 010 §3.1).** This component has no view-model concerns of its own — it renders
/// only whatever `content` the caller supplies, unchanged, on every detent change. The ownership
/// obligation lives entirely in the CALLER (`LiveMapScreen`/`GroupMapScreen`): as long as the
/// content closure captures an outer `@StateObject`, rather than constructing a fresh view model
/// inside the closure, that instance survives every detent change — proven generically by
/// `FindlyBottomSheetDetentOwnershipTests`.
public enum FindlyBottomSheetDetent: CaseIterable, Equatable {
    case minimized
    case standard
    case expanded
}

public extension View {
    /// - Parameters:
    ///   - selection: the currently-selected detent — typically a plain `@State` on the caller,
    ///     since SwiftUI's own `@State` persistence across body re-evaluations of the same view
    ///     identity already handles "the value survives a detent drag"; this component's own
    ///     concern is only the presentation wiring, not the state's storage. It also survives this
    ///     sheet being dismissed and re-presented via `isPresented` below, for the same reason.
    ///   - isPresented: whether the sheet is up at all. Defaults to always-`true` (this component's
    ///     original behavior: "from the user's perspective there is no closed state, only the
    ///     minimized detent"). The Family Map (010 §1.2/§3.1, I46) passes a binding that goes
    ///     `false` while its navigation drawer is open — the only way to get the drawer visually
    ///     above this sheet, since both are `.sheet`-and-in-hierarchy respectively and no z-order
    ///     trick crosses that boundary.
    ///   - minimizedHeight: the `.minimized` detent's height — computed by the caller, typically via
    ///     `FindlyBottomSheetHeightPlanning.minimizedHeight`.
    ///   - standardHeight: the `.standard` detent's height before capping — computed by the caller,
    ///     typically via `FindlyBottomSheetHeightPlanning.standardHeight`.
    ///   - standardHeightCap: an upper bound for `standardHeight` (010 §3.1: "capped at the platform
    ///     'large' detent so a big family cannot overflow it"). Callers pass their already-measured
    ///     viewport height (§3.4's camera-fitting value) as a practical stand-in for `.large`'s
    ///     actual extent. Defaults to `.infinity` (no cap; the system's own sheet presentation still
    ///     won't exceed its maximum extent).
    ///   - content: the sheet's content, given the current detent so it can render the handoff's
    ///     three different layouts (§3.1: minimized/standard/expanded show progressively more).
    func findlyBottomSheet<SheetContent: View>(
        selection: Binding<FindlyBottomSheetDetent>,
        isPresented: Binding<Bool> = .constant(true),
        minimizedHeight: CGFloat,
        standardHeight: CGFloat,
        standardHeightCap: CGFloat = .infinity,
        @ViewBuilder content: @escaping (FindlyBottomSheetDetent) -> SheetContent
    ) -> some View {
        modifier(FindlyBottomSheetModifier(
            selection: selection,
            isPresented: isPresented,
            minimizedHeight: minimizedHeight,
            standardHeight: standardHeight,
            standardHeightCap: standardHeightCap,
            sheetContent: content
        ))
    }
}

private struct FindlyBottomSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var selection: FindlyBottomSheetDetent
    let isPresented: Binding<Bool>
    let minimizedHeight: CGFloat
    let standardHeight: CGFloat
    let standardHeightCap: CGFloat
    let sheetContent: (FindlyBottomSheetDetent) -> SheetContent

    /// Guarantees `.standard` is always strictly taller than `.minimized` even if a caller's own
    /// height math happens to produce the same value for both — `.standard`'s content is header +
    /// rows, a strict superset of `.minimized`'s header-only content, so this never clips anything
    /// real; it only prevents two `PresentationDetent`s from colliding into the same value, which
    /// would silently collapse the three-detent set to two and break the round-trip below.
    private var cappedStandardHeight: CGFloat {
        max(min(standardHeight, standardHeightCap), minimizedHeight + 1)
    }

    private func presentationDetent(for detent: FindlyBottomSheetDetent) -> PresentationDetent {
        switch detent {
        case .minimized: return .height(minimizedHeight)
        case .standard: return .height(cappedStandardHeight)
        case .expanded: return .large
        }
    }

    private var allPresentationDetents: Set<PresentationDetent> {
        Set(FindlyBottomSheetDetent.allCases.map(presentationDetent(for:)))
    }

    /// `PresentationDetent` itself carries no case label to switch on (it's a value type wrapping
    /// a height/fraction), so round-tripping the system's selection binding back to our own enum
    /// matches on the concrete detent VALUES this component itself just handed `.presentationDetents`
    /// below — safe because both sides read the same live `minimizedHeight`/`cappedStandardHeight`
    /// within one body evaluation.
    private func detent(for presentationDetent: PresentationDetent) -> FindlyBottomSheetDetent {
        FindlyBottomSheetDetent.allCases.first { self.presentationDetent(for: $0) == presentationDetent } ?? selection
    }

    func body(content: Content) -> some View {
        content.sheet(isPresented: isPresented) {
            FindlyBottomSheetChrome(content: sheetContent(selection))
                .presentationDetents(
                    allPresentationDetents,
                    selection: Binding(
                        get: { presentationDetent(for: selection) },
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
