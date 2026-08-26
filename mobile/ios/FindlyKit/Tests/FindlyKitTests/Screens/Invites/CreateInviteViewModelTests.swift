import Foundation
import Testing
@testable import FindlyKit

/// specs/004-ios-client.md I2 (001 §3.3).
@MainActor
struct CreateInviteViewModelTests {

    @Test func createInvite_success_transitionsToCreated() async {
        let api = FakeAPIClient()
        api.createInviteHandler = { role, emailHint in
            #expect(role == "member")
            #expect(emailHint == "kid@example.com")
            return TestFeatures.envelope(CreateInviteResponse(inviteCode: "7F3K9QRZ", role: "member", expiresAt: "2026-07-22T10:00:00Z"))
        }
        let viewModel = CreateInviteViewModel(apiClient: api)

        await viewModel.createInvite(role: "member", emailHint: "kid@example.com")

        #expect(viewModel.state == .created(inviteCode: "7F3K9QRZ", role: "member", expiresAt: "2026-07-22T10:00:00Z"))
    }

    @Test func createInvite_failure_setsErrorState() async {
        let api = FakeAPIClient()
        api.createInviteHandler = { _, _ in
            throw APIError.server(APIErrorBody(code: .authForbidden, message: "not a parent", details: nil, requestId: "r1"), httpStatus: 403)
        }
        let viewModel = CreateInviteViewModel(apiClient: api)

        await viewModel.createInvite(role: "member", emailHint: nil)

        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    // MARK: - specs/007-public-join-links.md §4 (normative, added 2026-08-26) — the exact share
    // text template, byte-for-byte, for a fixed code + host (§7's snapshot-test rule).

    @Test func shareText_matchesThe007Section4TemplateExactly() {
        let expected = "Join our family on Findly — invite code 7F3K-9QRZ\nhttps://join.example.test/f#7F3K9QRZ"
        #expect(CreateInviteViewModel.shareText(for: "7f3k9qrz", joinLinkHost: "join.example.test") == expected)
    }

    @Test func shareText_fragmentCodeIsCanonicalUppercaseNoHyphen() {
        // 007 §4: "the fragment {CODE} is canonical (uppercase, no hyphen)" — only the display
        // form inside the sentence is hyphenated.
        let text = CreateInviteViewModel.shareText(for: "7f3k9qrz", joinLinkHost: "join.example.test")
        #expect(text.contains("#7F3K9QRZ"))
        #expect(!text.contains("#7F3K-9QRZ"))
    }

    // MARK: - specs/007-public-join-links.md §1 (added 2026-08-26) — the on-device QR/share link.
    // Built via `URLComponents`, not string interpolation, so the code is provably carried through
    // the **fragment**, never the path or query (the no-oracle privacy property, 007 §1).

    @Test func joinLink_isTheFamilyPathWithCodeInTheFragmentOnly() {
        let link = CreateInviteViewModel.joinLink(for: "7f3k9qrz", joinLinkHost: "join.example.test")

        #expect(link.scheme == "https")
        #expect(link.host == "join.example.test")
        let components = URLComponents(url: link, resolvingAgainstBaseURL: false)!
        #expect(components.path == "/f")
        #expect(components.fragment == "7F3K9QRZ")
        #expect(components.query == nil, "the code must never travel in the query string")
        #expect(!link.absoluteString.contains("?"), "the code must never travel in the query string")
    }

    // MARK: - specs/010-app-shell-and-screen-ux.md §5.1 — expiry rendered from the response's
    // `expiresAt`, never a hardcoded 72h.

    @Test func expiryLocalDateTime_formatsAValidIso8601Timestamp() {
        #expect(CreateInviteViewModel.expiryLocalDateTime(for: "2026-07-22T10:00:00Z") != nil)
    }

    @Test func expiryLocalDateTime_returnsNilForUnparsableInput() {
        #expect(CreateInviteViewModel.expiryLocalDateTime(for: "not-a-date") == nil)
    }
}
