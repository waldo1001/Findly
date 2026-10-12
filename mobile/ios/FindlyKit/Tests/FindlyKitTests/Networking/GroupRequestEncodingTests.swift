import Foundation
import Testing
@testable import FindlyKit

/// specs/001 §12.1/§12.4 (amended 2026-10-12, 000 §D21) — the wire distinction between an absent
/// key and `null` for `endsAt`. Swift's synthesized `Encodable` uses `encodeIfPresent` and would
/// silently drop a `nil`, which the backend answers with `400 VALIDATION_FAILED` on create (the
/// key is REQUIRED) and which on PATCH would mean "unchanged" instead of "remove the end date".
struct GroupRequestEncodingTests {

    private func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(data: try encoder.encode(value), encoding: .utf8)!
    }

    @Test func create_nilEndsAt_emitsExplicitNull() throws {
        let request = CreateGroupRequest(name: "Crew", endsAt: nil, expiryPolicy: "delete", displayName: nil)
        #expect(try json(request) == #"{"endsAt":null,"expiryPolicy":"delete","name":"Crew"}"#)
    }

    @Test func create_nilEndsAt_withDisplayName_stillEmitsNull() throws {
        let request = CreateGroupRequest(name: "Crew", endsAt: nil, expiryPolicy: "archive", displayName: "Eric")
        #expect(try json(request) == #"{"displayName":"Eric","endsAt":null,"expiryPolicy":"archive","name":"Crew"}"#)
    }

    @Test func create_datedEndsAt_emitsString() throws {
        let request = CreateGroupRequest(name: "Crew", endsAt: "2026-08-02T22:00:00Z", expiryPolicy: "grace", displayName: nil)
        #expect(try json(request) == #"{"endsAt":"2026-08-02T22:00:00Z","expiryPolicy":"grace","name":"Crew"}"#)
    }

    @Test func update_unchanged_omitsEndsAtKey() throws {
        let request = UpdateGroupRequest(name: "New", endsAt: .unchanged)
        #expect(try json(request) == #"{"name":"New"}"#)
    }

    @Test func update_clear_emitsExplicitNull() throws {
        let request = UpdateGroupRequest(name: nil, endsAt: .clear)
        #expect(try json(request) == #"{"endsAt":null}"#)
    }

    @Test func update_set_emitsString() throws {
        let request = UpdateGroupRequest(name: nil, endsAt: .set("2026-08-03T22:00:00Z"))
        #expect(try json(request) == #"{"endsAt":"2026-08-03T22:00:00Z"}"#)
    }

    @Test func update_nameAndClear_emitsBoth() throws {
        let request = UpdateGroupRequest(name: "New", endsAt: .clear)
        #expect(try json(request) == #"{"endsAt":null,"name":"New"}"#)
    }
}
