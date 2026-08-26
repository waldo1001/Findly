import Foundation

/// specs/010-app-shell-and-screen-ux.md §3.1/§10: pure, shared-logic humanization of a roster
/// row's `recordedAt` (001-api-contract.md §1.4, ISO 8601 UTC) — replaces the raw ISO strings both
/// platforms show today. Mirrors Android's `RelativeTimeFormatter.kt` exactly, including its
/// `nowIso`-as-parameter shape (rather than reading the system clock directly) so the 30 s ticker
/// that recomputes this (`LiveMapScreen`) can drive it deterministically and this stays
/// unit-testable with no clock dependency.
///
/// Deliberately returns a wrong-on-purpose constant right now (assertion-level red, not
/// compile-level) — the next commit implements the real thresholds.
public enum RelativeTimeFormatter {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static func parse(_ iso: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return withFractional.date(from: iso) ?? plain.date(from: iso)
    }

    /// "Just now" (< 60 s) / "N min ago" (< 60 min) / "N hr ago" (< 24 h) / a calendar date
    /// otherwise (§10: "thresholds ('just now' / minutes / hours / date)"). `recordedAtIso` in the
    /// future relative to `nowIso` (clock skew) clamps to "Just now" rather than a negative age
    /// (§10: "stability against clock skew (never negative ages)").
    public static func format(recordedAtIso: String, nowIso: String) -> String {
        guard let recordedAt = parse(recordedAtIso), let now = parse(nowIso) else {
            return "Just now"
        }
        let elapsedSeconds = max(now.timeIntervalSince(recordedAt), 0)

        switch elapsedSeconds {
        case ..<60:
            return "Just now"
        case ..<3_600:
            return "\(Int(elapsedSeconds / 60)) min ago"
        case ..<86_400:
            return "\(Int(elapsedSeconds / 3_600)) hr ago"
        default:
            return dateFormatter.string(from: recordedAt)
        }
    }
}
