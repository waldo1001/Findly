import Foundation

/// specs/004-ios-client.md I2 (001 §3.4) — join a family from a pasted code or a deep link. Every
/// input is normalized/validated by `InviteCodeParsing` BEFORE the network call (security checklist
/// §5 — deep-link inputs validated before use).
@MainActor
public final class AcceptInviteViewModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case joining
        case joined(familyId: String, familyName: String, role: String)
        case error(String)
    }

    @Published public private(set) var state: State = .idle
    private let apiClient: FindlyAPIClient

    public init(apiClient: FindlyAPIClient) {
        self.apiClient = apiClient
    }

    /// `rawInviteCode` may be a pasted code OR a full deep link (`findly://invite/<code>`).
    public func accept(rawInviteCode: String, displayName: String) async {
        guard let code = InviteCodeParsing.normalize(rawInviteCode) else {
            state = .error("That invite code doesn't look right. Double-check it and try again.")
            return
        }
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .error("Enter your name to join.")
            return
        }
        state = .joining
        do {
            let envelope = try await apiClient.acceptInvite(inviteCode: code, displayName: displayName)
            state = .joined(familyId: envelope.data.familyId, familyName: envelope.data.familyName, role: envelope.data.role)
        } catch {
            state = .error(userFacingMessage(for: error))
        }
    }
}
