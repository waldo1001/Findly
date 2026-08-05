import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §3.4 (001 §3.1; I17) — the client's only `POST /families` entry point.
/// `displayName` is REQUIRED unconditionally here (unlike §12.1/§12.6's create/join-group, where
/// it's only required when the caller has no profile yet) — same asymmetry
/// `AcceptInviteViewModel` already guards against (`backend/src/http/validate.ts`).
@MainActor
struct CreateFamilyViewModelTests {

    @Test func initialState_isIdle() {
        let viewModel = CreateFamilyViewModel(apiClient: FakeAPIClient())
        #expect(viewModel.state == .idle)
    }

    @Test func createFamily_emptyFamilyName_isRejectedWithoutCallingTheApi() async {
        let api = FakeAPIClient()
        let viewModel = CreateFamilyViewModel(apiClient: api)

        await viewModel.createFamily(familyName: "   ", displayName: "Eric")

        #expect(api.createFamilyCalls.isEmpty)
        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    @Test func createFamily_emptyDisplayName_isRejectedWithoutCallingTheApi() async {
        // I17 review concern (mirroring A21's found gap): displayName is unconditionally required
        // for create-family, unlike create-group/join-group — a blank value must never reach the
        // network.
        let api = FakeAPIClient()
        let viewModel = CreateFamilyViewModel(apiClient: api)

        await viewModel.createFamily(familyName: "Wauters", displayName: "   ")

        #expect(api.createFamilyCalls.isEmpty)
        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    @Test func createFamily_success_sendsTrimmedFieldsAndSetsCreatedState() async {
        let api = FakeAPIClient()
        api.createFamilyHandler = { familyName, displayName in
            #expect(familyName == "Wauters")
            #expect(displayName == "Eric")
            return TestFeatures.envelope(CreateFamilyResponse(
                familyId: "fam_9J2Kq7Lm3NpR5sTvWxYz", familyName: "Wauters",
                member: MemberSummary(userId: "u1", role: "parent", displayName: "Eric")
            ))
        }
        let viewModel = CreateFamilyViewModel(apiClient: api)

        await viewModel.createFamily(familyName: "  Wauters  ", displayName: "  Eric  ")

        #expect(viewModel.state == .created(CreateFamilyResponse(
            familyId: "fam_9J2Kq7Lm3NpR5sTvWxYz", familyName: "Wauters",
            member: MemberSummary(userId: "u1", role: "parent", displayName: "Eric")
        )))
    }

    @Test func createFamily_alreadyMember_setsErrorState() async {
        let api = FakeAPIClient()
        api.createFamilyHandler = { _, _ in
            throw APIError.server(APIErrorBody(code: .familyAlreadyMember, message: "already", details: nil, requestId: "r1"), httpStatus: 409)
        }
        let viewModel = CreateFamilyViewModel(apiClient: api)

        await viewModel.createFamily(familyName: "Wauters", displayName: "Eric")

        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }
}
