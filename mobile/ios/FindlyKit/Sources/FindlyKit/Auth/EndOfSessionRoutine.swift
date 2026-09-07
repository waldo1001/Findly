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
    /// One remaining axis, isolated here as a named, documented boolean rather than each call site
    /// copy-pasting its own subset of the calls. `false` below is a DELIBERATE, reviewed exception —
    /// not an oversight; a new call site that wants to set it MUST justify that in a comment at that
    /// call site, the way the existing exception already does.
    ///
    /// **(I45b) This struct used to carry a second axis,
    /// `clearsDeviceIdentityAndExportArtifact`, gating `deviceIdProvider.clearDeviceId` and
    /// `exportArtifactStore.removeCurrentArtifact`.** I25 introduced `false` for
    /// `DeleteAccountViewModel.signOutForRetry()` on the assumption that a SAME-uid sign-in was
    /// always the very next step after a failed delete, so a stale device id/export read under that
    /// uid would be harmless. I44 found that assumption unenforced — a DIFFERENT person could reach
    /// sign-in from `.signedOutForRetry` first, in which case the previous user's plaintext export
    /// (008 §3) and device id would still be on disk, the identical window I43 closed on the
    /// forced-sign-out path — and switched `signOutForRetry()` to clear unconditionally, leaving
    /// zero callers of `false`. I45b removed the axis entirely rather than leave a single-value
    /// option for the next reader to re-verify: `deviceIdProvider.clearDeviceId` and
    /// `exportArtifactStore.removeCurrentArtifact` now always run, same as `appVersionTracker`
    /// below. A future call site that needs to defer either clear again should re-introduce the
    /// axis with a fresh, current justification — not resurrect this one from history.
    public struct Options {
        /// `false` only for `RootView.clearSessionOnConfirmedAuthFailure()` (A37 review, Finding
        /// 4): `clearStoredSession()` clears just the Keychain-backed phone-verification (OTP) id,
        /// a leftover of the SMS step already made moot by `signOut()`'s own teardown — not this
        /// path's territory. Every other path defaults this `true`.
        public var clearsStoredSession: Bool

        public init(clearsStoredSession: Bool = true) {
            self.clearsStoredSession = clearsStoredSession
        }
    }

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
            deviceIdProvider.clearDeviceId(forUserId: uid)
        }
        // specs/008-privacy-endpoints.md §3.1 rule 2 / §4.4, specs/009 §9 (I43) — the plaintext
        // export artifact must not outlive the session it was written for. Unconditional as of
        // I45b — no call site has deferred this since I44.
        exportArtifactStore.removeCurrentArtifact()
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
