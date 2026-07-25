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
    /// The raw export document (001 §13.1 — never decoded through the §3.1 envelope), ready to
    /// hand to a `ShareLink`/document exporter once populated.
    @Published public private(set) var exportedData: Data?
    @Published public private(set) var exportError: String?

    private let apiClient: FindlyAPIClient

    public init(apiClient: FindlyAPIClient) {
        self.apiClient = apiClient
    }

    public func load() async {
        state = .loading
        do {
            let envelope = try await apiClient.getMyFamily()
            state = .loaded(isParent: envelope.data.me.role == "parent", members: envelope.data.members)
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
    public func export(userId: String?) async {
        exportError = nil
        do {
            exportedData = try await apiClient.exportData(userId: userId)
        } catch {
            exportError = userFacingMessage(for: error)
        }
    }

    /// specs/001-api-contract.md §13.1 — mirrors the server's own `Content-Disposition` filename
    /// (`findly-export-<userId>-<yyyy-MM-dd>.json`) so the on-device share sheet suggests the same
    /// name the server would have sent as a header — this client never reads response headers for
    /// the raw-`Data` export path (`sendRawData`), by design, so this is computed client-side.
    public static func suggestedFileName(userId: String, generatedAt: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return "findly-export-\(userId)-\(formatter.string(from: generatedAt)).json"
    }
}
