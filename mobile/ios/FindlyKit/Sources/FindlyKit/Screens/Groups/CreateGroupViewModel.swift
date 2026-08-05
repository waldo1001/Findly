import Foundation

/// specs/004-ios-client.md §3.4 (001 §12.1; 005 §2.1) — creates a group. `endsAt`/`expiryPolicy`
/// bounds (≥ now+1h, ≤ `limits.maxGroupDurationDays`) are the server's job (001 §12.1) — not
/// duplicated here beyond what the picker UI needs for a sane default, matching this client's
/// established "server is the source of truth" convention (specs/004 §3.4).
@MainActor
public final class CreateGroupViewModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case creating
        case created(GroupSummary)
        case error(String)
    }

    @Published public private(set) var state: State = .idle
    private let apiClient: FindlyAPIClient

    public init(apiClient: FindlyAPIClient) {
        self.apiClient = apiClient
    }

    /// `displayName` becomes the caller's per-group nickname (005 §1); required-if-no-profile,
    /// optional otherwise (001 §12.1). **I17 review (Major fix):** whether this call is
    /// bootstrapping a profile is established here from the server's own truth, NOT from a
    /// caller-supplied flag — a `RootView`-level "which button was tapped" hint (the pre-fix shape)
    /// is wrong for any arrival route that doesn't run through those specific closures, most
    /// notably a `findly://group-join`-style deep link (007), which `AppCoordinator.handleDeepLink`
    /// routes directly, bypassing `RootView`'s bootstrap-tracking state entirely. Only probed when
    /// `displayName` is actually blank — a non-blank value is valid either way, so the extra
    /// `GET /families/me` round trip is skipped in the common (name provided) case.
    public func createGroup(name: String, endsAt: Date, expiryPolicy: GroupExpiryPolicy, displayName: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            state = .error("Enter a name for the group.")
            return
        }
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDisplayName.isEmpty, await isBootstrappingProfile() {
            state = .error("Enter a display name.")
            return
        }
        state = .creating
        do {
            let envelope = try await apiClient.createGroup(
                name: trimmedName,
                endsAt: Self.iso8601Formatter.string(from: endsAt),
                expiryPolicy: expiryPolicy.rawValue,
                displayName: trimmedDisplayName.isEmpty ? nil : trimmedDisplayName
            )
            state = .created(envelope.data)
        } catch {
            state = .error(userFacingMessage(for: error))
        }
    }

    /// `true` only on a confirmed `PROFILE_NOT_FOUND` (001 §1.5.3) — any other outcome (a genuine
    /// profile, or an inconclusive probe: transport error, `FAMILY_NOT_FOUND`, anything else)
    /// defaults `false`, so a blip never blocks an ordinary already-profiled caller whose
    /// `displayName` genuinely is optional. If this default is ever wrong (a real bootstrap call
    /// slips through blank), the server still enforces it (`400 VALIDATION_FAILED`,
    /// `details.fields: ["displayName"]`) — `APIError+UserMessage` maps that to a specific message,
    /// same "server remains authoritative" fallback as every other client-side guard in this app.
    private func isBootstrappingProfile() async -> Bool {
        do {
            _ = try await apiClient.getMyFamily()
            return false
        } catch {
            return (error as? APIError)?.serverCode == .profileNotFound
        }
    }

    private static let iso8601Formatter = ISO8601DateFormatter()
}
