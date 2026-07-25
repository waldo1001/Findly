import Foundation

/// Persistence for the offline fix-queue (specs/004-ios-client.md §6). `InMemoryFixStore` is the
/// only implementation shipped in I1; a Core Data/SQLite-backed store that survives process death
/// is a runtime TODO for the on-device build (not required for `swift test`, which exercises
/// `FixQueue`'s rules against this in-memory store).
public protocol FixStoring {
    func loadAll() -> [LocationFix]
    func append(_ fix: LocationFix)
    func remove(fixIds: Set<String>)
}

public final class InMemoryFixStore: FixStoring {
    private var fixes: [LocationFix] = []

    public init() {}

    public func loadAll() -> [LocationFix] { fixes }

    public func append(_ fix: LocationFix) { fixes.append(fix) }

    public func remove(fixIds: Set<String>) {
        fixes.removeAll { fixIds.contains($0.fixId) }
    }
}
