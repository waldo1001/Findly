import SwiftUI

/// specs/004-ios-client.md §3.6, specs/008-privacy-endpoints.md §3 — data export, composed ONLY
/// from design-system components plus the documented system-primitive exception (`ShareLink`, same
/// pattern as the invite/group-detail share cards). `GET /export` is the one unenveloped response in
/// the API (001 §13.1). All artifact-file handling (write, opaque naming, data-protection/backup
/// exclusion, cleanup) lives in `ExportViewModel`/`ExportArtifactStoring` (specs/008 §3.1, review
/// finding #1) — this screen's only job with the result is handing `viewModel.shareURL` to
/// `ShareLink`.
///
/// **Deliberately no teardown/dismissal cleanup here (§3.1 rule 2, amended).** The OS share sheet
/// hands the file's URL to another app, which may read it lazily/asynchronously — a "Save to
/// Files"-style target's read can still be in flight after the sheet dismisses or this screen
/// disappears. Clearing on either signal would race that consumer and could delete the file out
/// from under it. The artifact is instead bounded by: the next export's own defensive clear
/// (`ExportArtifactStoring.write`), a one-shot cleanup at app cold start (`FindlyApp.init`), and
/// the account-deletion local wipe (`DeleteAccountViewModel`) — none of which can race an
/// in-progress share.
public struct ExportScreen: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var viewModel: ExportViewModel

    public init(viewModel: ExportViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            FindlyNavBar("Export data")
            content
        }
        .background(theme.colors.surfaceVariant)
        .task { await viewModel.load() }
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
                if let url = viewModel.shareURL {
                    ShareLink("Save or share the export", item: url)
                }
                exportRow(title: "Export my data", userId: nil)
                if isParent && !members.isEmpty {
                    Text("Export a family member's data")
                        .font(theme.typography.labelSmall)
                        .foregroundColor(theme.colors.onSurface.opacity(0.7))
                    ForEach(members, id: \.userId) { member in
                        exportRow(title: "Export \(member.displayName)'s data", userId: member.userId)
                    }
                }
            }
            .padding(theme.spacing.md)
        }
    }

    private func exportRow(title: String, userId: String?) -> some View {
        FindlyButton(title, style: .secondary) {
            Task { await viewModel.export(userId: userId) }
        }
    }
}
