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
    /// Returns the normalized 8-character uppercase code, or `nil` if `raw` doesn't resolve to a
    /// well-formed invite code — malformed/oversized/injection-shaped input is rejected here,
    /// never forwarded to `acceptInvite`.
    public static func normalize(_ raw: String) -> String? {
        var candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: candidate), let scheme = url.scheme, !scheme.isEmpty {
            if scheme == "findly", let code = CodeLinkParsing.extractQueryCode(from: url, expectedHost: "family-join") {
                // specs/007 §1/§4 (added 2026-08-26): findly://family-join?code=<code>.
                candidate = code
            } else if url.host == "invite" || url.pathComponents.contains("invite") {
                // Legacy path-based deep link (findly://invite/<code>, https://.../invite/<code>).
                candidate = url.lastPathComponent
            } else {
                // A URL-shaped string that isn't our invite deep link at all — never treat its
                // scheme/host/path as an invite code.
                return nil
            }
        }

        return CodeLinkParsing.normalizeCode(candidate)
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
    /// inferred from the URL, so a look-alike host can never be mistaken for the real one. The code
    /// is read from the URL's **fragment**, never the path or query (007 §1) — the load-bearing
    /// privacy property that keeps a single-use family-invite code out of every server/CDN log by
    /// construction (007 §1: "the single-use property makes the fragment rule MORE load-bearing").
    public static func matchHttpsInviteLink(_ url: URL, joinLinkHost: String) -> HttpsLinkMatch {
        switch CodeLinkParsing.matchHttpsLink(url, joinLinkHost: joinLinkHost, path: "/f") {
        case .notRecognized: return .notRecognized
        case .recognized(let code): return .recognized(code: code)
        }
    }

    /// specs/010-app-shell-and-screen-ux.md §5.2 — the smart code field's live-typing formatter:
    /// auto-uppercases, strips hyphens/spaces, whitelist-filters to the Crockford base32 charset,
    /// caps at 8 significant characters, and renders as `XXXX-XXXX` while typing. Shared logic
    /// (`CodeLinkParsing.liveFormat`) — same whitelist `normalize(_:)` validates against.
    public static func liveFormat(_ raw: String) -> String {
        CodeLinkParsing.liveFormat(raw)
    }
}
