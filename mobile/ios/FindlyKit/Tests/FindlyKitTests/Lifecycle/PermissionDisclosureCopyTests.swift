import Testing
@testable import FindlyKit

/// specs/009 §7 "Ongoing visibility" (amended 2026-10-12, 000 §D21 (a), I65) — the disclosure MUST NOT promise an indicator.
struct PermissionDisclosureCopyTests {
    @Test func noDisclosureStringMentionsAnIndicator() {
        for kind in [PermissionDisclosureKind.foreground, .background] {
            for point in PermissionDisclosureCopy.points(for: kind) {
                #expect(!point.lowercased().contains("indicator"))
            }
        }
    }

    /// specs/009 §7 "Presence needs background permission" (I67) — the required sentence, verbatim, as the last point.
    @Test func backgroundDisclosureStatesWhatAlwaysEnables() {
        let sentence = "Without 'Always', your family only sees you while Findly is open, and 'Locate now' cannot reach this phone."
        let points = PermissionDisclosureCopy.points(for: .background)
        #expect(points.contains(sentence))
        #expect(points.last == sentence)
    }
}
