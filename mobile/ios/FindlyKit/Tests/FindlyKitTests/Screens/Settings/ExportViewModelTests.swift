import Foundation
import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §3.6, specs/008-privacy-endpoints.md §3 — export: self-export for every
/// user with a profile, parent-for-a-member, the raw-`Data` path (never decoded through the §3.1
/// envelope), the `exportsPerDay` friendly message, and confirmation gating (loading the roster
/// alone never triggers a download).
@MainActor
struct ExportViewModelTests {

    /// specs/001-api-contract.md §13.1 — `userId` targets "another current member of the caller's
    /// family"; the caller is never a valid export-picker target for THEMSELVES via that path (the
    /// separate "Export my data" row already covers self, via `userId: nil`). Review finding #2:
    /// `members` (§3.2 shape) includes the caller like any other roster entry, so `load()` MUST
    /// filter them out before handing the list to the picker — mirroring
    /// `DeleteAccountViewModel.load()`'s existing `$0.userId != me.userId` self-filter.
    @Test func load_parent_populatesRosterWithOtherMembersOnly_excludingSelf() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            TestFeatures.envelope(GetMyFamilyResponse(
                familyId: "fam_1", familyName: "Wauters", createdAt: "2026-07-19T08:00:00Z",
                me: MeSummary(userId: "u1", role: "parent"),
                members: [
                    FamilyMember(userId: "u1", role: "parent", displayName: "Eric", joinedAt: "2026-07-19T08:00:00Z"),
                    FamilyMember(userId: "u2", role: "member", displayName: "Noor", joinedAt: "2026-07-19T08:00:00Z"),
                ]
            ))
        }
        let viewModel = ExportViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.state == .loaded(isParent: true, members: [
            FamilyMember(userId: "u2", role: "member", displayName: "Noor", joinedAt: "2026-07-19T08:00:00Z"),
        ]), "the caller (u1/Eric) must not appear as one of their own 'family members' to export")
    }

    @Test func load_nonParentMember_isParentFalse() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            TestFeatures.envelope(GetMyFamilyResponse(
                familyId: "fam_1", familyName: "Wauters", createdAt: "2026-07-19T08:00:00Z",
                me: MeSummary(userId: "u2", role: "member"), members: []
            ))
        }
        let viewModel = ExportViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.state == .loaded(isParent: false, members: []))
    }

    @Test func load_familyLess_stillLoadedForSelfExport() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .familyNotFound, message: "x", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = ExportViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.state == .loaded(isParent: false, members: []), "a family-less user can still export themselves")
    }

    @Test func load_otherFailure_setsErrorState() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = { throw APIError.transport("offline") }
        let viewModel = ExportViewModel(apiClient: api)

        await viewModel.load()

        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    @Test func load_neverCallsExportData() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            TestFeatures.envelope(GetMyFamilyResponse(
                familyId: "fam_1", familyName: "Wauters", createdAt: "2026-07-19T08:00:00Z",
                me: MeSummary(userId: "u1", role: "parent"), members: []
            ))
        }
        let viewModel = ExportViewModel(apiClient: api)

        await viewModel.load()

        #expect(api.exportDataCalls.isEmpty)
    }

    @Test func export_self_passesNilUserId_andStoresRawData() async {
        let api = FakeAPIClient()
        let document = "{\"formatVersion\":1}".data(using: .utf8)!
        api.exportDataHandler = { userId in
            #expect(userId == nil)
            return document
        }
        let viewModel = ExportViewModel(apiClient: api)

        await viewModel.export(userId: nil)

        #expect(viewModel.exportedData == document)
        #expect(viewModel.exportError == nil)
    }

    @Test func export_member_passesTheGivenUserId() async {
        let api = FakeAPIClient()
        api.exportDataHandler = { userId in
            #expect(userId == "u2")
            return Data()
        }
        let viewModel = ExportViewModel(apiClient: api)

        await viewModel.export(userId: "u2")

        #expect(api.exportDataCalls == ["u2"])
    }

    @Test func export_limitExceeded_setsAFriendlyExportSpecificError() async {
        let api = FakeAPIClient()
        api.exportDataHandler = { _ in
            throw APIError.server(
                APIErrorBody(code: .limitExceeded, message: "x", details: ["limit": .string("exportsPerDay")], requestId: "r1"),
                httpStatus: 402
            )
        }
        let viewModel = ExportViewModel(apiClient: api)

        await viewModel.export(userId: nil)

        #expect(viewModel.exportError?.lowercased().contains("tomorrow") == true)
        #expect(viewModel.exportedData == nil)
    }

    // MARK: - Export-artifact hygiene (specs/008-privacy-endpoints.md §3.1, review finding #1)
    //
    // The blocking finding this closes: the export document — one subject's complete movement
    // history — was written straight to `FileManager.default.temporaryDirectory` with the
    // subject's real `uid` in the filename, and never deleted. These tests prove the ViewModel
    // (not the untestable SwiftUI `ExportScreen`) now owns that lifecycle end-to-end through
    // `ExportArtifactStoring`, so it's the same testable layer as `DeleteAccountViewModel`'s wipe.

    @Test func export_success_writesDataThroughTheArtifactStore_andPublishesItsURL() async {
        let api = FakeAPIClient()
        let document = "{\"formatVersion\":1}".data(using: .utf8)!
        api.exportDataHandler = { _ in document }
        let store = InMemoryExportArtifactStore()
        let viewModel = ExportViewModel(apiClient: api, exportArtifactStore: store)

        await viewModel.export(userId: nil)

        #expect(viewModel.shareURL != nil)
        #expect(viewModel.shareURL == store.currentURL, "the Screen's ShareLink must point at the artifact store's own file, not an ad hoc temp write")
        #expect(store.writtenData[viewModel.shareURL!] == document)
    }

    /// Rule 2's "defensively... on the next export" — exporting a second subject (e.g. a parent
    /// exporting two different children back to back) must not leave the first export's file
    /// behind. `ExportArtifactStoring.write` already guarantees this internally; this proves
    /// `ExportViewModel.export` actually routes through it end-to-end rather than, say, writing
    /// straight to a fixed path itself.
    @Test func export_secondCall_removesThePreviousArtifactFirst() async {
        let api = FakeAPIClient()
        api.exportDataHandler = { _ in Data("second".utf8) }
        let store = InMemoryExportArtifactStore()
        let firstURL = try! store.write(Data("first".utf8))
        let viewModel = ExportViewModel(apiClient: api, exportArtifactStore: store)

        await viewModel.export(userId: nil)

        #expect(store.writtenData[firstURL] == nil, "the previous export must be gone once a new one starts")
        #expect(viewModel.shareURL != firstURL)
    }

    /// Rule 2's "removed once the share/save interaction completes or is dismissed... and on
    /// screen teardown" — `ExportScreen` calls this on share completion/dismissal and
    /// `onDisappear`. An export artifact MUST NOT survive the session that created it.
    @Test func clearShareArtifact_removesTheArtifactFromTheStore_andClearsPublishedState() async {
        let api = FakeAPIClient()
        api.exportDataHandler = { _ in Data("export-1".utf8) }
        let store = InMemoryExportArtifactStore()
        let viewModel = ExportViewModel(apiClient: api, exportArtifactStore: store)
        await viewModel.export(userId: nil)
        #expect(viewModel.shareURL != nil)

        viewModel.clearShareArtifact()

        #expect(store.currentURL == nil)
        #expect(viewModel.shareURL == nil)
    }

    @Test func clearShareArtifact_withNothingExported_isANoOp() {
        let store = InMemoryExportArtifactStore()
        let viewModel = ExportViewModel(apiClient: FakeAPIClient(), exportArtifactStore: store)

        viewModel.clearShareArtifact() // must not crash

        #expect(store.removeCallCount == 0)
    }

    /// A disk failure writing the artifact must not leave stale published state pointing at a URL
    /// that doesn't actually exist (or worse, a previous export's URL).
    @Test func export_artifactWriteFailure_clearsPublishedStateAndSetsAnError() async {
        final class AlwaysFailingStore: ExportArtifactStoring {
            struct WriteFailed: Error {}
            func write(_ data: Data) throws -> URL { throw WriteFailed() }
            func removeCurrentArtifact() {}
        }
        let api = FakeAPIClient()
        api.exportDataHandler = { _ in Data("export-1".utf8) }
        let viewModel = ExportViewModel(apiClient: api, exportArtifactStore: AlwaysFailingStore())

        await viewModel.export(userId: nil)

        #expect(viewModel.shareURL == nil)
        #expect(viewModel.exportedData == nil)
        #expect(viewModel.exportError != nil)
    }
}
