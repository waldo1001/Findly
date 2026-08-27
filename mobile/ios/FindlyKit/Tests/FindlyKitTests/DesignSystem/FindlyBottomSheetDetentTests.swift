import SwiftUI
import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §3.1, amended 2026-08-27 (row I46, `39e92a4`): "sheet
/// detents size to their content, not to fixed heights." The 186pt/440pt values this file used to
/// pin as normative are retired — with a real (small) family they left dead space below the
/// content at both detents. The three cases themselves, and `.expanded` staying the platform
/// "large" detent, remain the only things a unit test can pin here: the actual measured-height
/// wiring (`FindlyBottomSheetModifier`'s hidden probes + `PreferenceKey`) lives inside a `.sheet`'s
/// presentation content, which SwiftUI gives no inspection hook for outside a real host controller
/// — the same documented boundary `FindlyBottomSheetDetentOwnershipTests` already accepts for this
/// component. That test instead proves the general `@StateObject`-survives-a-detent-change
/// mechanism `LiveMapScreen`/`GroupMapScreen` depend on; a rendered-screenshot check (not a unit
/// test) is what this row's task actually used to verify the dead-space fix.
@MainActor
struct FindlyBottomSheetDetentTests {

    @Test func exactlyThreeDetentsExist() {
        #expect(FindlyBottomSheetDetent.allCases.count == 3)
        #expect(FindlyBottomSheetDetent.allCases == [.minimized, .standard, .expanded])
    }

    @Test func detentsAreDistinctValues() {
        #expect(FindlyBottomSheetDetent.minimized != .standard)
        #expect(FindlyBottomSheetDetent.standard != .expanded)
        #expect(FindlyBottomSheetDetent.minimized != .expanded)
    }
}
