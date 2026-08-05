import Foundation

/// specs/004-ios-client.md §3.4 (001 §3.1; I17) — the client's ONLY `POST /families` entry point.
/// Before I17, `createFamily` existed solely in the networking layer
/// (`Networking/Endpoints/FamiliesEndpoints.swift`/`FindlyAPIClient.swift`) with no screen or view
/// model calling it, leaving a brand-new signed-in user with no way to bootstrap a `Users` profile
/// row (001 §1.5.3) — verified against the live backend: `GET /v1/groups`, `/v1/families/me` and
/// `/v1/devices` all returned `404 PROFILE_NOT_FOUND` for a fresh user.
///
/// Reachable both from an already-profiled user (rare — the server rejects with
/// `409 FAMILY_ALREADY_MEMBER`, surfaced as an ordinary `.error`) and, more importantly, from the
/// profile-less first-run flow (`HomeViewModel.State.profileless`) where this is one of the four
/// 001 §1.5.3 bootstrap paths.
///
/// Same "gate before any network call" shape as `CreateGroupViewModel`/`GroupJoinViewModel`, but
/// `displayName` is REQUIRED unconditionally here (001 §3.1) — unlike §12.1/§12.6's create/join
/// group, there is no "optional, defaults to the profile's" case for create-family at all
/// (`backend/src/http/validate.ts`), so the guard below is unconditional, not gated behind a
/// `needsDisplayName` flag the way `CreateGroupViewModel`/`GroupJoinViewModel` need one.
@MainActor
public final class CreateFamilyViewModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case creating
        case created(CreateFamilyResponse)
        case error(String)
    }

    @Published public private(set) var state: State = .idle
    private let apiClient: FindlyAPIClient

    public init(apiClient: FindlyAPIClient) {
        self.apiClient = apiClient
    }

    /// Client-side mirror of 001 §3.1's validation (`familyName` 1-50 chars, `displayName` 1-30
    /// chars) — the server remains authoritative regardless (defense in depth, same convention as
    /// every other screen's `validate`/guard step).
    public func createFamily(familyName: String, displayName: String) async {
        let trimmedFamilyName = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFamilyName.isEmpty else {
            state = .error("Enter a name for your family.")
            return
        }
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDisplayName.isEmpty else {
            state = .error("Enter a display name.")
            return
        }
        state = .creating
        do {
            let envelope = try await apiClient.createFamily(familyName: trimmedFamilyName, displayName: trimmedDisplayName)
            state = .created(envelope.data)
        } catch {
            state = .error(userFacingMessage(for: error))
        }
    }
}
