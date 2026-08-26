import Foundation

/// specs/001-api-contract.md §1.4, specs/007-public-join-links.md §1/§4 — shared pure logic behind
/// `GroupCodeParsing` and `InviteCodeParsing`: both kinds of code (group join / family invite) are
/// 8-char Crockford base32, normalized identically (uppercase, hyphen/space-stripped), and both
/// kinds of https universal link carry their code in the URL **fragment**, validated against a
/// caller-supplied host + kind-specific path (`/g` vs `/f`). Extracted (I37) so the family-invite
/// twin doesn't hand-copy the group parser's geometry — the two public parsers keep their own
/// (near-identical, kind-specific) types/tests, but the actual matching/validation rules live here
/// once. Deliberately NOT `public` — this is an implementation-sharing seam internal to FindlyKit,
/// not part of its own API surface.
enum CodeLinkParsing {
    /// Crockford base32 alphabet (001 §1.4): digits + uppercase letters minus I, L, O, U.
    static let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHJKMNPQRSTVWXYZ0123456789")

    /// Strips hyphens/whitespace, uppercases, and validates length + charset. `nil` for anything
    /// that doesn't resolve to a well-formed 8-character code.
    static func normalizeCode(_ raw: String) -> String? {
        let stripped = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
        guard stripped.count == 8, stripped.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            return nil
        }
        return stripped
    }

    /// The result of matching an incoming URL against `https://{joinLinkHost}{path}#CODE`.
    enum HttpsLinkMatch: Equatable {
        case notRecognized
        case recognized(code: String?)
    }

    /// `joinLinkHost`/`path` are always caller-supplied, never inferred from the URL, so a
    /// look-alike host/path can never be mistaken for the real one. All of scheme/host/path are
    /// checked via `URLComponents`, NOT `URL`'s own accessors: `URL.path` silently normalizes away
    /// a trailing slash, which would let a wrong path slip past a naive `==` check.
    static func matchHttpsLink(_ url: URL, joinLinkHost: String, path: String) -> HttpsLinkMatch {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme == "https",
            components.host == joinLinkHost,
            components.path == path
        else {
            return .notRecognized
        }
        guard let fragment = components.fragment, let code = normalizeCode(fragment) else {
            return .recognized(code: nil)
        }
        return .recognized(code: code)
    }

    /// Extracts a `findly://{expectedHost}?{queryParamName}=CODE`-style deep link's code query
    /// parameter, gated on the URL's scheme+host matching exactly (`findly://group-join`,
    /// `findly://family-join`) — a different `findly://` deep link (or an unrelated URL) is never
    /// cross-parsed. Returns the RAW (not yet normalized) query value, or `nil` when the scheme/
    /// host don't match or the parameter is missing/empty.
    static func extractQueryCode(from url: URL, expectedHost: String, queryParamName: String = "code") -> String? {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme == "findly",
            components.host == expectedHost,
            let code = components.queryItems?.first(where: { $0.name == queryParamName })?.value,
            !code.isEmpty
        else {
            return nil
        }
        return code
    }

    /// specs/010-app-shell-and-screen-ux.md §5.2 — the smart code field's live-typing formatter:
    /// uppercases, strips disallowed characters (including hyphens/spaces — re-inserted below at
    /// the fixed display position, never wherever the user happened to type one), caps at 8
    /// significant characters, and renders the running result as `XXXX-XXXX`. Uses the SAME
    /// whitelist `normalizeCode` validates against, so a user can never type a character here that
    /// `normalizeCode` would later reject.
    static func liveFormat(_ raw: String) -> String {
        let filtered = raw.uppercased().filter { character in
            character.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
        }
        let significant = String(filtered.prefix(8))
        guard significant.count > 4 else { return significant }
        let splitIndex = significant.index(significant.startIndex, offsetBy: 4)
        return String(significant[..<splitIndex]) + "-" + String(significant[splitIndex...])
    }
}
