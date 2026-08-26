import Foundation

/// specs/010-app-shell-and-screen-ux.md §1.2 — the drawer header ("family name + the caller's
/// display name") reads `GET /families/me`, cached from the launch probe rather than re-fetched
/// every time the drawer opens. Populated by `AppLaunchResolver` on a successful probe and kept
/// fresh opportunistically by any screen that already calls `getMyFamily()` for its own reasons
/// (`FamilyMembersViewModel.load()`) or already has the data from its own bootstrap response
/// (`CreateFamilyScreen`'s `onCreated`) — never a dedicated network call of its own.
@MainActor
public final class FamilyContextCache: ObservableObject {
    @Published public private(set) var familyName: String?
    @Published public private(set) var myDisplayName: String?
    @Published public private(set) var isParent: Bool?

    public init(familyName: String? = nil, myDisplayName: String? = nil, isParent: Bool? = nil) {
        self.familyName = familyName
        self.myDisplayName = myDisplayName
        self.isParent = isParent
    }

    public func update(familyName: String, myDisplayName: String, isParent: Bool) {
        self.familyName = familyName
        self.myDisplayName = myDisplayName
        self.isParent = isParent
    }

    /// specs/008-privacy-endpoints.md §4.4 — part of the account-deletion/sign-out local wipe: a
    /// freshly-signed-in different user must never see the previous caller's family name flash in
    /// the drawer.
    public func clear() {
        familyName = nil
        myDisplayName = nil
        isParent = nil
    }
}
