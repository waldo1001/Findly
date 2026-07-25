import Foundation

/// specs/001-api-contract.md §12.1 — the three `expiryPolicy` values, immutable after creation
/// (specs/005-temporary-groups.md §2.1). `rawValue` is the exact wire string sent to
/// `createGroup(expiryPolicy:)`; `policyCopy` is the plain-language privacy promise clients MUST
/// show at creation (005 §2.1), reproduced here verbatim so `CreateGroupScreen` never re-derives
/// or paraphrases it.
public enum GroupExpiryPolicy: String, CaseIterable, Equatable, Identifiable {
    case delete
    case grace
    case archive

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .delete: return "Delete"
        case .grace: return "Grace period"
        case .archive: return "Archive"
        }
    }

    public var policyCopy: String {
        switch self {
        case .delete:
            return "When the group ends, everything about it disappears."
        case .grace:
            return "When the group ends it goes read-only for a few days so the owner can revive it; then everything disappears."
        case .archive:
            return "When the group ends, everyone's locations are deleted; the member list stays as a keepsake."
        }
    }
}

/// specs/005-temporary-groups.md §2.2 — maps a `GroupSummary`/`GroupDetail`'s derived `state`
/// string to a `StatusChip`. `expired` is deliberately absent (005 §2.2: "never serialized in a
/// response" — the server filters/410s it, so it's not a state this client ever renders).
public enum GroupStateChip {
    public static func kind(for state: String) -> StatusChipKind {
        switch state {
        case "active": return .online
        case "ended": return .stale
        case "archived": return .paused
        default: return .paused
        }
    }

    public static func label(for state: String) -> String {
        switch state {
        case "active": return "Active"
        case "ended": return "Ended"
        case "archived": return "Archived"
        default: return state.capitalized
        }
    }
}

/// A friendly, relative rendering of a group's `endsAt` (specs/004 §3.4 — "countdown from
/// `endsAt`"). Pure and testable; never crashes on an unparseable string (defensive — the server
/// is the source of truth for the ISO 8601 shape, 001 §1.4).
public enum GroupCountdown {
    public static func text(from endsAtISO8601: String, now: Date = Date()) -> String {
        guard let endsAt = parse(endsAtISO8601) else { return "" }
        let interval = endsAt.timeIntervalSince(now)
        guard interval > 0 else { return "Ended" }

        let totalMinutes = Int(interval / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return hours > 0 ? "Ends in \(days)d \(hours)h" : "Ends in \(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "Ends in \(hours)h \(minutes)m" : "Ends in \(hours)h"
        }
        return "Ends in \(minutes)m"
    }

    /// `endsAt` "milliseconds optional" per 001 §1.4 — try the plain shape first, then fractional
    /// seconds, before giving up.
    private static func parse(_ iso: String) -> Date? {
        if let date = Self.formatter.date(from: iso) { return date }
        return Self.fractionalFormatter.date(from: iso)
    }

    private static let formatter = ISO8601DateFormatter()

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
