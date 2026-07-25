import Foundation

/// specs/004-ios-client.md I2 (001 §1.4) — derives a client-chosen `geofenceId` slug
/// (`gf_[a-z0-9-]{1,30}`) from a user-entered name, de-duplicated against the family's existing
/// config. Pure and unit-testable in isolation from any view model.
public enum GeofenceIdGenerating {
    public static func makeId(from name: String, existingIds: Set<String>) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        var slug = String(name.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty { slug = "geofence" }
        slug = String(slug.prefix(30))

        var candidate = "gf_\(slug)"
        var suffix = 2
        while existingIds.contains(candidate) {
            let suffixText = "-\(suffix)"
            let trimmedSlug = String(slug.prefix(max(1, 30 - suffixText.count)))
            candidate = "gf_\(trimmedSlug)\(suffixText)"
            suffix += 1
        }
        return candidate
    }
}
