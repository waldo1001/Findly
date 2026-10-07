import Testing
@testable import FindlyKit

/// specs/009 §7 "Ongoing visibility" (I62) — the iOS background disclosure SHOULD mention the indicator.
struct PermissionDisclosureCopyTests {
    @Test func backgroundPoints_mentionTheBlueLocationIndicator() {
        #expect(PermissionDisclosureCopy.backgroundIndicatorSentence == "While Findly shares your location, iOS shows a blue location indicator.")
        #expect(PermissionDisclosureCopy.points(for: .background).contains(PermissionDisclosureCopy.backgroundIndicatorSentence))
    }

    @Test func foregroundPoints_doNotMentionTheIndicator() {
        #expect(!PermissionDisclosureCopy.points(for: .foreground).contains(PermissionDisclosureCopy.backgroundIndicatorSentence))
    }
}
