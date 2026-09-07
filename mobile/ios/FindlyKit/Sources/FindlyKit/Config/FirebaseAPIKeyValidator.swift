import Foundation

/// I47 (docs/implementation-handoff.md) — `FirebaseAuthProvider.configureFirebaseIfNeeded()`
/// (app target) calls `FirebaseApp.configure()` with no plist-format validation of its own. A
/// malformed `GoogleService-Info.plist` `API_KEY` raises **inside Firebase itself**
/// (`+[FIRInstallations validateAPIKey:]`) as an uncaught `NSException`, which aborts the process
/// with `SIGABRT` before a single pixel renders — a stack that is entirely Firebase internals and
/// names nothing about the plist. Three consecutive agents (I39, I45, I46) hit exactly this crash
/// against `.github/workflows/ios.yml`'s CI placeholder and misdiagnosed it as a Simulator/
/// automation limitation.
///
/// This type reproduces Firebase's own check in pure, host-agnostic Swift so the app target can
/// run it *before* handing control to `FirebaseApp.configure()`, and fail with a message that
/// names the file and the exact problem instead of an opaque internal crash. Fail-fast on a
/// genuinely broken config is still correct — a broken Firebase config cannot serve requests
/// either way — only the opacity was the defect.
///
/// **The three rules below are copied from the real, linked SDK, not assumed.** Verified against
/// this project's linked firebase-ios-sdk checkout (pinned `.upToNextMajor` from 11.15.0,
/// `mobile/ios/project.yml`), file
/// `FirebaseInstallations/Source/Library/FIRInstallations.m`, method `+validateAPIKey:`:
/// - `kExpectedAPIKeyLength = 39` — the key's `.length` must equal exactly 39.
/// - the key's first character must be `"A"`.
/// - every character must be in `NSCharacterSet.alphanumericCharacterSet` unioned with the two
///   characters `"-"` and `"_"` (the base64 URL-safe alphabet) — Firebase's own comment calls
///   this "base64 url-safe characters", though the check only excludes `+`/`/`/padding, not the
///   full base64 alphabet.
public enum FirebaseAPIKeyValidator {
    /// Mirrors `FIRInstallations.m`'s `kExpectedAPIKeyLength`.
    public static let expectedLength = 39

    private static let allowedCharacters: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-_")
        return set
    }()

    /// Every problem with `apiKey`, in the same spirit as Firebase's own `validationIssues` array
    /// (it collects every issue rather than stopping at the first) — empty when `apiKey` satisfies
    /// the format Firebase itself requires.
    public static func issues(with apiKey: String?) -> [String] {
        guard let apiKey, !apiKey.isEmpty else {
            return ["API_KEY is missing or empty"]
        }

        var issues: [String] = []

        if apiKey.count != expectedLength {
            issues.append("API_KEY length is \(apiKey.count), expected \(expectedLength)")
        }
        if apiKey.first != "A" {
            issues.append("API_KEY must start with \"A\"")
        }
        if apiKey.unicodeScalars.contains(where: { !allowedCharacters.contains($0) }) {
            issues.append("API_KEY contains a character outside letters, digits, \"-\" or \"_\"")
        }

        return issues
    }

    public static func isValid(_ apiKey: String?) -> Bool {
        issues(with: apiKey).isEmpty
    }
}
