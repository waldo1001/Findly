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
    /// specs/010-app-shell-and-screen-ux.md §5.2 — "prefilled with the caller's existing profile
    /// `displayName` when one exists". `nil` until `resolveExistingDisplayName()` runs (or on any
    /// failure/empty result — this is a convenience prefill, never on the join's critical path).
    @Published public private(set) var resolvedDisplayName: String?
    private let apiClient: FindlyAPIClient

    public init(apiClient: FindlyAPIClient) {
        self.apiClient = apiClient
    }

    /// specs/010-app-shell-and-screen-ux.md §5.2, specs/001-api-contract.md §4.2 — a family-less
    /// caller's `GET /devices` returns their OWN devices only, each with `ownerDisplayName` equal
    /// to their own profile `displayName` (§4.2: "a family-less caller gets their own devices
    /// only... ownerDisplayName = their profile displayName") — no dedicated profile-lookup
    /// endpoint exists, so this is the wire shape that actually carries it. Callers (the screen)
    /// only invoke this when there's no Onboarding-typed name already to prefill from.
    ///
    /// RED stub (I37 review fix): always `nil`, ignoring whatever `listDevices()` actually
    /// returns — deliberately wrong-but-type-correct so the new test fails on content, not a
    /// compile error. Real implementation lands in the next commit.
    public func resolveExistingDisplayName() async {
        resolvedDisplayName = nil
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
