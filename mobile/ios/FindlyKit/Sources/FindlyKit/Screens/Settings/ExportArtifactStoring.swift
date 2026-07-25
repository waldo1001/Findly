import Foundation

/// specs/008-privacy-endpoints.md §3.1 — the export document is the most sensitive payload in the
/// product: one subject's complete movement history to the full retention window, in plaintext, in
/// a single file. A parent may export a **child**. This protocol abstracts its on-disk lifecycle so
/// `DeleteAccountViewModel`'s local wipe (rule 2 — MUST also remove any export artifact) and
/// `ExportScreen` (which creates them for `ShareLink`) share one testable contract — the
/// protocol-abstracts-the-OS-dependency idiom already used by `DeviceIdProviding`/`KeychainStoring`.
public protocol ExportArtifactStoring: AnyObject {
    /// Writes `data` to a fresh, app-private file with an opaque (non-`userId`-derived) name,
    /// first removing any artifact from a previous call (rule 2's "defensively on the next
    /// export"). Returns the file's URL for `ShareLink`. Throws only on a genuine disk failure.
    func write(_ data: Data) throws -> URL
    /// Removes the artifact from the most recent `write(_:)`, if any — a no-op otherwise. Callers
    /// invoke this on share/dismiss, screen teardown, and the account-deletion local wipe (rule 2).
    func removeCurrentArtifact()
}

/// specs/008-privacy-endpoints.md §3.1 rule 3 — the on-disk name MUST NOT embed a stable
/// `userId`/`uid` (a directory listing must not become a roster of who's been exported). Note this
/// intentionally takes NO identifier parameter at all — there is nothing stable to accidentally
/// leak. The user-visible *suggested* name MAY still be friendly (a date is enough).
public enum ExportArtifactNaming {
    public static func fileName(generatedAt: Date = Date(), randomSuffix: String = UUID().uuidString.prefix(8).lowercased()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return "findly-export-\(formatter.string(from: generatedAt))-\(randomSuffix).json"
    }
}

/// In-memory fake — dev/test default; never touches disk, so `swift test` stays hermetic.
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
public final class FileManagerExportArtifactStore: ExportArtifactStoring {
    private let fileManager: FileManager
    private let directory: URL
    private var currentURL: URL?

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
        currentURL = mutableURL
        return mutableURL
    }

    public func removeCurrentArtifact() {
        guard let currentURL else { return }
        try? fileManager.removeItem(at: currentURL)
        self.currentURL = nil
    }
}
