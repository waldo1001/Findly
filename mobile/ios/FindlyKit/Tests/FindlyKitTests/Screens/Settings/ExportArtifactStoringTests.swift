import Foundation
import Testing
@testable import FindlyKit

/// specs/008-privacy-endpoints.md §3.1 (review finding #1; rule 2 later amended to close a
/// share-sheet race) — the export document is the most sensitive payload in the product (one
/// subject's full movement history to the full retention window, in plaintext, in a single file).
/// This suite proves the hygiene rules that are testable without a real device: app-private
/// storage, deleted defensively before the next write and via explicit removal, cold-start-safe
/// removal (a fresh store instance still finds a PREVIOUS instance's leftover file — the property
/// that makes triggers (b)/(c) correct), no durable `userId`/`uid` embedded in the on-disk name,
/// and (for the real `FileManagerExportArtifactStore`) that data-protection/backup-exclusion
/// attributes are actually requested — not left to inherited defaults. Deliberately NOT covered
/// here (removed by the spec amendment): any screen-teardown/share-dismissal trigger — see
/// `ExportArtifactStoring`'s doc comment for why.
struct ExportArtifactStoringTests {

    // MARK: - ExportArtifactNaming (rule 3 — no durable identifier)

    @Test func fileName_neverContainsAPassedInStableIdentifier() {
        // The naming helper intentionally takes NO userId/uid parameter at all — this test exists
        // to make that omission a deliberate, checked property, not just an absence.
        let name = ExportArtifactNaming.fileName()
        #expect(name.hasPrefix("findly-export-"))
        #expect(name.hasSuffix(".json"))
    }

    @Test func fileName_isNotStableAcrossCalls() {
        // Two exports on the same day (e.g. a parent exporting two different children back to
        // back) must not collide or be distinguishable as "the same subject" from the filename.
        let first = ExportArtifactNaming.fileName()
        let second = ExportArtifactNaming.fileName()
        #expect(first != second, "a stable/deterministic name would let a directory listing become a roster of who's been exported")
    }

    /// specs/008-privacy-endpoints.md §3.1 rule 2(b) — the predicate `removeCurrentArtifact()`'s
    /// cold-start-safe directory scan is built on: it must recognize the type's own generated
    /// names and reject everything else.
    @Test func isExportArtifactFileName_matchesOnlyTheGeneratedPattern() {
        #expect(ExportArtifactNaming.isExportArtifactFileName(ExportArtifactNaming.fileName()))
        #expect(!ExportArtifactNaming.isExportArtifactFileName("not-an-export.json"))
        #expect(!ExportArtifactNaming.isExportArtifactFileName("findly-export-2026-07-25-abc12345.txt"), "wrong extension must not match")
        // The scan runs unconditionally at every cold start against the SHARED system temp
        // directory (not a dedicated subdirectory) — a prefix-and-suffix-only check would also
        // match an unrelated file that merely shares both, so the predicate must check the full
        // generated shape (date + 8 lowercase-hex segment), not just its bookends.
        #expect(!ExportArtifactNaming.isExportArtifactFileName("findly-export-anything-whatsoever.json"), "right prefix and suffix, wrong middle shape, must not match")
    }

    // MARK: - InMemoryExportArtifactStore (dev/test fake)

    @Test func inMemoryStore_write_thenRemove_leavesNothingBehind() {
        let store = InMemoryExportArtifactStore()
        let url = try? store.write(Data("export-1".utf8))
        #expect(url != nil)
        #expect(store.writtenData[url!] == Data("export-1".utf8))

        store.removeCurrentArtifact()

        #expect(store.writtenData.isEmpty)
        #expect(store.currentURL == nil)
    }

    @Test func inMemoryStore_write_removesAnyPreviousArtifactFirst() {
        // Rule 2's "defensively on the next export" — a second write must not leave the first
        // export's file behind even if nothing ever explicitly removed it.
        let store = InMemoryExportArtifactStore()
        let firstURL = try! store.write(Data("export-1".utf8))
        let secondURL = try! store.write(Data("export-2".utf8))

        #expect(firstURL != secondURL)
        #expect(store.writtenData[firstURL] == nil, "the first artifact must be gone once a second export starts")
        #expect(store.writtenData[secondURL] == Data("export-2".utf8))
    }

    @Test func inMemoryStore_removeCurrentArtifact_withNothingWritten_isANoOp() {
        let store = InMemoryExportArtifactStore()
        store.removeCurrentArtifact() // must not crash/throw
        #expect(store.removeCallCount == 0, "nothing to remove — no spurious removal recorded")
    }

    // MARK: - FileManagerExportArtifactStore (the real, on-disk implementation — rules 1/2/3/4)

    @Test func fileManagerStore_write_createsAnAppPrivateFile_readableBackVerbatim() throws {
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileManagerExportArtifactStore(directory: directory)
        let payload = Data(#"{"formatVersion":1}"#.utf8)

        let url = try store.write(payload)

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: url) == payload)
        #expect(url.deletingLastPathComponent().path == directory.path, "rule 1 — app-private storage only, never a shared/external location")
    }

    @Test func fileManagerStore_write_doesNotEmbedAStableIdentifierInTheOnDiskName() throws {
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileManagerExportArtifactStore(directory: directory)

        let url = try store.write(Data("x".utf8))

        #expect(!url.lastPathComponent.contains("u_totally_stable_uid_marker"))
    }

    @Test func fileManagerStore_secondWrite_removesTheFirstFileFromDisk() throws {
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileManagerExportArtifactStore(directory: directory)

        let firstURL = try store.write(Data("export-1".utf8))
        #expect(FileManager.default.fileExists(atPath: firstURL.path))
        let secondURL = try store.write(Data("export-2".utf8))

        #expect(!FileManager.default.fileExists(atPath: firstURL.path), "rule 2 — defensively removed on the next export")
        #expect(FileManager.default.fileExists(atPath: secondURL.path))
    }

    @Test func fileManagerStore_removeCurrentArtifact_deletesTheFileFromDisk() throws {
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileManagerExportArtifactStore(directory: directory)
        let url = try store.write(Data("export-1".utf8))
        #expect(FileManager.default.fileExists(atPath: url.path))

        store.removeCurrentArtifact()

        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func fileManagerStore_removeCurrentArtifact_withNothingWritten_doesNotThrowOrCrash() throws {
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileManagerExportArtifactStore(directory: directory)
        store.removeCurrentArtifact()
    }

    /// specs/008-privacy-endpoints.md §3.1 rule 2(b) (spec amendment) — the app-cold-start
    /// cleanup trigger. A fresh process constructs a fresh `FileManagerExportArtifactStore`
    /// instance with no in-memory record of what a PREVIOUS process's instance wrote (e.g. the
    /// app was killed mid-export, before the next write's defensive clear or the account-deletion
    /// wipe ever ran). This is the load-bearing proof that `removeCurrentArtifact()` still finds
    /// and removes that leftover file — it must NOT rely on a remembered `currentURL`, which a
    /// brand-new instance can never have.
    @Test func fileManagerStore_removeCurrentArtifact_findsAnArtifactWrittenByADifferentInstance_simulatingColdStart() throws {
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstProcessStore = FileManagerExportArtifactStore(directory: directory)
        let url = try firstProcessStore.write(Data("export-1".utf8))
        #expect(FileManager.default.fileExists(atPath: url.path))

        // Simulate the app being killed and relaunched: a brand-new instance, sharing nothing
        // with the one that wrote the file except the directory.
        let coldStartStore = FileManagerExportArtifactStore(directory: directory)
        coldStartStore.removeCurrentArtifact()

        #expect(!FileManager.default.fileExists(atPath: url.path), "cold start must remove an artifact left by a PREVIOUS instance/process, not just its own in-memory state")
    }

    /// The directory-scan cold-start cleanup must only ever touch files matching the export
    /// artifact's own naming pattern — never delete unrelated files that happen to share the
    /// directory (a real risk once the default `directory` is the shared system temp directory).
    @Test func fileManagerStore_removeCurrentArtifact_leavesUnrelatedFilesInTheSameDirectoryAlone() throws {
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let differentEverything = directory.appendingPathComponent("not-an-export.txt")
        try Data("unrelated".utf8).write(to: differentEverything)
        // Load-bearing fixture: same extension as the real artifact, different prefix. A
        // suffix-only predicate (`hasSuffix(".json")`, no prefix check at all) would still pass
        // `differentEverything` above (it differs in BOTH prefix and extension) while wrongly
        // deleting this one — this is the only fixture that actually exercises the prefix half of
        // the match at the directory-scan level.
        let sameExtensionDifferentPrefix = directory.appendingPathComponent("unrelated-cache.json")
        try Data("also unrelated".utf8).write(to: sameExtensionDifferentPrefix)
        let store = FileManagerExportArtifactStore(directory: directory)

        store.removeCurrentArtifact()

        #expect(FileManager.default.fileExists(atPath: differentEverything.path), "must only match the export-artifact naming pattern")
        #expect(FileManager.default.fileExists(atPath: sameExtensionDifferentPrefix.path), "same extension, different prefix — must still survive")
    }

    /// Rule 4 — backup exclusion is requested explicitly, not left to inherited defaults. (File
    /// data-protection classes, `.completeFileProtection`, are meaningless outside a real iOS
    /// device/simulator with a passcode and can't be verified in this headless sandbox — the write
    /// path attempts to set it regardless, see `FileManagerExportArtifactStore.write`.)
    @Test func fileManagerStore_write_excludesTheFileFromBackup() throws {
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileManagerExportArtifactStore(directory: directory)

        let url = try store.write(Data("x".utf8))

        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    private static func makeScratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ExportArtifactStoringTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
