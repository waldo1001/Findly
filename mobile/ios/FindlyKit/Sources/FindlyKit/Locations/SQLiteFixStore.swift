import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

/// specs/009-device-runtime.md §2 — the durable `FixStoring` implementation that replaces
/// `InMemoryFixStore` for a real device build, behind the *unchanged* `FixStoring` protocol.
///
/// **SQLite over Core Data, deliberately (I10 judgment call).** specs/004 §1.1 already lived
/// through the exact "hand-authoring a binary/XML artifact with no way to validate it" risk when
/// it deferred `Findly.xcodeproj` rather than hand-write a `project.pbxproj` — I9 later resolved
/// that by generating the file with a tool (`xcodegen`) instead of by hand. A hand-edited
/// `.xcdatamodeld` (Core Data's model file, an Xcode-GUI-authored bundle of XML + compiled
/// `.mom`/`.omo` binaries) is the same risk shape: no GUI model editor is used in this session, and
/// there is no tool here that validates a hand-written `.xcdatamodeld` the way `xcodegen generate`
/// + `xcodebuild` together validate a generated `.pbxproj`. For a single flat table with one
/// pending/frozen boolean-ish column, Core Data's relationship graph and change-tracking machinery
/// buy nothing — raw SQLite via the system `SQLite3` C library (part of the OS on both iOS and
/// macOS, zero new SPM dependency, works identically in `swift test` and on-device) is simpler,
/// fully within this session's ability to author *and verify* (a real `.sqlite` file this session
/// can open/introspect/write reproducible tests against, including the file-reopen "process death"
/// test below), and avoids the unvalidatable-artifact risk entirely. Mirrors Android's
/// `RoomFixQueueDao`'s SQL-transaction approach one level down the abstraction stack (no ORM, but
/// the same "one atomic transaction per composite operation" discipline).
///
/// Every "composite" operation below (`append`'s cap-enforcement, `freezeNextBatch`,
/// `markAccepted`, `markRejected`) runs inside a single `BEGIN IMMEDIATE ... COMMIT` transaction —
/// this is the load-bearing property specs/009 §2 exists for: a process death strictly before or
/// after the transaction commits leaves either the old state or the new one, never a partial mix
/// (see `SQLiteFixStoreTests.survivesSimulatedProcessDeath...` for the test that proves it by
/// literally closing the connection and reopening a fresh instance against the same file).
///
/// Thread-safety: this class does no locking of its own. It doesn't need to — `FixQueue` (its only
/// production caller) is an `actor`, so every call arrives already serialized by Swift concurrency.
public final class SQLiteFixStore: FixStoring {
    private var db: OpaquePointer?
    private let cap: Int
    private let onOverflowDropped: (Int) -> Void

    public enum StoreError: Error, Equatable {
        case openFailed(String)
        case sqlFailed(String)
    }

    /// - Parameters:
    ///   - url: the on-disk file this store persists to. Passing the SAME url across two separate
    ///     `SQLiteFixStore` instances (e.g. across a process restart) is exactly what makes the
    ///     in-flight batch identity durable — see this type's top doc.
    ///   - cap: specs/009 §2's 1 000-fix cap (overridable for tests).
    ///   - onOverflowDropped: invoked with a **count only** whenever `append` drops fixes to the
    ///     cap — never coordinates (docs/security-review-checklist.md). The real on-device wiring
    ///     logs this at debug level.
    public init(url: URL, cap: Int = 1000, onOverflowDropped: @escaping (Int) -> Void = { _ in }) throws {
        self.cap = cap
        self.onOverflowDropped = onOverflowDropped
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite3_open_v2 failed"
            throw StoreError.openFailed(message)
        }
        self.db = handle
        // WAL is friendlier to the "reopen the same file from a fresh instance" durability test
        // and to real on-device usage (readers never block a writer mid-transaction).
        try exec("PRAGMA journal_mode=WAL;")
        try exec("""
        CREATE TABLE IF NOT EXISTS fixes (
            seq INTEGER PRIMARY KEY AUTOINCREMENT,
            fixId TEXT NOT NULL UNIQUE,
            recordedAt TEXT NOT NULL,
            lat REAL NOT NULL,
            lon REAL NOT NULL,
            accuracyM REAL NOT NULL,
            altitudeM REAL,
            speedMps REAL,
            bearingDeg REAL,
            batteryPct INTEGER NOT NULL,
            source TEXT NOT NULL,
            batchId TEXT
        );
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_fixes_batchId ON fixes(batchId);")
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - FixStoring

    public func loadAll() -> [LocationFix] {
        (try? queryFixes(sql: "SELECT * FROM fixes ORDER BY seq ASC;")) ?? []
    }

    @discardableResult
    public func append(_ fix: LocationFix) -> Int {
        (try? withTransaction { () -> Int in
            try insert(fix)
            let total = try scalarInt("SELECT COUNT(*) FROM fixes;")
            let overflow = total - cap
            guard overflow > 0 else { return 0 }
            let toDropIds = try queryStrings(
                sql: "SELECT fixId FROM fixes WHERE batchId IS NULL ORDER BY seq ASC LIMIT ?;",
                bind: { try self.bindInt($0, index: 1, value: overflow) }
            )
            guard !toDropIds.isEmpty else { return 0 }
            try deleteByIds(toDropIds)
            return toDropIds.count
        }) .map { dropped in
            if dropped > 0 { onOverflowDropped(dropped) }
            return dropped
        } ?? 0
    }

    public func remove(fixIds: Set<String>) {
        guard !fixIds.isEmpty else { return }
        try? withTransaction {
            try self.deleteByIds(Array(fixIds))
        }
    }

    public func currentBatch() -> PendingBatch? {
        (try? currentBatchLocked()) ?? nil
    }

    public func freezeNextBatch(maxSize: Int, newBatchId: () -> String) -> PendingBatch? {
        // newBatchId() is a caller-supplied closure (typically `{ UUID().uuidString }`) - it must
        // only ever be invoked when a NEW batch is actually being minted, never on a retry. We
        // resolve it outside the SQL transaction (it does no I/O) but only call it after
        // confirming no batch is already frozen, inside the same logical operation.
        var mintedId: String?
        let result: PendingBatch? = try? withTransaction {
            if let existing = try self.currentBatchLocked() { return existing }
            // Post-review fix: LIMIT is now bound as a parameter, matching every other query in
            // this file's "always bind, never splice" discipline — previously interpolated
            // directly into the SQL text (not exploitable here, maxSize is an internal, never
            // user/network-supplied Int, but inconsistent with the rest of the file).
            let pending = try self.queryFixes(
                sql: "SELECT * FROM fixes WHERE batchId IS NULL ORDER BY seq ASC LIMIT ?;",
                bind: { try self.bindInt($0, index: 1, value: max(maxSize, 0)) }
            )
            guard !pending.isEmpty else { return nil }
            let batchId = newBatchId()
            mintedId = batchId
            try self.assignBatch(batchId: batchId, fixIds: pending.map(\.fixId))
            return PendingBatch(batchId: batchId, fixes: pending)
        } ?? nil
        _ = mintedId // kept for clarity/debuggability; no further use needed today.
        return result
    }

    public func markAccepted(batchId: String) {
        try? withTransaction {
            let ids = try self.queryStrings(sql: "SELECT fixId FROM fixes WHERE batchId = ?;", bind: { try self.bindText($0, index: 1, value: batchId) })
            guard !ids.isEmpty else { return }
            try self.deleteByIds(ids)
        }
    }

    public func markRejected(batchId: String, dropFixIds: Set<String>?) {
        try? withTransaction {
            let idsToDrop: [String]
            if let dropFixIds {
                idsToDrop = Array(dropFixIds)
            } else {
                idsToDrop = try self.queryStrings(sql: "SELECT fixId FROM fixes WHERE batchId = ?;", bind: { try self.bindText($0, index: 1, value: batchId) })
            }
            if !idsToDrop.isEmpty { try self.deleteByIds(idsToDrop) }
            try self.exec("UPDATE fixes SET batchId = NULL WHERE batchId = ?;", bind: { try self.bindText($0, index: 1, value: batchId) })
        }
    }

    public func removeAll() {
        try? exec("DELETE FROM fixes;")
    }

    // MARK: - Internals

    private func currentBatchLocked() throws -> PendingBatch? {
        guard let batchId = try queryStrings(sql: "SELECT DISTINCT batchId FROM fixes WHERE batchId IS NOT NULL LIMIT 1;", bind: nil).first else {
            return nil
        }
        let fixes = try queryFixes(sql: "SELECT * FROM fixes WHERE batchId = ? ORDER BY seq ASC;", bind: { try self.bindText($0, index: 1, value: batchId) })
        return PendingBatch(batchId: batchId, fixes: fixes)
    }

    private func insert(_ fix: LocationFix) throws {
        let sql = """
        INSERT INTO fixes (fixId, recordedAt, lat, lon, accuracyM, altitudeM, speedMps, bearingDeg, batteryPct, source, batchId)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL);
        """
        var statement: OpaquePointer?
        try checked(sqlite3_prepare_v2(db, sql, -1, &statement, nil), context: "prepare insert")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, fix.fixId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, fix.recordedAt, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 3, fix.lat)
        sqlite3_bind_double(statement, 4, fix.lon)
        sqlite3_bind_double(statement, 5, fix.accuracyM)
        if let altitudeM = fix.altitudeM { sqlite3_bind_double(statement, 6, altitudeM) } else { sqlite3_bind_null(statement, 6) }
        if let speedMps = fix.speedMps { sqlite3_bind_double(statement, 7, speedMps) } else { sqlite3_bind_null(statement, 7) }
        if let bearingDeg = fix.bearingDeg { sqlite3_bind_double(statement, 8, bearingDeg) } else { sqlite3_bind_null(statement, 8) }
        sqlite3_bind_int(statement, 9, Int32(fix.batteryPct))
        sqlite3_bind_text(statement, 10, fix.source.rawValue, -1, SQLITE_TRANSIENT)
        try checked(sqlite3_step(statement), context: "step insert", expecting: SQLITE_DONE)
    }

    private func assignBatch(batchId: String, fixIds: [String]) throws {
        let sql = "UPDATE fixes SET batchId = ? WHERE fixId = ?;"
        var statement: OpaquePointer?
        try checked(sqlite3_prepare_v2(db, sql, -1, &statement, nil), context: "prepare assignBatch")
        defer { sqlite3_finalize(statement) }
        for fixId in fixIds {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_text(statement, 1, batchId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, fixId, -1, SQLITE_TRANSIENT)
            try checked(sqlite3_step(statement), context: "step assignBatch", expecting: SQLITE_DONE)
        }
    }

    private func deleteByIds(_ fixIds: [String]) throws {
        let sql = "DELETE FROM fixes WHERE fixId = ?;"
        var statement: OpaquePointer?
        try checked(sqlite3_prepare_v2(db, sql, -1, &statement, nil), context: "prepare deleteByIds")
        defer { sqlite3_finalize(statement) }
        for fixId in fixIds {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_text(statement, 1, fixId, -1, SQLITE_TRANSIENT)
            try checked(sqlite3_step(statement), context: "step deleteByIds", expecting: SQLITE_DONE)
        }
    }

    private func queryFixes(sql: String, bind: ((OpaquePointer?) throws -> Void)? = nil) throws -> [LocationFix] {
        var statement: OpaquePointer?
        try checked(sqlite3_prepare_v2(db, sql, -1, &statement, nil), context: "prepare queryFixes")
        defer { sqlite3_finalize(statement) }
        try bind?(statement)
        var results: [LocationFix] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            try checked(step, context: "step queryFixes", expecting: SQLITE_ROW)
            results.append(readFix(statement))
        }
        return results
    }

    private func readFix(_ statement: OpaquePointer?) -> LocationFix {
        func text(_ index: Int32) -> String { String(cString: sqlite3_column_text(statement, index)) }
        func optionalDouble(_ index: Int32) -> Double? {
            sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_double(statement, index)
        }
        // Column order matches "SELECT * FROM fixes": seq, fixId, recordedAt, lat, lon, accuracyM,
        // altitudeM, speedMps, bearingDeg, batteryPct, source, batchId.
        return LocationFix(
            fixId: text(1),
            recordedAt: text(2),
            lat: sqlite3_column_double(statement, 3),
            lon: sqlite3_column_double(statement, 4),
            accuracyM: sqlite3_column_double(statement, 5),
            altitudeM: optionalDouble(6),
            speedMps: optionalDouble(7),
            bearingDeg: optionalDouble(8),
            batteryPct: Int(sqlite3_column_int(statement, 9)),
            source: FixSource(rawValue: text(10)) ?? .periodic
        )
    }

    private func queryStrings(sql: String, bind: ((OpaquePointer?) throws -> Void)?) throws -> [String] {
        var statement: OpaquePointer?
        try checked(sqlite3_prepare_v2(db, sql, -1, &statement, nil), context: "prepare queryStrings")
        defer { sqlite3_finalize(statement) }
        try bind?(statement)
        var results: [String] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            try checked(step, context: "step queryStrings", expecting: SQLITE_ROW)
            results.append(String(cString: sqlite3_column_text(statement, 0)))
        }
        return results
    }

    private func scalarInt(_ sql: String) throws -> Int {
        var statement: OpaquePointer?
        try checked(sqlite3_prepare_v2(db, sql, -1, &statement, nil), context: "prepare scalarInt")
        defer { sqlite3_finalize(statement) }
        try checked(sqlite3_step(statement), context: "step scalarInt", expecting: SQLITE_ROW)
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func bindText(_ statement: OpaquePointer?, index: Int32, value: String) throws {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func bindInt(_ statement: OpaquePointer?, index: Int32, value: Int) throws {
        sqlite3_bind_int(statement, index, Int32(value))
    }

    /// Runs `body` inside `BEGIN IMMEDIATE ... COMMIT` — `BEGIN IMMEDIATE` (not the default
    /// deferred `BEGIN`) acquires the write lock up front, which is what makes the "assign batchId
    /// to every row read in this same operation" sequence in `freezeNextBatch` genuinely atomic
    /// rather than merely appearing so under low contention. Rolls back on any thrown error.
    ///
    /// Internal (not `private`), matching `URLSessionAPIClient.makeRequest`/`send`'s established
    /// precedent in this codebase — so `SQLiteFixStoreTests` can fault-inject a failure directly
    /// (a real mid-transaction write followed by a thrown error) and assert the write was rolled
    /// back, which no combination of the public `FixStoring` methods can trigger on their own
    /// (the schema's only constraint, `fixId UNIQUE`, fails on the very first statement of any
    /// transaction that hits it, before anything has been written that would need undoing).
    @discardableResult
    func withTransaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE;")
        do {
            let value = try body()
            try exec("COMMIT;")
            return value
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    /// Internal (not `private`) for the same reason as `withTransaction` above.
    func exec(_ sql: String, bind: ((OpaquePointer?) throws -> Void)? = nil) throws {
        if bind == nil {
            var errorPointer: UnsafeMutablePointer<Int8>?
            let result = sqlite3_exec(db, sql, nil, nil, &errorPointer)
            if result != SQLITE_OK {
                let message = errorPointer.map { String(cString: $0) } ?? "unknown sqlite error"
                sqlite3_free(errorPointer)
                throw StoreError.sqlFailed("\(sql): \(message)")
            }
            return
        }
        var statement: OpaquePointer?
        try checked(sqlite3_prepare_v2(db, sql, -1, &statement, nil), context: "prepare exec")
        defer { sqlite3_finalize(statement) }
        try bind?(statement)
        try checked(sqlite3_step(statement), context: "step exec", expecting: SQLITE_DONE)
    }

    private func checked(_ result: Int32, context: String, expecting: Int32 = SQLITE_OK) throws {
        guard result == expecting else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw StoreError.sqlFailed("\(context): code \(result) (\(message))")
        }
    }
}

// `sqlite3_bind_text`'s destructor parameter: SQLITE_TRANSIENT tells SQLite to copy the string
// immediately rather than assume the pointer outlives the call (SQLITE_STATIC would be unsafe
// here since Swift `String` buffers are not guaranteed stable across the call). This is the
// standard workaround for SQLITE_TRANSIENT not importing cleanly into Swift as a constant.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
