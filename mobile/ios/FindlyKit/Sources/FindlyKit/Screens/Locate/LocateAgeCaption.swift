import Foundation

/// specs/009-device-runtime.md §5.1 "Requester side": a `.late` position is "rendered exactly like
/// fresh plus an age caption". Pure so `LocateScreen` doesn't need any wall-clock dependency in a
/// test; a malformed `recordedAt` (should never happen — it comes straight off a parsed server
/// response) yields an empty string rather than crashing the screen. Mirrors Android's
/// `LocateAgeCaption` (same wording).
public enum LocateAgeCaption {
    public static func forRecordedAt(_ recordedAt: String, now: Date = Date()) -> String {
        guard let recorded = ISO8601DateFormatter().date(from: recordedAt) else { return "" }
        let minutes = max(0, Int(now.timeIntervalSince(recorded) / 60))
        switch minutes {
        case 0: return "just now"
        case 1: return "1 minute ago"
        default: return "\(minutes) minutes ago"
        }
    }
}
