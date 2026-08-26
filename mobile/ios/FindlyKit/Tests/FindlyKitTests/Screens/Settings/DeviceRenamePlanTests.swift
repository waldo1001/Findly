import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §4.2 — "Save is disabled while the trimmed draft is
/// empty or unchanged." Pure logic, extracted so the rename row's Save-button gating is
/// unit-tested without any SwiftUI hosting.
@MainActor
struct DeviceRenamePlanTests {

    @Test func blankDraft_disablesSave() {
        #expect(DeviceRenamePlan.isSaveEnabled(draft: "", currentName: "Eric's phone") == false)
    }

    @Test func whitespaceOnlyDraft_disablesSave() {
        #expect(DeviceRenamePlan.isSaveEnabled(draft: "   ", currentName: "Eric's phone") == false)
    }

    @Test func draftEqualToTheCurrentName_disablesSave() {
        #expect(DeviceRenamePlan.isSaveEnabled(draft: "Eric's phone", currentName: "Eric's phone") == false)
    }

    @Test func draftEqualToTheCurrentNameModuloSurroundingWhitespace_disablesSave() {
        #expect(DeviceRenamePlan.isSaveEnabled(draft: "  Eric's phone  ", currentName: "Eric's phone") == false)
    }

    @Test func aGenuinelyDifferentNonBlankDraft_enablesSave() {
        #expect(DeviceRenamePlan.isSaveEnabled(draft: "Noor's tablet", currentName: "Eric's phone") == true)
    }
}
