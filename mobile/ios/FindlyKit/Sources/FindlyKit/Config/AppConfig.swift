import Foundation

/// specs/004-ios-client.md §8 — the one place H1-dependent values are injected. No secrets, no
/// real third-party host: the default `baseURL` uses the `.invalid` TLD (RFC 2606), which never
/// resolves, so nothing here can be mistaken for (or accidentally hit) a real backend.
public struct AppConfig: Equatable {
    public var baseURL: URL
    public var authMode: AuthMode
    /// specs/006-phone-auth.md §5 — feeds `StubAuthProvider`'s fake `iss`/`aud` claims in dev mode
    /// (`iss = "https://securetoken.google.com/<firebaseProjectId>"`, `aud = firebaseProjectId`).
    /// A dev default is fine here: H1 supplies the real Firebase project id via the app target's
    /// build configuration, never by editing this default.
    public var firebaseProjectId: String
    /// specs/004-ios-client.md §3.5/§8, specs/007-public-join-links.md §1 — the `JOIN_LINK_HOST`
    /// deployment constant (the public join-link host, `https://{joinLinkHost}/g#CODE`), recorded
    /// at H4 (done 2026-07-22 — see `AppConfig.defaultJoinLinkHost` for the real value) once the
    /// Static Web App was provisioned (docs/azure-setup.md §7). No Xcode app target exists yet
    /// (specs/004 §1.1) to inject this via a real build configuration, so — same as `baseURL`/
    /// `firebaseProjectId` above — this default IS what ships until that scaffolding lands.
    public var joinLinkHost: String

    public init(
        baseURL: URL = AppConfig.placeholderBaseURL,
        authMode: AuthMode = .stubLocal,
        firebaseProjectId: String = "findly-dev",
        joinLinkHost: String = AppConfig.defaultJoinLinkHost
    ) {
        self.baseURL = baseURL
        self.authMode = authMode
        self.firebaseProjectId = firebaseProjectId
        self.joinLinkHost = joinLinkHost
    }

    /// Obviously non-resolving placeholder — H1 supplies the real Azure Functions base URL via
    /// the app target's build configuration, never by editing this default.
    public static let placeholderBaseURL = URL(string: "https://api.findly.invalid/api/v1")!

    /// The real join-link Static Web App hostname (H4, docs/azure-setup.md §7 — `swa-findly`
    /// in resource group Findly, provisioned 2026-07-22). Mirrors Android's equivalent
    /// `joinLinkHost` val in `app/build.gradle.kts` (specs/003 §12.3) — same host, single source of
    /// truth per platform until a custom domain is added later (specs/007 §6).
    public static let defaultJoinLinkHost = "kind-plant-0fb99b003.7.azurestaticapps.net"
}

public enum AuthMode: Equatable {
    /// `StubAuthProvider` — matches the backend's `AUTH_MODE=insecure-local` (specs/001 §2.3).
    case stubLocal
    /// `FirebaseAuthProvider` — H1 follow-up, not implemented in I1 (no Firebase SDK dependency,
    /// no `GoogleService-Info.plist`).
    case firebase
}
