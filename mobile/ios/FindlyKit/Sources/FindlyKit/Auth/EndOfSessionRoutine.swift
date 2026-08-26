import Foundation

/// specs/008-privacy-endpoints.md §3.1/§4.4, specs/009-device-runtime.md §9 (I43) — the ONE shared
/// end-of-session routine every path that ends a signed-in session on this device MUST call, so a
/// fourth path can never again re-derive its own, incomplete call list.
///
/// **Why this exists.** Before this fix, `FindlyApp.swift`'s forced `onSignedOut` closure (a second
/// `AUTH_TOKEN_EXPIRED`, specs/009 §9) called only `authProvider.signOut()` +
/// `LocationRuntimeContainer.wipeLocalState()` — a strict SUBSET of what
/// `DeleteAccountViewModel`'s account-deletion completion already called
/// (`deviceIdProvider.clearDeviceId`, `appVersionTracker.clearLastRegisteredAppVersion`,
/// `exportArtifactStore.removeCurrentArtifact`, `authProvider.clearStoredSession`). Three of those
/// four are harmless to have skipped: `deviceIdProvider`/`appVersionTracker` are keyed per-uid, so a
/// DIFFERENT user signing in next never reads the stale entry, and the Keychain-backed
/// `verificationID` is an opaque OTP-step handle `signOut()`'s own teardown already makes moot. The
/// fourth is not — `exportArtifactStore` holds a PLAINTEXT COPY of the signed-out user's own
/// exported data (008 §3), on a device that had just forced them out. Nothing else clears it before
/// the next cold start (008 §3.1 rule 2b) or the next export's own defensive pre-write clear, so a
/// DIFFERENT user signing in on the same device — without a relaunch, without exporting anything
/// themselves — could reach it in that window.
///
/// Every real dependency below is a `FindlyKit` protocol; `wipeLocalState` is a plain closure, not
/// `LocationRuntimeContainer` itself — matching the convention `DeleteAccountViewModel` already
/// established (I11), so this type never needs a live `CLLocationManager`/SQLite stack to test and
/// a future test double never has to fake one out.
///
/// `currentUserId` and `authProvider` are read by the CALLER, before this function runs — every
/// `AuthProviding.signOut()` implementation clears `currentUserId` as part of its own contract (see
/// `FirebaseAuthProvider`/`StubAuthProvider`), so a caller that captured the uid any later than
/// "before calling this function" would always observe `nil` and silently skip the uid-keyed
/// clears. `authProvider` is `Optional` (unlike every other parameter) only so a caller with a
/// `weak` reference to it — `FindlyApp.swift`'s forced `onSignedOut` closure captures
/// `[weak authProvider]`, matching its pre-existing style — can still run the local wipe even if
/// that reference has already gone: the local wipe must never depend on auth state being
/// available.
@MainActor
public enum EndOfSessionRoutine {
    /// The two axes every existing session-ending path disagrees on, isolated here as named,
    /// documented booleans rather than each call site copy-pasting its own subset of the four
    /// calls. Every `false` below is a DELIBERATE, reviewed exception — not an oversight; a new
    /// call site that wants to set either MUST justify it in a comment at that call site, the way
    /// the two existing exceptions already do.
    public struct Options {
        /// `false` only for `DeleteAccountViewModel.signOutForRetry()` (I25 review): the backend
        /// account is already gone, but a SAME-uid sign-in is the very next expected step (the user
        /// retries the delete from `.firebaseDeleteFailed`) — `deviceIdProvider`/
        /// `exportArtifactStore` are plain values whose stale read under that same uid is harmless
        /// (a stale deviceId just re-registers under the same UUID; a stale export artifact just
        /// gets overwritten), so clearing them is deferred to the point the deletion is actually
        /// confirmed complete (`wipeLocalStateAndComplete()`). Every other path defaults this
        /// `true`.
        public var clearsDeviceIdentityAndExportArtifact: Bool
        /// `false` only for `RootView.clearSessionOnConfirmedAuthFailure()` (A37 review, Finding
        /// 4): `clearStoredSession()` clears just the Keychain-backed phone-verification (OTP) id,
        /// a leftover of the SMS step already made moot by `signOut()`'s own teardown — not this
        /// path's territory. Every other path defaults this `true`.
        public var clearsStoredSession: Bool

        public init(clearsDeviceIdentityAndExportArtifact: Bool = true, clearsStoredSession: Bool = true) {
            self.clearsDeviceIdentityAndExportArtifact = clearsDeviceIdentityAndExportArtifact
            self.clearsStoredSession = clearsStoredSession
        }
    }

    /// `appVersionTracker` is cleared unconditionally whenever `currentUserId` is known — unlike
    /// `deviceIdProvider`/`exportArtifactStore`, it is not a plain value: it GATES CONTROL FLOW
    /// (`DeviceRegistrationService.registerOnLaunchIfNeeded()` no-ops entirely once the stored
    /// version already matches the running app version), so no existing path defers clearing it —
    /// see `Options.clearsDeviceIdentityAndExportArtifact`'s doc for the full I25 rationale.
    public static func run(
        currentUserId: String?,
        authProvider: AuthProviding?,
        deviceIdProvider: DeviceIdProviding,
        appVersionTracker: AppVersionRegistrationTracking,
        exportArtifactStore: ExportArtifactStoring,
        wipeLocalState: () async -> Void,
        options: Options = Options()
    ) async {
        if let uid = currentUserId {
            appVersionTracker.clearLastRegisteredAppVersion(forUserId: uid)
            if options.clearsDeviceIdentityAndExportArtifact {
                deviceIdProvider.clearDeviceId(forUserId: uid)
            }
        }
        if options.clearsDeviceIdentityAndExportArtifact {
            // specs/008-privacy-endpoints.md §3.1 rule 2 / §4.4, specs/009 §9 (I43) — the plaintext
            // export artifact must not outlive the session it was written for.
            exportArtifactStore.removeCurrentArtifact()
        }
        // Independent of every clear above — no data dependency in either direction (A37 review,
        // Finding 3), so this may run in any position relative to them; kept here so the local wipe
        // always happens even when `authProvider` is `nil` and every step below is skipped.
        await wipeLocalState()
        if options.clearsStoredSession {
            authProvider?.clearStoredSession()
        }
        try? authProvider?.signOut()
    }
}
