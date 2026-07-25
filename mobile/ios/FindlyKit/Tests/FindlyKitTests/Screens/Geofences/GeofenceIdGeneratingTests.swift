import Testing
@testable import FindlyKit

/// specs/004-ios-client.md I2 (001 §1.4 — `geofenceId` slug `gf_[a-z0-9-]{1,30}`, unique within
/// the family config).
struct GeofenceIdGeneratingTests {

    @Test func makeId_slugifiesASimpleName() {
        #expect(GeofenceIdGenerating.makeId(from: "Home", existingIds: []) == "gf_home")
    }

    @Test func makeId_replacesDisallowedCharactersAndCollapsesRuns() {
        #expect(GeofenceIdGenerating.makeId(from: "Noor's School!!", existingIds: []) == "gf_noor-s-school")
    }

    @Test func makeId_trimsLeadingAndTrailingHyphens() {
        #expect(GeofenceIdGenerating.makeId(from: "  Home  ", existingIds: []) == "gf_home")
    }

    @Test func makeId_fallsBackWhenNameHasNoUsableCharacters() {
        #expect(GeofenceIdGenerating.makeId(from: "🏠🏠🏠", existingIds: []) == "gf_geofence")
    }

    @Test func makeId_deduplicatesAgainstExistingIds() {
        let id = GeofenceIdGenerating.makeId(from: "Home", existingIds: ["gf_home"])
        #expect(id == "gf_home-2")
    }

    @Test func makeId_deduplicatesRepeatedlyUntilFree() {
        let id = GeofenceIdGenerating.makeId(from: "Home", existingIds: ["gf_home", "gf_home-2", "gf_home-3"])
        #expect(id == "gf_home-4")
    }

    @Test func makeId_neverExceedsThirtyCharacterSlug() {
        let longName = String(repeating: "a", count: 60)
        let id = GeofenceIdGenerating.makeId(from: longName, existingIds: [])
        #expect(id.hasPrefix("gf_"))
        #expect(id.count <= 33) // "gf_" (3) + slug (<=30)
    }
}
