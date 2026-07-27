# Findly — iOS app (Swift)

**I1 (foundation) + I2 (feature screens) + I3 (phone sign-in) + I7 (Keychain hardening) + I8 (privacy: export/delete) + I9 (Xcode app-target project) implemented.** Normative design: [`specs/004-ios-client.md`](../../specs/004-ios-client.md) — read that first; it owns the architecture, the design-system token contract, the full 001 endpoint mapping, auth/token-refresh, the fix-queue model, and the location/push strategy (000 §O1). Phone sign-in is normative in [`specs/006-phone-auth.md`](../../specs/006-phone-auth.md) (004 §4 owns only the iOS shapes). Wire contract: [`specs/001-api-contract.md`](../../specs/001-api-contract.md). Product context: [`specs/000-overview.md`](../../specs/000-overview.md), esp. open items **O1–O4, O9**.

## What's here

```
mobile/ios/
├── FindlyKit/         ← Swift Package — ALL logic + the design system. Builds & tests headlessly:
│   │                    `cd FindlyKit && swift build && swift test`
│   ├── Sources/FindlyKit/   Config, Networking (full 001 client, 19 endpoints), Auth (phone-only
│   │                       sign-in: AuthProviding, PhoneAuthError, PhoneNumberNormalizer,
│   │                       StubAuthProvider — specs/006), Device, Locations (offline fix-queue),
│   │                       LocationSensing, Push, DesignSystem (tokens/theme/11 components),
│   │                       Navigation, Screens/ — two-step phone sign-in (I3) + Home, Map (live
│   │                       map + swappable MapKit/list `MapRendering`), History (cursor
│   │                       pagination), Geofences (list/editor, ETag-aware save + version-conflict
│   │                       merge UX), Locate (create + poll-to-terminal), Settings (device +
│   │                       family members), Invites (create + accept, with deep-link
│   │                       validation) — all I2 except sign-in; `Auth/KeychainStoring.swift` (I7) —
│   │                       the protocol + in-memory fake for the Keychain-backed storage
│   │                       `FirebaseAuthProvider` uses for its verification session id
│   └── Tests/FindlyKitTests/   Swift Testing suite (see specs/004 §9 for why not XCTest here)
└── Findly/      ← Thin SwiftUI app-target SOURCE FILES (App lifecycle + composition root
                         wiring), wrapped by the committed `Findly.xcodeproj` (I9, see below). Two
                         spec-sanctioned exceptions to "zero business logic" here (004 §1.1's
                         general rule): `Auth/FirebaseAuthProvider.swift` — the real `AuthProviding`
                         implementation, kept out of `FindlyKit` specifically so the package stays
                         Firebase-SDK-free and `swift test` keeps running headless (004 §4.1). It
                         compiles to an inert `#else` fallback today (no Firebase SPM dependency
                         wired into the project yet); real on-device verification additionally
                         depends on H2 (Firebase console phone-auth setup) and is expected to stay
                         untestable locally until both land. `Auth/KeychainStore.swift` (I7) — the
                         real `KeychainStoring` implementation (`Security` framework
                         generic-password items), kept out of `FindlyKit` for the same reason:
                         Keychain access doesn't behave deterministically in a headless `swift test`
                         sandbox. Also holds `Assets.xcassets/AppIcon.appiconset` (I9 — the
                         light/dark/tinted app icon, `design/findly-icon/`).
```

**I9** creates `Findly.xcodeproj` (specs/004 §1.1) — the piece 004 §1.1 explicitly deferred until a
session had real Xcode to validate the result: hand-authoring a `project.pbxproj` was judged worse
than no project file at all. Generated from a declarative `project.yml` via
[xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) rather than by hand or
via the Xcode GUI (no GUI automation available in this session) — reproducible, diffable, and
validated for real with `xcodebuild` on this session's Xcode 26.6 install. `project.yml` (repo
root of `mobile/ios/`) is the source of truth; regenerate with `xcodegen generate` after editing it,
never hand-edit `project.pbxproj`. Targets iOS 16 (matching `FindlyKit`'s `Package.swift`), bundle
id `com.findly.ios`, automatic code signing with no team wired in yet (H5/H6 own real
signing/provisioning — `DEVELOPMENT_TEAM` is commented out in `project.yml` with the real Team ID,
`92A2K3Q7NH`, noted for when it's needed). `FindlyKit` is linked in as a local Swift Package
dependency (relative path from the project). Zero business logic was added to the app target — this
task only wraps the existing, already-reviewed `Findly/` source files in a build harness. One
necessary, minimal fix surfaced by wrapping `Info.plist` in a *real* build for the first time (vs.
the loose `swiftc -typecheck` check the README previously described): it was missing
`CFBundleExecutable`/`CFBundleIdentifier`/`CFBundlePackageType` — `xcodebuild build` doesn't
validate these, but `simctl install` (and a real device install) fails outright with "Missing
bundle ID" without them. Added as the standard Xcode-template build-setting substitutions
(`$(EXECUTABLE_NAME)`/`$(PRODUCT_BUNDLE_IDENTIFIER)`/`$(PRODUCT_BUNDLE_PACKAGE_TYPE)`), not
hardcoded values — plist plumbing, not business logic.

**I2** adds the feature screens on top of I1's foundation: live map (§5.2), history (§5.3),
geofences list/editor (§7.1–7.2), locate-to-request (§6), device/family settings
(§4.2–4.3/§3.5–3.6), invites (§3.3–3.4) — same design system, no changes to `DesignSystem/Tokens`
or `Theme`; two new stateless components (`FindlyTextField`, `FindlyToggleRow`) were added to
`DesignSystem/Components/` for the new forms.

**I3** replaces the I1 proof-of-concept sign-in screen with phone-number-only sign-in (specs/006):
`SignInViewModel`/`SignInScreen` implement the two-step (phone entry → code entry) state machine;
`PhoneNumberNormalizer` implements the E.164 normalization rules; `StubAuthProvider` is now
phone-shaped and emits a **real** unsigned JWT (previously a non-parseable stub shape — see "Auth"
below); `FirebaseAuthProvider` (app target) is the real implementation, wired in at the `RootView`
seam via `AppConfig.authMode`.

## Build & test

```bash
cd FindlyKit
swift build          # the package — logic + design system
swift build --build-tests   # also compiles the test target
swift test            # runs the Swift Testing suite (needs a host where Testing.framework
                       # actually executes tests — see specs/004 §9 for a documented gap on
                       # Command-Line-Tools-only hosts, worked around in this session via an
                       # out-of-tree harness; unaffected on a normal Xcode/CI machine)
```

**Known flaky crash (found I9, not fixed — out of I9's scope):** on a real Xcode host, `swift test`
intermittently aborts with `freed pointer was not the last allocation` (SIGABRT) partway through the
suite — reproduced across multiple runs, unrelated to `Findly.xcodeproj`/the app target (reproduces
in an isolated copy of `FindlyKit/` alone). First suspect was `Networking/MockURLProtocol.swift`'s
shared `static var requestHandler` — **ruled out**: `swift test --skip RequestBuildingTests` (the
only file touching it) still crashed with zero MockURLProtocol-related tests in the run. Most likely
remaining cause: several shared `static let DateFormatter`/`ISO8601DateFormatter` instances
(`Screens/Groups/GroupModels.swift`, `CreateGroupViewModel.swift`, `GroupDetailViewModel.swift`,
`Screens/History/HistoryViewModel.swift`, `HistoryScreen.swift`) — classically not safe for
concurrent use even as a `let`, and Swift Testing runs different ViewModel test suites concurrently
by default. Not yet confirmed (needs a bisection), not fixed here (`do not touch FindlyKit/` was
this task's explicit scope) — flagged as a follow-up task.

The app target builds with the committed `Findly.xcodeproj` (I9):

```bash
xcodebuild -list -project Findly.xcodeproj                                              # sanity check
xcodebuild build -project Findly.xcodeproj -scheme Findly -destination 'generic/platform=iOS Simulator'
```

Verified (I9, this session, real Xcode 26.6 + a real iOS 26.5 Simulator runtime): both the generic
destination build above and a concrete `-destination 'platform=iOS Simulator,name=iPhone 17'` build
succeed; the resulting `Findly.app` installs and launches cleanly via `simctl install`/`simctl
launch` on a booted simulator, rendering the real sign-in screen (design-system styling, `+32`
phone-country default) and the real home-screen app icon.

Regenerating the project (after editing `project.yml`): `xcodegen generate` (`brew install
xcodegen` if needed). CI: `.github/workflows/ios.yml`'s `ios-build` job now runs a real
`xcodebuild build` on `macos-14` (archive + real signing is still a TODO — requires the Apple
Developer secrets H6 is provisioning).

## Key decisions (see specs/004 for the full normative text)

- **Location sync:** `CLLocationManager` with Always authorization (staged onboarding: When-In-Use → Always upgrade prompt); background fixes via significant-change monitoring + `BGAppRefreshTask` opportunistic scheduling — scaffolded behind `LocationProviding`/`BackgroundSyncScheduling`, real on-device wiring is a runtime TODO (needs a device/simulator this session doesn't have). iOS does not honor exact periodic intervals — the interval is a *target*; the UI (I2) must document the delivered cadence honestly.
- **Push-to-locate (000 §O1 — the #1 platform risk):** correct mechanism is the **Location Push Service Extension** (`com.apple.developer.location.push`, `apns-push-type: location`) — **apply to Apple for this entitlement immediately** (human/Apple-account action, not blocking). Until granted, the backend's data-only `LOCATE_REQUEST` push is used exactly as normatively specified; UI (I2) falls back to "last known, updating…". `LocationPushTokenHandling` scaffolds the token capture/registration path so wiring the extension in later is additive only.
- **Geofencing:** `CLCircularRegion` monitoring (max 20 regions — `features.limits.maxGeofences`, 000 §O9) is an I2 concern; `FindlyKit`'s geofences client methods exist now.
- **Push tokens:** FCM/APNs token registered via `PushTokenProviding` → `DeviceRegistrationService`, re-`POST /devices` on every refresh (001 §4.1, 000 §O4).
- **Auth (phone-only sign-in, specs/006):** `AuthProviding` gains `startPhoneVerification(phoneNumberE164:)`/`confirmCode(_:)` and the closed `PhoneAuthError` set (006 §4.2). `StubAuthProvider` implements the two-step dev shape (006 §5) and now emits a **real** unsigned JWT — base64url JSON header/payload with an empty signature, parseable by the backend's `AUTH_MODE=insecure-local` verifier; the previous `"stub-header.…"` shape was not valid base64url JSON and never actually worked against a local backend. `SignInViewModel`/`SignInScreen` implement the 006 §4.1 state machine (phone entry → code entry, 30 s resend cooldown via an injected virtual-time-testable sleep). `FirebaseAuthProvider` (app target) is the real implementation, wired in at the `RootView` seam via `AppConfig.authMode`/`firebaseProjectId` — it compiles to an inert fallback until the Firebase SDK dependency + `GoogleService-Info.plist` land (H1) and Firebase console phone-auth setup is done (H2).
- **Offline:** `FixQueue` (actor) — freeze-on-first-send `batchId` idempotency, in-memory queue today (Core Data/SQLite persistence is a runtime TODO), batch upload per 001 §5.1.
- **I7 hardening (Keychain, not UserDefaults):** `FirebaseAuthProvider`'s `verificationID` — previously plaintext in `UserDefaults` (flagged non-blocking in I3's security review) — now lives behind `KeychainStoring` (`FindlyKit`, protocol + `InMemoryKeychainStore` fake) with a real `Security`-framework `KeychainStore` (app target, generic-password item, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). Storage-mechanism swap only; the verify/confirm lifecycle is unchanged.
- **I8 privacy (export/delete account/delete family, specs/004 §3.6, specs/008):** `Screens/Settings/` gains a hub (`PrivacySettingsScreen`, reachable unconditionally from Home — a store requirement, 008 §4.4) plus `ExportScreen`/`DeleteAccountScreen`/`DeleteFamilyScreen`. `FindlyAPIClient` gains `exportData(userId:)` (raw `Data`, the one unenveloped success response in the API, via a new `URLSessionAPIClient.sendRawData`), `deleteAccount()`, `deleteFamily()` (both bare-204). `AuthProviding` gains `deleteCurrentUser()` — the 008 §1.3 seam FindlyKit calls after `DELETE /users/me` returns 204; `FirebaseAuthProvider` (app target) implements it as `Auth.auth().currentUser?.delete()`, kept out of FindlyKit like the rest of the real Firebase surface. `DeleteAccountViewModel` derives the 008 §4.2 cascade-warning wording from the caller's own role/roster (last parent or sole member), orders backend-then-Firebase-then-local-wipe (`FixQueue.clearAll()` + `DeviceIdProviding.clearDeviceId` + `signOut()` for the Keychain entry), and offers a Firebase-step-only retry on failure. `DeleteFamilyScreen` layers a typed-family-name gate on top of the standard `.confirmationDialog` two-step (008 §5.4's recommended UX).
