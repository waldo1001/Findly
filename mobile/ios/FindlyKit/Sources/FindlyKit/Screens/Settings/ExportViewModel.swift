import Foundation

/// specs/004-ios-client.md §3.6, specs/008-privacy-endpoints.md §3 — data export. Available to
/// every user with a profile (self); a parent may additionally export a current family member
/// (001 §13.1) — `load()` fetches the roster purely to drive that picker, tolerating a family-less
/// caller (still self-exportable) as `.loaded(isParent: false, members: [])`.
@MainActor
public final class ExportViewModel: ObservableObject {
    public enum State: Equatable {
        case loading
        case loaded(isParent: Bool, members: [FamilyMember])
        case error(String)
    }

    @Published public private(set) var state: State = .loading
    /// The raw export document (001 §13.1 — never decoded through the §3.1 envelope). Kept
    /// alongside `shareURL` mainly for tests/observability — `ExportScreen` hands `shareURL`, not
    /// this, to `ShareLink`.
    @Published public private(set) var exportedData: Data?
    /// specs/008-privacy-endpoints.md §3.1 (review finding #1) — the app-private, opaquely-named
    /// file `exportArtifactStore` just wrote `exportedData` to; `ExportScreen`'s `ShareLink` is
    /// built from THIS, never from an ad hoc temp-file write of its own. `nil` before the first
    /// export, or after a failure. There is deliberately no ViewModel-level way to clear this
    /// early: rule 2 (amended) permits removal only immediately before the next write, at app
    /// cold start, or via the account-deletion wipe — never on screen teardown/share completion,
    /// which would race the OS share sheet's consumer (it may still be reading the file
    /// asynchronously when those signals fire).
    @Published public private(set) var shareURL: URL?
    @Published public private(set) var exportError: String?

    private let apiClient: FindlyAPIClient
    private let exportArtifactStore: ExportArtifactStoring

    public init(apiClient: FindlyAPIClient, exportArtifactStore: ExportArtifactStoring = InMemoryExportArtifactStore()) {
        self.apiClient = apiClient
        self.exportArtifactStore = exportArtifactStore
    }

    public func load() async {
        state = .loading
        do {
            let envelope = try await apiClient.getMyFamily()
            // specs/001-api-contract.md §13.1 (review finding #2) — `userId` targets "another"
            // current family member; the §3.2 `members` roster includes the caller like any other
            // entry, so the caller must never appear as one of their own export targets here (self
            // is already covered by the separate "Export my data" row, `userId: nil`). Mirrors
            // `DeleteAccountViewModel.load()`'s existing self-filter.
            let me = envelope.data.me
            let otherMembers = envelope.data.members.filter { $0.userId != me.userId }
            state = .loaded(isParent: me.role == "parent", members: otherMembers)
        } catch {
            if let code = (error as? APIError)?.serverCode, code == .familyNotFound || code == .profileNotFound {
                state = .loaded(isParent: false, members: [])
            } else {
                state = .error(userFacingMessage(for: error))
            }
        }
    }

    /// `userId == nil` exports the caller; a non-`nil` value is the parent-for-member path — the
    /// server enforces the role/membership check (`403 AUTH_FORBIDDEN`/`404 MEMBER_NOT_FOUND`), not
    /// this method.
    ///
    /// specs/008-privacy-endpoints.md §3.1 (review finding #1) — the fetched document is written to
    /// disk through `exportArtifactStore`, never with an identifier-bearing filename and never left
    /// for `ExportScreen` to materialize itself. `write(_:)` already removes any previous artifact
    /// first (rule 2's "defensively on the next export"), so back-to-back exports (e.g. a parent
    /// exporting two children in a row) never accumulate more than one file. A write failure clears
    /// all published state rather than leaving a stale/successful-looking `shareURL` around.
    public func export(userId: String?) async {
        exportError = nil
        do {
            let data = try await apiClient.exportData(userId: userId)
            let url = try exportArtifactStore.write(data)
            exportedData = data
            shareURL = url
        } catch {
            exportedData = nil
            shareURL = nil
            exportError = userFacingMessage(for: error)
        }
    }
}
