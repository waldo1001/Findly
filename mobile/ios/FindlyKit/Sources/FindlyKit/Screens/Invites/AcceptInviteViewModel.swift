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
    /// `displayName` when one exists". `nil` until `loadDisplayNameFallback()` runs (or on any
    /// failure/ambiguous result — this is a convenience prefill, never on the join's critical
    /// path).
    @Published public private(set) var resolvedDisplayName: String?
    private let apiClient: FindlyAPIClient

    public init(apiClient: FindlyAPIClient) {
        self.apiClient = apiClient
    }

    /// specs/010-app-shell-and-screen-ux.md §5.2, specs/001-api-contract.md §3.2/§4.2 — mirrors
    /// Android's `loadDisplayNameFallback()` exactly (review fix, I37 round 2; the original
    /// `resolveExistingDisplayName()` shipped a PII-misattribution bug: it called `GET /devices`
    /// unconditionally and adopted `devices.first?.ownerDisplayName`, but 001 §4.2's
    /// `ownerDisplayName`-equals-own-`displayName` guarantee holds ONLY for a family-less caller —
    /// for a caller who already has a family, that response carries EVERY member's devices in
    /// unspecified order, so "first" is an ARBITRARY OTHER member's name. Reachable because
    /// `handleDeepLink` pushes `.acceptInvite` for a family-invite link with no check of the
    /// caller's family state, so a user already in a family who taps a stale/forwarded/hostile
    /// link could land here with another member's name silently prefilled as their own).
    ///
    /// Three outcomes, each confirmed by its own network response rather than a cached/inferred
    /// guess (`FamilyContextCache` is NOT used here — this screen is reachable via a deep link
    /// arriving before the launch probe ever populates it):
    /// 1. `GET /families/me` succeeds (caller HAS a family) → resolve `me.userId` against
    ///    `members`, a precise self-match — NEVER "first member". `listDevices()` is NEVER
    ///    called in this branch.
    /// 2. A CONFIRMED `404 FAMILY_NOT_FOUND` (caller is genuinely family-less — the ONLY state
    ///    001 §4.2's guarantee actually covers) → falls back to
    ///    `listDevices().first?.ownerDisplayName`.
    /// 3. Any other outcome (transient failure, a different error code, a decoding surprise) →
    ///    leaves `resolvedDisplayName` nil and never calls `listDevices()`. An ambiguous/transient
    ///    outcome is NEVER treated as a confirmed family-less state — conflating the two is
    ///    exactly the fail-open defect 000/A37 tracks elsewhere in this codebase. Never a hard
    ///    error either way: this is a convenience prefill, not on the join's critical path.
    ///
    public func loadDisplayNameFallback() async {
        do {
            let envelope = try await apiClient.getMyFamily()
            let myUserId = envelope.data.me.userId
            resolvedDisplayName = envelope.data.members.first(where: { $0.userId == myUserId })?.displayName
        } catch {
            guard (error as? APIError)?.serverCode == .familyNotFound else {
                // Ambiguous/transient (or any error code other than a CONFIRMED family-less
                // state) — never guess, never fall back to listDevices() here.
                resolvedDisplayName = nil
                return
            }
            do {
                let envelope = try await apiClient.listDevices()
                resolvedDisplayName = envelope.data.devices.first?.ownerDisplayName
            } catch {
                resolvedDisplayName = nil
            }
        }
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
