import Foundation

/// specs/004-ios-client.md §3.4 (001 §12.6) — join a group from a pasted code or a deep link. Every
/// input is normalized/validated by `GroupCodeParsing` BEFORE the network call (security checklist
/// §5 — deep-link inputs validated before use), mirroring `AcceptInviteViewModel`.
@MainActor
public final class GroupJoinViewModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case joining
        case joined(GroupSummary)
        case error(String)
    }

    @Published public private(set) var state: State = .idle
    private let apiClient: FindlyAPIClient

    public init(apiClient: FindlyAPIClient) {
        self.apiClient = apiClient
    }

    /// `rawCode` may be a pasted code OR a full deep link (`findly://group-join?code=<code>` /
    /// the 007 `https://{joinLinkHost}/g#CODE` universal link) — this is the app's primary
    /// external on-ramp (specs/005/007), so it's also the screen a signed-in, profile-less caller
    /// is most likely to land on WITHOUT ever passing through `HomeScreen`'s `.profileless`
    /// bootstrap buttons. `displayName` becomes the caller's per-group nickname (005 §1) if given;
    /// required-if-no-profile, optional otherwise (001 §12.6). **I17 review (Major fix):** whether
    /// this call is bootstrapping a profile is established here from the server's own truth, NOT
    /// from a caller-supplied flag — see `CreateGroupViewModel.createGroup`'s doc for the full
    /// reasoning (a `RootView`-level "which button was tapped" hint is wrong for exactly this
    /// deep-link arrival). Only probed when `displayName` is actually blank.
    public func join(rawCode: String, displayName: String) async {
        guard let code = GroupCodeParsing.normalize(rawCode) else {
            state = .error("That group code doesn't look right. Double-check it and try again.")
            return
        }
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDisplayName.isEmpty, await isBootstrappingProfile() {
            state = .error("Enter a display name.")
            return
        }
        state = .joining
        do {
            let envelope = try await apiClient.joinGroup(code: code, displayName: trimmedDisplayName.isEmpty ? nil : trimmedDisplayName)
            state = .joined(envelope.data)
        } catch {
            state = .error(userFacingMessage(for: error))
        }
    }

    /// `true` only on a confirmed `PROFILE_NOT_FOUND` (001 §1.5.3) — see
    /// `CreateGroupViewModel.isBootstrappingProfile`'s doc for the inconclusive-probe default and
    /// server-side fallback reasoning (identical here).
    private func isBootstrappingProfile() async -> Bool {
        do {
            _ = try await apiClient.getMyFamily()
            return false
        } catch {
            return (error as? APIError)?.serverCode == .profileNotFound
        }
    }
}
