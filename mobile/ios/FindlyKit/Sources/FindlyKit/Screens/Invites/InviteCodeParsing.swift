import Foundation

/// specs/004-ios-client.md I2 (001 §1.4; docs/security-review-checklist.md §5 — "deep-link inputs
/// validated before use") — extracts and normalizes an invite code from EITHER a raw pasted code OR
/// a deep link (`findly://invite/<code>`), validating the charset defensively before it's ever sent
/// to the network layer. An invite code is 8 chars of Crockford base32 (no I/L/O/U); the canonical
/// wire form is uppercase with no hyphen, but a user may paste/type the hyphenated
/// `XXXX-XXXX` display form.
public enum InviteCodeParsing {
    /// Crockford base32 alphabet (specs/001 §1.4): digits + uppercase letters minus I, L, O, U.
    private static let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHJKMNPQRSTVWXYZ0123456789")

    /// Returns the normalized 8-character uppercase code, or `nil` if `raw` doesn't resolve to a
    /// well-formed invite code — malformed/oversized/injection-shaped input is rejected here,
    /// never forwarded to `acceptInvite`.
    public static func normalize(_ raw: String) -> String? {
        var candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: candidate), let scheme = url.scheme, !scheme.isEmpty {
            if url.host == "invite" || url.pathComponents.contains("invite") {
                candidate = url.lastPathComponent
            } else {
                // A URL-shaped string that isn't our invite deep link at all — never treat its
                // scheme/host/path as an invite code.
                return nil
            }
        }

        let stripped = candidate.replacingOccurrences(of: "-", with: "").uppercased()
        guard stripped.count == 8, stripped.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            return nil
        }
        return stripped
    }
}
