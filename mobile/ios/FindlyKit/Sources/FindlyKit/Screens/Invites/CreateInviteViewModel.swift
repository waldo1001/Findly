import Foundation

/// specs/004-ios-client.md I2 (001 §3.3) — parent creates an invite; the code is shared out-of-band
/// via the OS share sheet (`ShareLink` in `CreateInviteScreen`), never sent by the app itself.
@MainActor
public final class CreateInviteViewModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case creating
        case created(inviteCode: String, role: String, expiresAt: String)
        case error(String)
    }

    @Published public private(set) var state: State = .idle
    private let apiClient: FindlyAPIClient

    public init(apiClient: FindlyAPIClient) {
        self.apiClient = apiClient
    }

    public func createInvite(role: String, emailHint: String?) async {
        state = .creating
        do {
            let envelope = try await apiClient.createInvite(role: role, emailHint: emailHint)
            state = .created(inviteCode: envelope.data.inviteCode, role: envelope.data.role, expiresAt: envelope.data.expiresAt)
        } catch {
            state = .error(userFacingMessage(for: error))
        }
    }

    /// specs/007-public-join-links.md §4 (normative, added 2026-08-26) — the human-shareable text
    /// (`ShareLink` payload). The exact template text is normative; this stub is deliberately
    /// wrong (I37 RED) — it ignores `joinLinkHost` and doesn't append the link at all, reproducing
    /// today's real bug (a bare sentence, no link, per 010 §5's problem statement). Real
    /// implementation lands in the next commit.
    public static func shareText(for code: String, joinLinkHost: String) -> String {
        let clean = code.uppercased()
        guard clean.count == 8 else {
            return "Join our family on Findly! Invite code: \(clean)"
        }
        let formatted = "\(clean.prefix(4))-\(clean.suffix(4))"
        return "Join our family on Findly! Invite code: \(formatted)"
    }

    /// specs/007-public-join-links.md §1 (added 2026-08-26) — the canonical
    /// `https://{joinLinkHost}/f#CODE` family-invite link this screen's QR/share now use.
    ///
    /// RED stub (I37): wrong path (`/g`, the GROUP path) — deliberately wrong-but-type-correct so
    /// the new test fails on content, not a compile error. Real implementation lands in the next
    /// commit.
    public static func joinLink(for code: String, joinLinkHost: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = joinLinkHost
        components.path = "/g"
        components.fragment = code.uppercased()
        return components.url!
    }

    /// specs/010-app-shell-and-screen-ux.md §5.1 caption line 2 ("Expires {local date/time}") —
    /// `expiresAt` is the server's own ISO 8601 UTC value (001 §3.3), NEVER a hardcoded 72h
    /// computed client-side. `nil` if the server ever sends something unparsable, so the caller
    /// can omit the line rather than render garbage.
    ///
    /// RED stub (I37): always `nil` — this is exactly today's real bug (`expiresAt` decoded into
    /// `State.created` but never rendered, per 010 §5's problem statement). Real implementation
    /// lands in the next commit.
    public static func expiryLocalDateTime(for expiresAt: String) -> String? {
        nil
    }
}
