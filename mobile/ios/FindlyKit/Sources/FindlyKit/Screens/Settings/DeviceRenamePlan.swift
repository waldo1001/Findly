import Foundation

/// specs/010-app-shell-and-screen-ux.md §4.2 — the rename row's Save-button gate: "disabled while
/// the trimmed draft is empty or unchanged." Pure, no SwiftUI, so it's unit-tested independent of
/// the (review-gate, §10) rename row's visual alignment.
public enum DeviceRenamePlan {
    public static func isSaveEnabled(draft: String, currentName: String) -> Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != currentName
    }
}
