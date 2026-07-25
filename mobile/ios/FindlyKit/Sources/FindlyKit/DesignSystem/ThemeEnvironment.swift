import SwiftUI

/// specs/004-ios-client.md §2.2 — the app target's root view resolves `.light`/`.dark` from the
/// SwiftUI `colorScheme` environment value and sets `\.theme` ONCE at the root; no component below
/// the root ever reads `colorScheme` directly.
private struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: Theme = .light
}

extension EnvironmentValues {
    public var theme: Theme {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}
