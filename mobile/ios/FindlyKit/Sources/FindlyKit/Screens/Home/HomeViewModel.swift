import Foundation
import os

/// specs/004-ios-client.md I2/§3.4 — the post-sign-in hub. Loads just enough family context
/// (`GET /families/me`) to know the caller's role (parent vs member) and offer sensible defaults
/// (own history, first other member to locate), so individual feature screens don't each need to
/// re-derive this.
///
/// **Family-less and profile-less are first-class (review-gate finding #3, specs/005 §1, 001 §1.5;
/// I17).** A signed-in user without a family answers `FAMILY_NOT_FOUND` or `PROFILE_NOT_FOUND` to
/// this fetch — neither is the generic `.error`, so `HomeScreen` can still offer a way forward
/// instead of a dead end with a bare error banner. **They are DISTINCT states, not one conflated
/// `.familyless` (I17 fix — the prior conflation was itself a bug):** `FAMILY_NOT_FOUND` (`.familyless`)
/// means the caller already has a `Users` profile row and can use every profile-scoped endpoint,
/// incl. `GET /groups` (001 §12.2) — Groups is a safe, working destination for them.
/// `PROFILE_NOT_FOUND` (`.profileless`) means no profile exists at all (001 §1.5.3): `GET /groups`
/// would 404 too, so the only ways forward are the four profile-bootstrapping endpoints
/// (`POST /families` §3.1, `POST /invites/accept` §3.4, `POST /groups` §12.1, `POST /groups/join`
/// §12.6) — routing this caller to the ordinary Groups list (as the pre-I17 code did) was itself
/// the doomed dead end the review found. Every other failure (transport, decoding, any other server
/// code) still lands in `.error`.
@MainActor
public final class HomeViewModel: ObservableObject {
    public enum State: Equatable {
        case loading
        case loaded(myUserId: String, isParent: Bool, familyName: String, otherMembers: [FamilyMember])
        case familyless
        case profileless
        case error(String)
    }

    @Published public private(set) var state: State = .loading
    private let apiClient: FindlyAPIClient

    public init(apiClient: FindlyAPIClient) {
        self.apiClient = apiClient
    }

    public func load() async {
        state = .loading
        Self.log("load: started")
        do {
            let envelope = try await apiClient.getMyFamily()
            Self.log("load: getMyFamily returned")
            let others = envelope.data.members.filter { $0.userId != envelope.data.me.userId }
            state = .loaded(
                myUserId: envelope.data.me.userId,
                isParent: envelope.data.me.role == "parent",
                familyName: envelope.data.familyName,
                otherMembers: others
            )
        } catch {
            switch (error as? APIError)?.serverCode {
            case .familyNotFound:
                Self.log("load: no family -> familyless")
                state = .familyless
            case .profileNotFound:
                Self.log("load: no profile -> profileless")
                state = .profileless
            default:
                Self.log("load: failed -> error state")
                state = .error(userFacingMessage(for: error))
            }
        }
    }

    /// Home is the first screen every signed-in launch lands on, and it was possible for it to sit
    /// on "Loading your family…" forever with nothing whatsoever in the logs to say why (2026-08-05).
    /// These three breadcrumbs distinguish the cases that look identical from the outside: the call
    /// never started, it started and never returned, or it returned and the state machine moved on.
    ///
    /// Logs control flow only — never the family, member names, or the error's text
    /// (docs/security-review-checklist.md: category only, never payload).
    private static func log(_ message: StaticString) {
        os_log(message, log: OSLog(subsystem: "com.findly.ios", category: "home"), type: .info)
    }
}
