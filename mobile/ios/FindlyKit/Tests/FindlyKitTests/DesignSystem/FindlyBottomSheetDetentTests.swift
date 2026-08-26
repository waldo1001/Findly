import SwiftUI
import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §3.1 — the handoff's three detent heights are normative
/// layout values (not design tokens), pinned here so a future edit can't silently drift from
/// 186/440/large.
@MainActor
struct FindlyBottomSheetDetentTests {

    @Test func minimizedIs186Points() {
        #expect(FindlyBottomSheetDetent.minimized.presentationDetent == .height(186))
    }

    @Test func standardIs440Points() {
        #expect(FindlyBottomSheetDetent.standard.presentationDetent == .height(440))
    }

    @Test func expandedIsThePlatformLargeDetent() {
        #expect(FindlyBottomSheetDetent.expanded.presentationDetent == .large)
    }

    @Test func allThreeDetentsAreDistinct() {
        #expect(FindlyBottomSheetDetent.allPresentationDetents.count == 3)
    }
}
