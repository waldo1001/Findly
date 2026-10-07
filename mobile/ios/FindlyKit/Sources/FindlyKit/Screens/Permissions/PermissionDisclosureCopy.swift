import Foundation

/// specs/009-device-runtime.md §7 — the disclosure bullet copy, extracted from
/// `PermissionDisclosureScreen` so it is testable without rendering SwiftUI.
public enum PermissionDisclosureCopy {
    /// §7 "Ongoing visibility" (H12, I62): iOS shows the blue indicator while sharing in the background.
    public static let backgroundIndicatorSentence = "While Findly shares your location, iOS shows a blue location indicator."

    public static func points(for kind: PermissionDisclosureKind) -> [String] {
        switch kind {
        case .foreground:
            return [
                "Findly collects this device's location so it can appear on your family's map.",
                "Only people in the families and groups you have joined can see it. It is never sold or shared with anyone else.",
                "You can pause sharing at any time in Settings, and delete your history and account from inside the app.",
            ]
        case .background:
            return [
                "To keep the map up to date, Findly needs to collect your location even when the app is closed or not in use.",
                "This is what lets your family see where you are without you opening the app, and what makes arrival and departure alerts work for places like home or school.",
                "Background updates follow the interval you choose in Settings, and stop entirely when you pause sharing.",
                backgroundIndicatorSentence,
            ]
        }
    }
}
