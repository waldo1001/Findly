import Foundation

/// specs/004-ios-client.md I2 (001 §1.4; docs/security-review-checklist.md §5 — "deep-link inputs
/// validated before use") — extracts and normalizes an invite code from a raw pasted code, the
/// legacy `findly://invite/<code>` / `https://.../invite/<code>` path-based deep link, OR (since
/// specs/007-public-join-links.md §1/§4, added 2026-08-26) the `findly://family-join?code=<code>`
/// query-based deep link. The `https://{joinLinkHost}/f#CODE` universal link is host-aware and
/// carries its code in the URL **fragment** — handled separately by
/// `matchHttpsInviteLink(_:joinLinkHost:)` below, exactly mirroring `GroupCodeParsing`'s split
/// between `normalize(_:)` and `matchHttpsJoinLink(_:joinLinkHost:)`, for the same reason: a
/// single-string API has no way to receive an expected host, so trusting an arbitrary https host
/// here would defeat "wrong host is ignored, never mis-routed". An invite code is 8 chars of
/// Crockford base32 (no I/L/O/U); the canonical wire form is uppercase with no hyphen, but a user
/// may paste/type the hyphenated `XXXX-XXXX` display form.
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

    /// specs/007-public-join-links.md §1/§4 (added 2026-08-26) — the result of matching an
    /// incoming URL against the `https://{joinLinkHost}/f#CODE` family-invite universal-link
    /// contract, mirroring `GroupCodeParsing.HttpsLinkMatch` exactly (`.notRecognized` for a wrong
    /// host/path — never mis-routed; `.recognized(code: nil)` for a valid host+path with no usable
    /// fragment, 007 §4 / 010 §5.2's "opens the join screen with an empty code field, no error").
    public enum HttpsLinkMatch: Equatable {
        case notRecognized
        case recognized(code: String?)
    }

    /// specs/007-public-join-links.md §1/§4 — `joinLinkHost` is always caller-supplied, never
    /// inferred from the URL, so a look-alike host can never be mistaken for the real one.
    ///
    /// RED stub (I37): always `.notRecognized` — no https matching implemented yet. Real matching
    /// (shared with `GroupCodeParsing.matchHttpsJoinLink` via `CodeLinkParsing`) lands in the next
    /// commit.
    public static func matchHttpsInviteLink(_ url: URL, joinLinkHost: String) -> HttpsLinkMatch {
        .notRecognized
    }

    /// specs/010-app-shell-and-screen-ux.md §5.2 — the smart code field's live-typing formatter:
    /// auto-uppercases, strips hyphens/spaces, whitelist-filters to the Crockford base32 charset,
    /// caps at 8 significant characters, and renders as `XXXX-XXXX` while typing.
    ///
    /// RED stub (I37): passthrough (no filtering/grouping at all) — real implementation (shared
    /// with the group-code parser via `CodeLinkParsing`) lands in the next commit.
    public static func liveFormat(_ raw: String) -> String {
        raw
    }
}
