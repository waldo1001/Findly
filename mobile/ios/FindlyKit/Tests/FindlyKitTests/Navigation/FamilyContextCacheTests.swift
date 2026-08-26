import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §1.2 — the drawer header ("family name + the caller's
/// display name") reads from `GET /families/me`, cached from the launch probe rather than a fresh
/// fetch every time the drawer opens. This is the cache itself; `AppLaunchResolverTests` covers
/// population from the actual probe.
@MainActor
struct FamilyContextCacheTests {

    @Test func startsEmpty() {
        let cache = FamilyContextCache()

        #expect(cache.familyName == nil)
        #expect(cache.myDisplayName == nil)
        #expect(cache.isParent == nil)
    }

    @Test func update_publishesAllThreeFields() {
        let cache = FamilyContextCache()

        cache.update(familyName: "Wauters", myDisplayName: "Eric", isParent: true)

        #expect(cache.familyName == "Wauters")
        #expect(cache.myDisplayName == "Eric")
        #expect(cache.isParent == true)
    }

    @Test func clear_resetsAllThreeFields() {
        let cache = FamilyContextCache()
        cache.update(familyName: "Wauters", myDisplayName: "Eric", isParent: true)

        cache.clear()

        #expect(cache.familyName == nil)
        #expect(cache.myDisplayName == nil)
        #expect(cache.isParent == nil)
    }
}
