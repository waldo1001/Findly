import Foundation

// specs/001-api-contract.md §13 — privacy: export & deletion wire shapes; concepts/guarantees are
// normative in specs/008-privacy-endpoints.md.

extension URLSessionAPIClient {
    /// §13.1 — `userId == nil` exports the caller; a parent may pass another current family
    /// member's id (server-enforced: `403 AUTH_FORBIDDEN` for a non-parent naming someone else,
    /// `404 MEMBER_NOT_FOUND` for a parent naming a non-member). The success body is the export
    /// document itself, NOT the §3.1 envelope (001 §1.3's documented exception) — `sendRawData`
    /// returns it untouched, never attempting `Envelope<T>` decoding.
    public func exportData(userId: String?) async throws -> Data {
        var queryItems: [URLQueryItem] = []
        if let userId {
            queryItems.append(URLQueryItem(name: "userId", value: userId))
        }
        return try await sendRawData(method: .get, path: "export", queryItems: queryItems)
    }

    /// §13.2 — bare 204. Available to every authenticated user, including one with no profile
    /// (idempotent no-op, 008 §4.1) — re-callable until clean (008 §4.5).
    public func deleteAccount() async throws {
        try await sendNoContent(method: .delete, path: "users/me")
    }

    /// §13.3 — bare 204. Parent-only; re-callable until clean (008 §5.5).
    public func deleteFamily() async throws {
        try await sendNoContent(method: .delete, path: "families/me")
    }
}
