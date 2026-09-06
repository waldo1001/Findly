import Foundation
import Testing
@testable import FindlyKit

/// specs/009-device-runtime.md §5.1 "Requester side": a `.late` position is "rendered exactly like
/// fresh plus an age caption". Pure formatter — no wall clock dependency.
struct LocateAgeCaptionTests {
    private static let iso = ISO8601DateFormatter()

    @Test func lessThanOneMinuteOld_rendersJustNow() {
        let recordedAt = "2026-07-19T09:14:40Z"
        let now = Self.iso.date(from: "2026-07-19T09:15:00Z")!

        #expect(LocateAgeCaption.forRecordedAt(recordedAt, now: now) == "just now")
    }

    @Test func oneMinuteOld_rendersSingular() {
        let recordedAt = "2026-07-19T09:14:00Z"
        let now = Self.iso.date(from: "2026-07-19T09:15:00Z")!

        #expect(LocateAgeCaption.forRecordedAt(recordedAt, now: now) == "1 minute ago")
    }

    @Test func multipleMinutesOld_rendersPlural() {
        let recordedAt = "2026-07-19T09:00:00Z"
        let now = Self.iso.date(from: "2026-07-19T09:15:00Z")!

        #expect(LocateAgeCaption.forRecordedAt(recordedAt, now: now) == "15 minutes ago")
    }

    @Test func malformedRecordedAt_neverCrashes_rendersEmpty() {
        #expect(LocateAgeCaption.forRecordedAt("not-a-date") == "")
    }
}
