import SwiftUI

/// specs/004-ios-client.md §3.6, specs/008-privacy-endpoints.md §3 — data export, composed ONLY
/// from design-system components plus the documented system-primitive exception (`ShareLink`, same
/// pattern as the invite/group-detail share cards). `GET /export` is the one unenveloped response in
/// the API (001 §13.1); `ExportViewModel.exportedData` is the raw document, never parsed — this
/// screen's only job with the bytes is writing them to a temporary file so `ShareLink` has a URL to
/// hand to the OS share sheet (a `ShareLink(item: Data)` would need a custom `Transferable`
/// wrapper; a temp file matches how a real device would hand off a downloaded document either way).
public struct ExportScreen: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var viewModel: ExportViewModel
    /// Threaded from `RootView` (`authProvider.currentUserId`) purely to build an accurate
    /// self-export filename (`ExportViewModel.suggestedFileName`) — never sent in a request.
    private let myUserId: String
    @State private var lastRequestedTarget: ExportTarget?
    @State private var pendingShareURL: URL?

    public init(viewModel: ExportViewModel, myUserId: String) {
        self.viewModel = viewModel
        self.myUserId = myUserId
    }

    public var body: some View {
        VStack(spacing: 0) {
            FindlyNavBar("Export data")
            content
        }
        .background(theme.colors.surfaceVariant)
        .task { await viewModel.load() }
        .onChange(of: viewModel.exportedData) { data in
            guard let data, let target = lastRequestedTarget else { return }
            pendingShareURL = Self.writeToTemporaryFile(data: data, userId: target.userId(myUserId: myUserId))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingStateView(message: "Loading…")
        case .error(let message):
            ErrorStateView(message: message) {
                Task { await viewModel.load() }
            }
        case .loaded(let isParent, let members):
            list(isParent: isParent, members: members)
        }
    }

    private func list(isParent: Bool, members: [FamilyMember]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.md) {
                if let exportError = viewModel.exportError {
                    ErrorStateView(message: exportError)
                }
                if let url = pendingShareURL {
                    ShareLink("Save or share the export", item: url)
                }
                exportRow(title: "Export my data", target: .me)
                if isParent && !members.isEmpty {
                    Text("Export a family member's data")
                        .font(theme.typography.labelSmall)
                        .foregroundColor(theme.colors.onSurface.opacity(0.7))
                    ForEach(members, id: \.userId) { member in
                        exportRow(title: "Export \(member.displayName)'s data", target: .member(userId: member.userId, displayName: member.displayName))
                    }
                }
            }
            .padding(theme.spacing.md)
        }
    }

    private func exportRow(title: String, target: ExportTarget) -> some View {
        FindlyButton(title, style: .secondary) {
            pendingShareURL = nil
            lastRequestedTarget = target
            Task { await viewModel.export(userId: target.exportUserId) }
        }
    }

    private static func writeToTemporaryFile(data: Data, userId: String) -> URL? {
        let fileName = ExportViewModel.suggestedFileName(userId: userId)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

/// Which subject an export request targets — `.me` maps to `userId: nil` on the wire (001 §13.1),
/// `.member` is the parent-for-member path.
private enum ExportTarget: Equatable {
    case me
    case member(userId: String, displayName: String)

    /// The value sent to `ExportViewModel.export(userId:)`.
    var exportUserId: String? {
        switch self {
        case .me: return nil
        case .member(let userId, _): return userId
        }
    }

    /// The value used to build the local filename — unlike `exportUserId`, `.me` resolves to the
    /// caller's real id here since the filename is purely cosmetic client-side state, never sent.
    func userId(myUserId: String) -> String {
        switch self {
        case .me: return myUserId
        case .member(let userId, _): return userId
        }
    }
}
