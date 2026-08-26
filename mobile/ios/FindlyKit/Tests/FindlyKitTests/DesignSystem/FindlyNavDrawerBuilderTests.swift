import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §1.2 — the drawer's normative item list/order, and the
/// "Invite someone" `myRole == "parent"` gate, as a pure function so both are unit-testable
/// (010 §10: "Drawer: parent-gating of Invite someone; item list/order").
struct FindlyNavDrawerBuilderTests {

    @Test func nonParent_omitsInviteSomeone() {
        let items = FindlyNavDrawerBuilder.items(isParent: false)

        #expect(items.map(\.id) == [
            "familyMap", "history", "geofences", "devices", "family", "groups", "privacyData",
        ])
    }

    @Test func parent_includesInviteSomeoneInNormativeOrder() {
        let items = FindlyNavDrawerBuilder.items(isParent: true)

        #expect(items.map(\.id) == [
            "familyMap", "history", "geofences", "devices", "family", "inviteSomeone", "groups", "privacyData",
        ])
    }

    @Test func familyMapItem_isFirstAndTitled() {
        let items = FindlyNavDrawerBuilder.items(isParent: false)

        #expect(items.first?.title == "Family map")
    }
}
