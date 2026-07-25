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

    /// The human-shareable text (`ShareLink` payload) — canonical uppercase, no hyphen (specs/001
    /// §1.4), formatted for readability as `XXXX-XXXX`.
    public static func shareText(for code: String) -> String {
        let clean = code.uppercased()
        guard clean.count == 8 else {
            return "Join our family on Findly! Invite code: \(clean)"
        }
        let formatted = "\(clean.prefix(4))-\(clean.suffix(4))"
        return "Join our family on Findly! Invite code: \(formatted)"
    }
}
