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

    /// specs/010-app-shell-and-screen-ux.md §5.1 item 6 — "a way to create another invite without
    /// leaving the screen ('Create another' resets the form)". Called by `CreateInviteScreen`'s
    /// "Create another" button.
    public func reset() {
        state = .idle
    }

    /// specs/007-public-join-links.md §4 (normative, added 2026-08-26) — the human-shareable text
    /// (`ShareLink` payload), reproduced byte-for-byte: the sentence with the hyphenated display
    /// code, a newline, then the canonical `https://{joinLinkHost}/f#CODE` link with the code in
    /// the fragment as canonical uppercase (no hyphen) — deliberately no store URL (007 §4: "the
    /// message stays short and never goes stale when store URLs change").
    public static func shareText(for code: String, joinLinkHost: String) -> String {
        let link = joinLink(for: code, joinLinkHost: joinLinkHost)
        return "Join our family on Findly — invite code \(displayForm(for: code))\n\(link.absoluteString)"
    }

    /// The hyphenated `XXXX-XXXX` display form (specs/001 §1.4) — the exact text `Copy code`
    /// copies to the clipboard (010 §5.1 item 1) and what `shareText(for:joinLinkHost:)` embeds in
    /// its sentence. A single source of truth so the screen never hand-rolls this formatting.
    public static func displayForm(for code: String) -> String {
        let clean = code.uppercased()
        guard clean.count == 8 else { return clean }
        return "\(clean.prefix(4))-\(clean.suffix(4))"
    }

    /// specs/007-public-join-links.md §1 (added 2026-08-26) — the canonical
    /// `https://{joinLinkHost}/f#CODE` family-invite link this screen's QR/share now use. Built
    /// via `URLComponents` (not string interpolation) so the code is provably set through the
    /// **fragment** property, never the path or query — the load-bearing privacy property that
    /// keeps the join capability out of every server/CDN log by construction.
    public static func joinLink(for code: String, joinLinkHost: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = joinLinkHost
        components.path = "/f"
        components.fragment = code.uppercased()
        return components.url!
    }

    /// specs/010-app-shell-and-screen-ux.md §5.1 caption line 2 ("Expires {local date/time}") —
    /// `expiresAt` is the server's own ISO 8601 UTC value (001 §3.3), NEVER a hardcoded 72h
    /// computed client-side. `nil` if the server ever sends something unparsable, so the caller
    /// can omit the line rather than render garbage. Tries a fractional-seconds parse before the
    /// plain one (001 §1.4: "milliseconds optional"), mirroring `RelativeTimeFormatter`'s fallback.
    public static func expiryLocalDateTime(for expiresAt: String) -> String? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let date = withFractional.date(from: expiresAt) ?? plain.date(from: expiresAt) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
