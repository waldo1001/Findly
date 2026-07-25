import Foundation

/// specs/004-ios-client.md I2/§3.4 — the post-sign-in hub. Loads just enough family context
/// (`GET /families/me`) to know the caller's role (parent vs member) and offer sensible defaults
/// (own history, first other member to locate), so individual feature screens don't each need to
/// re-derive this.
///
/// **Family-less is first-class (review-gate finding #3, specs/005 §1, 001 §1.5).** A signed-in
/// user without a family answers `FAMILY_NOT_FOUND` (has a profile, no family) or
/// `PROFILE_NOT_FOUND` (brand-new, no profile at all yet — 001 §1.5.3) to this fetch — both land in
/// `.familyless`, a distinct renderable state, NOT the generic `.error`, so `HomeScreen` can still
/// offer Groups (family-independent, 001 §1.5.4) instead of a dead end with a bare error banner.
/// Every other failure (transport, decoding, any other server code) still lands in `.error`.
@MainActor
public final class HomeViewModel: ObservableObject {
    public enum State: Equatable {
        case loading
        case loaded(myUserId: String, isParent: Bool, familyName: String, otherMembers: [FamilyMember])
        case familyless
        case error(String)
    }

    @Published public private(set) var state: State = .loading
    private let apiClient: FindlyAPIClient

    public init(apiClient: FindlyAPIClient) {
        self.apiClient = apiClient
    }

    public func load() async {
        state = .loading
        do {
            let envelope = try await apiClient.getMyFamily()
            let others = envelope.data.members.filter { $0.userId != envelope.data.me.userId }
            state = .loaded(
                myUserId: envelope.data.me.userId,
                isParent: envelope.data.me.role == "parent",
                familyName: envelope.data.familyName,
                otherMembers: others
            )
        } catch {
            switch (error as? APIError)?.serverCode {
            case .familyNotFound, .profileNotFound:
                state = .familyless
            default:
                state = .error(userFacingMessage(for: error))
            }
        }
    }
}
