import Foundation

/// specs/004-ios-client.md §3.4/§3.5 (specs/005-temporary-groups.md §1; specs/007-public-join-
/// links.md §1/§4; 001 §1.4; docs/security-review-checklist.md §5 — "deep-link inputs validated
/// before use") — extracts and normalizes a group join code from a raw pasted code, the
/// `findly://group-join?code=<code>` deep link, OR (since 007) the `https://{joinLinkHost}/g#CODE`
/// universal link, validating the charset defensively before it's ever sent to the network layer.
/// A group code shares the invite codes' 8-char Crockford base32 format/normalization
/// (`InviteCodeParsing`, 001 §1.4) — canonical wire form uppercase, no hyphen; a user may
/// paste/type the hyphenated `XXXX-XXXX` display form.
///
/// Unlike the invite deep link (`findly://invite/<code>`, a path segment), the `findly://` group-join
/// link carries its code as a `code` query parameter (`normalize(_:)` below). The https universal
/// link (007 §1) is host-aware (`{JOIN_LINK_HOST}` + path `/g`) and carries its code in the URL
/// **fragment**, never the path or query — the load-bearing privacy property that keeps the join
/// capability out of every server/CDN log by construction — so it needs the caller-supplied
/// `joinLinkHost` and is handled by the separate `matchHttpsJoinLink(_:joinLinkHost:)` below rather
/// than folded into `normalize(_:)`, which has no way to receive an expected host.
public enum GroupCodeParsing {
    /// Returns the normalized 8-character uppercase code, or `nil` if `raw` doesn't resolve to a
    /// well-formed group code — malformed/oversized/injection-shaped input is rejected here, never
    /// forwarded to `joinGroup`.
    public static func normalize(_ raw: String) -> String? {
        var candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: candidate), let scheme = url.scheme, !scheme.isEmpty {
            guard let code = CodeLinkParsing.extractQueryCode(from: url, expectedHost: "group-join") else {
                // Either a wholly unrelated URL, or a different `findly://` deep link (e.g. the
                // invite one) — never cross-parse another feature's link as a group code.
                return nil
            }
            candidate = code
        }

        return CodeLinkParsing.normalizeCode(candidate)
    }

    /// specs/007-public-join-links.md §1/§4 — the result of matching an incoming URL against the
    /// `https://{joinLinkHost}/g#CODE` universal-link contract specifically (the `findly://` form is
    /// `normalize(_:)`'s job, above). `.notRecognized` means wrong host or wrong path — the caller
    /// MUST NOT route anywhere for this ("wrong host or path is ignored, never mis-routed", 007
    /// §4). `.recognized(code:)` means host+path matched; `code` is `nil` when the fragment is
    /// missing, empty, or doesn't resolve to a well-formed code ("a valid link with no usable
    /// fragment opens the join screen with an empty code field, no error", 007 §4 / 003 §12.3).
    public enum HttpsLinkMatch: Equatable {
        case notRecognized
        case recognized(code: String?)
    }

    /// `joinLinkHost` is the deployment constant (`AppConfig.joinLinkHost`, specs/004 §8) — matched
    /// ONLY against this caller-supplied host, never inferred from the URL itself, so a look-alike
    /// host can never be mistaken for the real one. The code is read from the URL's **fragment**
    /// (`URLComponents.fragment`), never the path or query (007 §1), then run through the exact
    /// same `normalize(_:)` charset whitelist used by the `findly://` form above — one validation
    /// path, not two divergent ones.
    ///
    /// All of scheme/host/path are checked via `URLComponents`, NOT `URL`'s own `.scheme`/`.host`/
    /// `.path` accessors: `URL.path` silently normalizes away a trailing slash (`/g/` reads back as
    /// `/g`), which would let a wrong path (`/g/`) slip past a naive `url.path == "/g"` check —
    /// `URLComponents.path` preserves it exactly as written, so `/g/` is correctly `.notRecognized`
    /// ("wrong path (must be exactly /g) MUST be rejected", 007 §1).
    public static func matchHttpsJoinLink(_ url: URL, joinLinkHost: String) -> HttpsLinkMatch {
        switch CodeLinkParsing.matchHttpsLink(url, joinLinkHost: joinLinkHost, path: "/g") {
        case .notRecognized: return .notRecognized
        case .recognized(let code): return .recognized(code: code)
        }
    }
}
