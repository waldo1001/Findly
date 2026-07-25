import SwiftUI
import FindlyKit

/// specs/004-ios-client.md §1.1 — the thin app target's ONLY job is App-lifecycle wiring. All logic
/// and the design system live in `FindlyKit`. This file must stay this small: scene setup and
/// nothing else.
@main
struct FindlyApp: App {
    // specs/004-ios-client.md §8 — the one shared `AppConfig`, so `AppCoordinator` (deep-link host
    // matching) and `RootView` (share link/QR) agree on the same `joinLinkHost` (specs/007 §1).
    private let config: AppConfig
    @StateObject private var coordinator: AppCoordinator

    init() {
        let config = AppConfig()
        self.config = config
        _coordinator = StateObject(wrappedValue: AppCoordinator(joinLinkHost: config.joinLinkHost))
        // specs/008-privacy-endpoints.md §3.1 rule 2(b) — the one-shot cold-start cleanup: removes
        // any export artifact left behind by a previous process (e.g. killed mid-export, before
        // the next export's own defensive clear or the account-deletion wipe ever ran). `App.init`
        // is guaranteed by SwiftUI to run exactly once per process launch — unlike `RootView`'s
        // init, which SwiftUI may re-invoke as `coordinator` publishes changes — so this is the one
        // place in the app target where "cold start" is unambiguous. A throwaway store instance is
        // fine here: `FileManagerExportArtifactStore.removeCurrentArtifact()` is a directory scan
        // matched by filename pattern, not in-memory state, so it finds exactly what `RootView`'s
        // separately-constructed instance (same default directory) would.
        FileManagerExportArtifactStore().removeCurrentArtifact()
    }

    var body: some Scene {
        WindowGroup {
            RootView(coordinator: coordinator, config: config)
                // specs/004-ios-client.md §3.4/§3.5 — both the `findly://group-join?code=…` deep
                // link and, since specs/007, the `https://{joinLinkHost}/g#CODE` universal link are
                // parsed/validated in FindlyKit (AppCoordinator.handleDeepLink, backed by the pure
                // GroupCodeParsing); this is just the OS-lifecycle forwarding, the one piece of
                // "logic" the app target is allowed (specs/004 §1.1).
                .onOpenURL { url in coordinator.handleDeepLink(url) }
        }
    }
}
