import Foundation

/// specs/008-privacy-endpoints.md §3.1 — the export document is the most sensitive payload in the
/// product: one subject's complete movement history to the full retention window, in plaintext, in
/// a single file. A parent may export a **child**. This protocol abstracts its on-disk lifecycle so
/// `DeleteAccountViewModel`'s local wipe (rule 2c — MUST also remove any export artifact) and
/// `ExportScreen` (which creates them for `ShareLink`) share one testable contract — the
/// protocol-abstracts-the-OS-dependency idiom already used by `DeviceIdProviding`/`KeychainStoring`.
///
/// **Permitted removal triggers ONLY (rule 2, amended):** (a) immediately before writing a new
/// export, so at most one artifact ever exists; (b) once at app cold start, so an artifact never
/// survives a process restart; (c) the account-deletion local wipe. Screen-level triggers (share
/// completion, dismissal, `onDisappear`) are deliberately NOT among them: the OS share sheet hands
/// the file's URL to another app, which may read it lazily/asynchronously — clearing on those
/// signals races that consumer and can delete the file out from under a "Save to Files"-style
/// target while it's still reading. Screen teardown MAY clear it only where the platform guarantees
/// the consumer already copied the data; iOS's `ShareLink` gives no such guarantee, so this codebase
/// never calls a removal from `ExportScreen`.
public protocol ExportArtifactStoring: AnyObject {
    /// Writes `data` to a fresh, app-private file with an opaque (non-`userId`-derived) name,
    /// first removing any artifact from a previous call (trigger (a) — "immediately before writing
    /// a new export"). Returns the file's URL for `ShareLink`. Throws only on a genuine disk
    /// failure.
    func write(_ data: Data) throws -> URL
    /// Removes any live export artifact, if one exists — a no-op otherwise. Callers invoke this
    /// before every `write(_:)` (trigger a), once at app cold start (trigger b — see
    /// `FileManagerExportArtifactStore`'s doc comment for why this must NOT rely on in-memory
    /// state), and from the account-deletion local wipe (trigger c). Deliberately NOT called from
    /// `ExportScreen` on share completion/dismissal/teardown — see the protocol's doc comment.
    func removeCurrentArtifact()
}

/// specs/008-privacy-endpoints.md §3.1 rule 3 — the on-disk name MUST NOT embed a stable
/// `userId`/`uid` (a directory listing must not become a roster of who's been exported). Note this
/// intentionally takes NO identifier parameter at all — there is nothing stable to accidentally
/// leak. The user-visible *suggested* name MAY still be friendly (a date is enough).
public enum ExportArtifactNaming {
    private static let prefix = "findly-export-"
    private static let suffix = ".json"

    public static func fileName(generatedAt: Date = Date(), randomSuffix: String = UUID().uuidString.prefix(8).lowercased()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return "\(prefix)\(formatter.string(from: generatedAt))-\(randomSuffix)\(suffix)"
    }

    /// specs/008-privacy-endpoints.md §3.1 rule 2(b) — whether `fileName` matches the FULL shape
    /// this type generates (`findly-export-<yyyy>-<MM>-<dd>-<8 lowercase hex>.json`), not merely
    /// its prefix/suffix. `FileManagerExportArtifactStore`'s cold-start cleanup runs
    /// UNCONDITIONALLY at every app launch against `directory`, which by default is the SHARED
    /// system temp directory, not a dedicated subdirectory — so this predicate is deliberately as
    /// narrow as the exact thing `fileName` generates, not merely "looks export-shaped." A looser
    /// prefix-and-suffix-only check would also match e.g. `findly-export-notes.json`, an unrelated
    /// file that happens to share both. `ExportArtifactNaming` stays the one place that both
    /// generates and recognises the name, so the two cannot drift apart.
    public static func isExportArtifactFileName(_ fileName: String) -> Bool {
        // findly-export- + yyyy + - + MM + - + dd + - + 8 lowercase hex chars + .json
        let pattern = "^\(NSRegularExpression.escapedPattern(for: prefix))"
            + "\\d{4}-\\d{2}-\\d{2}-[0-9a-f]{8}"
            + "\(NSRegularExpression.escapedPattern(for: suffix))$"
        return fileName.range(of: pattern, options: .regularExpression) != nil
    }
}

/// In-memory fake — dev/test default; never touches disk, so `swift test` stays hermetic. A
/// single-slot, in-process store: there is no cross-process "cold start" concept for it (a test's
/// process ends when the test does), so `removeCurrentArtifact()` tracking `currentURL` in memory
/// is sufficient here — unlike `FileManagerExportArtifactStore`, see its doc comment.
public final class InMemoryExportArtifactStore: ExportArtifactStoring {
    public private(set) var writtenData: [URL: Data] = [:]
    public private(set) var currentURL: URL?
    public private(set) var removeCallCount = 0

    public init() {}

    public func write(_ data: Data) throws -> URL {
        removeCurrentArtifact()
        let url = URL(fileURLWithPath: "/dev/null/fake-export-\(UUID().uuidString).json")
        writtenData[url] = data
        currentURL = url
        return url
    }

    public func removeCurrentArtifact() {
        guard let currentURL else { return }
        writtenData[currentURL] = nil
        removeCallCount += 1
        self.currentURL = nil
    }
}

/// The real device implementation — writes into an app-private directory (rule 1; `directory`
/// defaults to `FileManager.default.temporaryDirectory`, itself inside the app sandbox, never
/// external/shared storage), sets `.completeFileProtection` and backup exclusion explicitly (rule
/// 4, not inherited defaults), and names the file with no durable `userId` (rule 3, via
/// `ExportArtifactNaming`). Both attribute-setting calls are best-effort (`try?`): a failure there
/// must not block the export the user actually asked for, and there is nothing more restrictive to
/// fall back to short of not writing the file at all.
///
/// `removeCurrentArtifact()` deliberately does NOT track "the current artifact" as an in-memory
/// `currentURL` ivar — it scans `directory` and removes every file matching
/// `ExportArtifactNaming.isExportArtifactFileName`. This is required for trigger (b), the app
/// cold-start cleanup (rule 2): a fresh process constructs a fresh store instance with no memory
/// of what a PREVIOUS process wrote, so instance-state tracking would make that instance's very
/// first `removeCurrentArtifact()` call a silent no-op against a real leftover file (e.g. the app
/// was killed mid-export, before the next write's defensive clear or the account-deletion wipe
/// ever ran) — exactly the durability gap rule 2(b) exists to close. Filtering by name (not
/// deleting indiscriminately) also means this is safe to point at a directory shared with other,
/// unrelated temp files. At most one artifact should ever exist on disk at a time (rule 2a), so
/// "remove every match" and "remove the one current artifact" are the same operation — this also
/// makes the method idempotent and safe to call from multiple independent triggers/instances
/// without coordination.
public final class FileManagerExportArtifactStore: ExportArtifactStoring {
    private let fileManager: FileManager
    private let directory: URL

    public init(fileManager: FileManager = .default, directory: URL? = nil) {
        self.fileManager = fileManager
        self.directory = directory ?? fileManager.temporaryDirectory
    }

    public func write(_ data: Data) throws -> URL {
        removeCurrentArtifact()
        let url = directory.appendingPathComponent(ExportArtifactNaming.fileName())
        try data.write(to: url, options: .atomic)
        try? fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        var mutableURL = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? mutableURL.setResourceValues(resourceValues)
        return mutableURL
    }

    public func removeCurrentArtifact() {
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in contents where ExportArtifactNaming.isExportArtifactFileName(url.lastPathComponent) {
            try? fileManager.removeItem(at: url)
        }
    }
}
