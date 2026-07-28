import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

/// specs/009-device-runtime.md §6.3 — the durable `GeofenceEventQueueStoring` implementation that
/// replaces `InMemoryGeofenceEventQueueStore` for a real device build, behind the *unchanged*
/// `GeofenceEventQueueStoring` protocol. A region-monitoring delegate callback can fire after an
/// app relaunch-from-termination (specs/009 §3.4's relaunch behavior applies identically to region
/// transitions) with **no durable state yet in memory** — this store exists so a detected
/// transition is never lost between that callback and the next successful flush.
///
/// Same durability discipline as `SQLiteFixStore` (see its doc for the full rationale — SQLite over
/// Core Data, one atomic `BEGIN IMMEDIATE...COMMIT` transaction per composite operation, every
/// runtime value bound via `sqlite3_bind_*`/`?`, **never string-interpolated** — I10's review
/// specifically caught and fixed one violation of that rule, so this file follows the exact same
/// bind-only discipline throughout). Simpler than `SQLiteFixStore`: no overflow cap (not specified
/// for events, unlike the fix queue's explicit 1 000 cap, specs/009 §2 — a detected transition MUST
/// NOT be dropped for capacity reasons) and no reject-with-dropped-ids method (001-api-contract.md
/// §7.3 defines no per-event rejection shape).
///
/// Thread-safety: no locking of its own — `GeofenceEventQueue` (its only production caller) is an
/// `actor`, so every call arrives already serialized by Swift concurrency.
public final class SQLiteGeofenceEventQueueStore: GeofenceEventQueueStoring {
    private var db: OpaquePointer?

    public enum StoreError: Error, Equatable {
        case openFailed(String)
        case sqlFailed(String)
    }

    /// - Parameter url: the on-disk file this store persists to. Passing the SAME url across two
    ///   separate `SQLiteGeofenceEventQueueStore` instances (e.g. across a process restart) is what
    ///   makes the in-flight batch identity durable — see this type's top doc.
    public init(url: URL) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite3_open_v2 failed"
            throw StoreError.openFailed(message)
        }
        self.db = handle
        try exec("PRAGMA journal_mode=WAL;")
        try exec("""
        CREATE TABLE IF NOT EXISTS geofence_events (
            seq INTEGER PRIMARY KEY AUTOINCREMENT,
            eventId TEXT NOT NULL UNIQUE,
            geofenceId TEXT NOT NULL,
            transition TEXT NOT NULL,
            recordedAt TEXT NOT NULL,
            batchId TEXT
        );
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_geofence_events_batchId ON geofence_events(batchId);")
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - GeofenceEventQueueStoring

    public func loadAll() -> [GeofenceEventReport] {
        (try? queryEvents(sql: "SELECT * FROM geofence_events ORDER BY seq ASC;")) ?? []
    }

    public func enqueue(_ event: GeofenceEventReport) {
        try? withTransaction {
            try self.insert(event)
        }
    }

    public func currentBatch() -> GeofenceEventBatch? {
        (try? currentBatchLocked()) ?? nil
    }

    public func freezeNextBatch(maxSize: Int, newBatchId: () -> String) -> GeofenceEventBatch? {
        (try? withTransaction { () -> GeofenceEventBatch? in
            if let existing = try self.currentBatchLocked() { return existing }
            let pending = try self.queryEvents(
                sql: "SELECT * FROM geofence_events WHERE batchId IS NULL ORDER BY seq ASC LIMIT ?;",
                bind: { try self.bindInt($0, index: 1, value: max(maxSize, 0)) }
            )
            guard !pending.isEmpty else { return nil }
            let batchId = newBatchId()
            try self.assignBatch(batchId: batchId, eventIds: pending.map(\.eventId))
            return GeofenceEventBatch(batchId: batchId, events: pending)
        }) ?? nil
    }

    public func markSent(batchId: String) {
        try? withTransaction {
            let ids = try self.queryStrings(sql: "SELECT eventId FROM geofence_events WHERE batchId = ?;", bind: { try self.bindText($0, index: 1, value: batchId) })
            guard !ids.isEmpty else { return }
            try self.deleteByIds(ids)
        }
    }

    public func markFailedTransient(batchId: String) {
        // Intentionally a no-op on the pending pool - see the protocol doc.
    }

    public func removeAll() {
        try? exec("DELETE FROM geofence_events;")
    }

    // MARK: - Internals

    private func currentBatchLocked() throws -> GeofenceEventBatch? {
        guard let batchId = try queryStrings(sql: "SELECT DISTINCT batchId FROM geofence_events WHERE batchId IS NOT NULL LIMIT 1;", bind: nil).first else {
            return nil
        }
        let events = try queryEvents(sql: "SELECT * FROM geofence_events WHERE batchId = ? ORDER BY seq ASC;", bind: { try self.bindText($0, index: 1, value: batchId) })
        return GeofenceEventBatch(batchId: batchId, events: events)
    }

    private func insert(_ event: GeofenceEventReport) throws {
        let sql = """
        INSERT INTO geofence_events (eventId, geofenceId, transition, recordedAt, batchId)
        VALUES (?, ?, ?, ?, NULL);
        """
        var statement: OpaquePointer?
        try checked(sqlite3_prepare_v2(db, sql, -1, &statement, nil), context: "prepare insert")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, event.eventId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, event.geofenceId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, event.transition.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 4, event.recordedAt, -1, SQLITE_TRANSIENT)
        try checked(sqlite3_step(statement), context: "step insert", expecting: SQLITE_DONE)
    }

    private func assignBatch(batchId: String, eventIds: [String]) throws {
        let sql = "UPDATE geofence_events SET batchId = ? WHERE eventId = ?;"
        var statement: OpaquePointer?
        try checked(sqlite3_prepare_v2(db, sql, -1, &statement, nil), context: "prepare assignBatch")
        defer { sqlite3_finalize(statement) }
        for eventId in eventIds {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_text(statement, 1, batchId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, eventId, -1, SQLITE_TRANSIENT)
            try checked(sqlite3_step(statement), context: "step assignBatch", expecting: SQLITE_DONE)
        }
    }

    private func deleteByIds(_ eventIds: [String]) throws {
        let sql = "DELETE FROM geofence_events WHERE eventId = ?;"
        var statement: OpaquePointer?
        try checked(sqlite3_prepare_v2(db, sql, -1, &statement, nil), context: "prepare deleteByIds")
        defer { sqlite3_finalize(statement) }
        for eventId in eventIds {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_text(statement, 1, eventId, -1, SQLITE_TRANSIENT)
            try checked(sqlite3_step(statement), context: "step deleteByIds", expecting: SQLITE_DONE)
        }
    }

    private func queryEvents(sql: String, bind: ((OpaquePointer?) throws -> Void)? = nil) throws -> [GeofenceEventReport] {
        var statement: OpaquePointer?
        try checked(sqlite3_prepare_v2(db, sql, -1, &statement, nil), context: "prepare queryEvents")
        defer { sqlite3_finalize(statement) }
        try bind?(statement)
        var results: [GeofenceEventReport] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            try checked(step, context: "step queryEvents", expecting: SQLITE_ROW)
            results.append(readEvent(statement))
        }
        return results
    }

    private func readEvent(_ statement: OpaquePointer?) -> GeofenceEventReport {
        func text(_ index: Int32) -> String { String(cString: sqlite3_column_text(statement, index)) }
        // Column order matches "SELECT * FROM geofence_events": seq, eventId, geofenceId,
        // transition, recordedAt, batchId.
        return GeofenceEventReport(
            eventId: text(1),
            geofenceId: text(2),
            transition: GeofenceTransition(rawValue: text(3)) ?? .enter,
            recordedAt: text(4)
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

    private func bindText(_ statement: OpaquePointer?, index: Int32, value: String) throws {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func bindInt(_ statement: OpaquePointer?, index: Int32, value: Int) throws {
        sqlite3_bind_int(statement, index, Int32(value))
    }

    /// Runs `body` inside `BEGIN IMMEDIATE ... COMMIT` — see `SQLiteFixStore.withTransaction`'s
    /// doc for the full rationale (identical here). Internal (not `private`) so
    /// `SQLiteGeofenceEventQueueStoreTests` can fault-inject a failure directly, mirroring
    /// `SQLiteFixStoreTests`'s rollback test.
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

// See `SQLiteFixStore.swift`'s identical constant for why SQLITE_TRANSIENT is redefined here -
// each file that needs it defines its own file-private copy (matches that file's own precedent).
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
