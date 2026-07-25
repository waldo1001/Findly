# Findly — iOS app (Swift)

**I1 (foundation) + I2 (feature screens) + I3 (phone sign-in) + I7 (Keychain hardening) + I8 (privacy: export/delete) implemented.** Normative design: [`specs/004-ios-client.md`](../../specs/004-ios-client.md) — read that first; it owns the architecture, the design-system token contract, the full 001 endpoint mapping, auth/token-refresh, the fix-queue model, and the location/push strategy (000 §O1). Phone sign-in is normative in [`specs/006-phone-auth.md`](../../specs/006-phone-auth.md) (004 §4 owns only the iOS shapes). Wire contract: [`specs/001-api-contract.md`](../../specs/001-api-contract.md). Product context: [`specs/000-overview.md`](../../specs/000-overview.md), esp. open items **O1–O4, O9**.

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
                         wiring). No `.xcodeproj` is committed yet — see specs/004 §1.1 for why and
                         how to create one. Two spec-sanctioned exceptions to "zero business logic"
                         here (004 §1.1's general rule): `Auth/FirebaseAuthProvider.swift` — the
                         real `AuthProviding` implementation, kept out of `FindlyKit` specifically so
                         the package stays Firebase-SDK-free and `swift test` keeps running
                         headless (004 §4.1). It compiles to an inert `#else` fallback today (no
                         Firebase SPM dependency or `.xcodeproj` exists yet); real on-device
                         verification additionally depends on H2 (Firebase console phone-auth
                         setup) and is expected to stay untestable locally until both land.
                         `Auth/KeychainStore.swift` (I7) — the real `KeychainStoring`
                         implementation (`Security` framework generic-password items), kept out of
                         `FindlyKit` for the same reason: Keychain access doesn't behave
                         deterministically in a headless `swift test` sandbox.
```

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

The `Findly/` app-target sources type-check against the built `FindlyKit` module
(`swiftc -typecheck -I FindlyKit/.build/.../Modules -L FindlyKit/.build/... FindlyApp.swift RootView.swift Auth/FirebaseAuthProvider.swift Auth/KeychainStore.swift`)
but are not wrapped in an Xcode project yet — do that in Xcode (File → New → Project → App,
point sources at this folder, add `FindlyKit` as a local Swift Package dependency), then build with
Xcode 16+ / `xcodebuild`. CI: `.github/workflows/ios.yml` (currently a structure check; real
`xcodebuild` + signing steps are stubbed there as TODO — requires Apple Developer account, $99/yr,
and blocks on the `.xcodeproj` existing).

## Key decisions (see specs/004 for the full normative text)

- **Location sync:** `CLLocationManager` with Always authorization (staged onboarding: When-In-Use → Always upgrade prompt); background fixes via significant-change monitoring + `BGAppRefreshTask` opportunistic scheduling — scaffolded behind `LocationProviding`/`BackgroundSyncScheduling`, real on-device wiring is a runtime TODO (needs a device/simulator this session doesn't have). iOS does not honor exact periodic intervals — the interval is a *target*; the UI (I2) must document the delivered cadence honestly.
- **Push-to-locate (000 §O1 — the #1 platform risk):** correct mechanism is the **Location Push Service Extension** (`com.apple.developer.location.push`, `apns-push-type: location`) — **apply to Apple for this entitlement immediately** (human/Apple-account action, not blocking). Until granted, the backend's data-only `LOCATE_REQUEST` push is used exactly as normatively specified; UI (I2) falls back to "last known, updating…". `LocationPushTokenHandling` scaffolds the token capture/registration path so wiring the extension in later is additive only.
- **Geofencing:** `CLCircularRegion` monitoring (max 20 regions — `features.limits.maxGeofences`, 000 §O9) is an I2 concern; `FindlyKit`'s geofences client methods exist now.
- **Push tokens:** FCM/APNs token registered via `PushTokenProviding` → `DeviceRegistrationService`, re-`POST /devices` on every refresh (001 §4.1, 000 §O4).
- **Auth (phone-only sign-in, specs/006):** `AuthProviding` gains `startPhoneVerification(phoneNumberE164:)`/`confirmCode(_:)` and the closed `PhoneAuthError` set (006 §4.2). `StubAuthProvider` implements the two-step dev shape (006 §5) and now emits a **real** unsigned JWT — base64url JSON header/payload with an empty signature, parseable by the backend's `AUTH_MODE=insecure-local` verifier; the previous `"stub-header.…"` shape was not valid base64url JSON and never actually worked against a local backend. `SignInViewModel`/`SignInScreen` implement the 006 §4.1 state machine (phone entry → code entry, 30 s resend cooldown via an injected virtual-time-testable sleep). `FirebaseAuthProvider` (app target) is the real implementation, wired in at the `RootView` seam via `AppConfig.authMode`/`firebaseProjectId` — it compiles to an inert fallback until the Firebase SDK dependency + `GoogleService-Info.plist` land (H1) and Firebase console phone-auth setup is done (H2).
- **Offline:** `FixQueue` (actor) — freeze-on-first-send `batchId` idempotency, in-memory queue today (Core Data/SQLite persistence is a runtime TODO), batch upload per 001 §5.1.
- **I7 hardening (Keychain, not UserDefaults):** `FirebaseAuthProvider`'s `verificationID` — previously plaintext in `UserDefaults` (flagged non-blocking in I3's security review) — now lives behind `KeychainStoring` (`FindlyKit`, protocol + `InMemoryKeychainStore` fake) with a real `Security`-framework `KeychainStore` (app target, generic-password item, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). Storage-mechanism swap only; the verify/confirm lifecycle is unchanged.
- **I8 privacy (export/delete account/delete family, specs/004 §3.6, specs/008):** `Screens/Settings/` gains a hub (`PrivacySettingsScreen`, reachable unconditionally from Home — a store requirement, 008 §4.4) plus `ExportScreen`/`DeleteAccountScreen`/`DeleteFamilyScreen`. `FindlyAPIClient` gains `exportData(userId:)` (raw `Data`, the one unenveloped success response in the API, via a new `URLSessionAPIClient.sendRawData`), `deleteAccount()`, `deleteFamily()` (both bare-204). `AuthProviding` gains `deleteCurrentUser()` — the 008 §1.3 seam FindlyKit calls after `DELETE /users/me` returns 204; `FirebaseAuthProvider` (app target) implements it as `Auth.auth().currentUser?.delete()`, kept out of FindlyKit like the rest of the real Firebase surface. `DeleteAccountViewModel` derives the 008 §4.2 cascade-warning wording from the caller's own role/roster (last parent or sole member), orders backend-then-Firebase-then-local-wipe (`FixQueue.clearAll()` + `DeviceIdProviding.clearDeviceId` + `signOut()` for the Keychain entry), and offers a Firebase-step-only retry on failure. `DeleteFamilyScreen` layers a typed-family-name gate on top of the standard `.confirmationDialog` two-step (008 §5.4's recommended UX).
