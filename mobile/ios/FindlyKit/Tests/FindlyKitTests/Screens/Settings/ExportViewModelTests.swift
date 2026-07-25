import Foundation
import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §3.6, specs/008-privacy-endpoints.md §3 — export: self-export for every
/// user with a profile, parent-for-a-member, the raw-`Data` path (never decoded through the §3.1
/// envelope), the `exportsPerDay` friendly message, and confirmation gating (loading the roster
/// alone never triggers a download).
@MainActor
struct ExportViewModelTests {

    @Test func load_parent_populatesRosterAndIsParentTrue() async {
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
            FamilyMember(userId: "u1", role: "parent", displayName: "Eric", joinedAt: "2026-07-19T08:00:00Z"),
            FamilyMember(userId: "u2", role: "member", displayName: "Noor", joinedAt: "2026-07-19T08:00:00Z"),
        ]))
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

    /// specs/001-api-contract.md §13.1 — mirrors the server's own `Content-Disposition` filename.
    @Test func suggestedFileName_matchesTheServerFilenameShape() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 25, hour: 14))!

        let fileName = ExportViewModel.suggestedFileName(userId: "u1", generatedAt: date)

        #expect(fileName == "findly-export-u1-2026-07-25.json")
    }
}
