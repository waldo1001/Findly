# Findly — iOS app (Swift)

**I1 (foundation) + I2 (feature screens) + I3 (phone sign-in) + I7 (Keychain hardening) + I8 (privacy: export/delete) + I9 (Xcode app-target project) + I10 (real device runtime) + I12 (push registration + handling) implemented.** Normative design: [`specs/004-ios-client.md`](../../specs/004-ios-client.md) — read that first; it owns the architecture, the design-system token contract, the full 001 endpoint mapping, auth/token-refresh, and the fix-queue model's *rules* (batch/idempotency — the *runtime* behind those rules, incl. persistence, capture, scheduling, and push/geofence handling, is normative in [`specs/009-device-runtime.md`](../../specs/009-device-runtime.md), which 004 §7 points to rather than duplicating). Phone sign-in is normative in [`specs/006-phone-auth.md`](../../specs/006-phone-auth.md) (004 §4 owns only the iOS shapes). Wire contract: [`specs/001-api-contract.md`](../../specs/001-api-contract.md). Product context: [`specs/000-overview.md`](../../specs/000-overview.md), esp. open items **O1–O4, O9**.

## What's here

```
mobile/ios/
├── FindlyKit/         ← Swift Package — ALL logic + the design system. Builds & tests headlessly:
│   │                    `cd FindlyKit && swift build && swift test`
│   ├── Sources/FindlyKit/   Config, Networking (full 001 client, 19 endpoints), Auth (phone-only
│   │                       sign-in: AuthProviding, PhoneAuthError, PhoneNumberNormalizer,
│   │                       StubAuthProvider — specs/006), Device, Locations (the durable offline
│   │                       fix-queue — `FixQueue`/`FixStoring`/`SQLiteFixStore` — plus the sync
│   │                       runner: `LocationSyncCoordinator`/`LocationSyncRunner`, I10),
│   │                       LocationSensing (real CoreLocation/BackgroundTasks wiring +
│   │                       `LocationRuntimeContainer`, I10), Push (I12 — `PushMessageType`/
│   │                       `PushMessageDispatcher` + the four per-type handlers, `PushRuntimeContainer`
│   │                       composition root, `LocationPushTokenHandling` scaffolding), DesignSystem
│   │                       (tokens/theme/11 components), Navigation, Screens/ — two-step phone sign-in (I3) + Home, Map (live
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
                         sandbox. `Push/FirebasePushTokenProvider.swift` (I12) — the real
                         `PushTokenProviding`, bridging APNs↔`Messaging`↔the FCM token stream; kept
                         out of `FindlyKit` for the same Firebase-SDK-free reason as
                         `FirebaseAuthProvider`. `Push/AppDelegate.swift` (I12) — pure
                         `UIApplicationDelegate` glue (Firebase configure, APNs token callbacks,
                         `didReceiveRemoteNotification` → `FindlyKit`'s `PushMessageDispatcher` via
                         `PushRuntimeContainerHolder`), wired in via
                         `@UIApplicationDelegateAdaptor(AppDelegate.self)` in `FindlyApp.swift`. Also
                         holds `Assets.xcassets/AppIcon.appiconset` (I9 — the light/dark/tinted app
                         icon, `design/findly-icon/`).
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

**I10** replaces the I1 location-runtime *scaffolding* with the real thing (specs/009-device-runtime.md
§1–§4, §9). Summary — see the file-level doc comments for the full rationale on each:

- **Durable queue (§2), the central correctness property.** `FixStoring` was widened from
  `loadAll`/`append`/`remove` to also own the frozen in-flight batch's identity
  (`currentBatch`/`freezeNextBatch`/`markAccepted`/`markRejected`) — previously that identity lived
  only in `FixQueue`'s own in-memory `inFlight` property, invisible to whatever store was plugged
  in, so it never actually survived a process restart. `FixQueue` is now a thin, **stateless**
  actor that delegates every call to the store (mirrors Android's `RoomFixQueueStore` exactly).
  `SQLiteFixStore` (raw `SQLite3` C API — chosen over Core Data specifically to avoid hand-editing
  a `.xcdatamodeld` with no GUI model editor in this session, the same class of risk I9 solved for
  `.pbxproj` via `xcodegen`; see the file's doc for the full argument) performs `freezeNextBatch`/
  `markAccepted`/`markRejected`/the 1 000-cap enforcement each as one atomic `BEGIN IMMEDIATE ...
  COMMIT` transaction. `SQLiteFixStoreTests.swift`'s `survivesSimulatedProcessDeath...` tests close
  the connection and reopen a fresh instance against the same file, proving the batch identity and
  exact fix set survive — verified again for real on-device: the app's actual container shows
  `findly-fixqueue.sqlite` (+ WAL files, correct schema) after a real simulator launch.
- **Real `SystemLocationProvider`** (`LocationSensing/LocationProviding.swift`) — staged When-In-Use
  → explicit Always-upgrade authorization, `requestSingleFix(source:)` bridging
  `CLLocationManagerDelegate` to `async/await` via a checked continuation raced against a timeout
  (`withThrowingTaskGroup`, never a leak/double-resume), significant-location-change monitoring
  routed through `FixCaptureCoordinator` (not straight to `FixQueue.enqueue`) so every capture goes
  through the same §1.2 suppression. `FixCaptureCoordinator` (pure, `LocationProviding`-fake
  testable) owns pause/permission/<60s-debounce suppression, mirroring Android's
  `FixCaptureCoordinator` split exactly.
- **Real `SystemBackgroundSyncScheduler`** — registers/submits `BGAppRefreshTaskRequest` under
  specs/009 §3.4's identifier `be.dynex.findly.refresh` (also added to `Info.plist`'s
  `BGTaskSchedulerPermittedIdentifiers` — required or `submit()` throws). The 0.8-elapsed-time
  trigger rule is pure (`SyncTriggerPolicy`); backoff is pure (`BackoffPolicy`, 30s initial,
  doubling, capped at the sync interval).
- **The sync runner** (`LocationSyncCoordinator` bridges `FixQueue`↔`LocationsEndpoints`;
  `LocationSyncRunner` orchestrates capture-then-drain per opportunistic trigger) applies the
  mandatory `deviceSettings` piggyback on every accepted response via `DeviceSettingsCoordinator`
  (pure `SettingsChangeDecision` + pause/resume/reschedule), and reacts to `TRACKING_PAUSED`/
  `DEVICE_NOT_FOUND`/a second `AUTH_TOKEN_EXPIRED` per specs/009 §9. `PausedDevicePoller` covers the
  `GET /devices` resume path (app foreground + ≥6-hourly, per §4).
- **`LocationRuntimeContainer`** (`@MainActor`) composes all of the above; `RootView` constructs the
  one real instance (sharing its `FixQueue` with `DeleteAccountViewModel`'s wipe — two independent
  queues over the same file would desync) and publishes it to `LocationRuntimeContainerHolder`,
  which `FindlyApp.init()`'s `BGTaskScheduler.register(...)` call (MUST run before `init` returns,
  Apple's own requirement) reads lazily when the system actually fires the task.
- **Deferred/not this task's scope:** geofence region-monitoring lifecycle and `source: "geofence"`
  captures (I11 — a `GeofenceRegistrarStub` no-op seam is left for it, mirroring Android's A9→A11
  pattern; I12 additionally leaves a second, `GEOFENCE_CONFIG_CHANGED`-specific seam,
  `GeofenceConfigRegistering`, for the same I11 session to replace); a manual-refresh UI call site
  for `source: "manual"` (no I2 screen currently calls it — the seam accepts a source/accuracy pair
  regardless, `requestSingleFix(source:)`, ready for whenever one lands). The "first launch after
  sign-in" gap noted here originally is now closed by I12 (see below) — `onReRegisterDevice` (the
  `009 §9` `DEVICE_NOT_FOUND` reaction) remains as an additional backstop.

**I12** wires up real push handling (specs/009-device-runtime.md §5, specs/001-api-contract.md §8).
Summary — see the file-level doc comments (`FindlyKit/Sources/FindlyKit/Push/`) for the full
rationale on each:

- **Firebase SPM dependency, real and resolved.** `project.yml` adds `firebase-ios-sdk` (pinned
  `from: 11.15.0`, resolved to `11.15.0` — see the committed `Package.resolved` under
  `Findly.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`) as a remote package, linking only
  the two products this task needs — `FirebaseMessaging` + `FirebaseCore` — into the `Findly`
  target (mirrors how `FindlyKit` itself is wired as a local package dependency). `FirebaseAuth` is
  deliberately **not** added — that's I3's own already-written, `#if canImport(FirebaseAuth)`-gated
  `FirebaseAuthProvider` code, left inert on purpose until a future session's task adds that
  product. **Verified for real, not just assumed:** `xcodebuild build` resolves the package over the
  network (a full clone of `firebase-ios-sdk` + its transitive Google dependencies) and links it
  cleanly; a concrete-simulator build + `simctl install`/`launch` on a real iPhone 17 Simulator
  (Xcode 26.6) shows `FirebaseMessaging` genuinely initializing at runtime (`[FirebaseMessaging]
  ...FIRMessaging Remote Notifications proxy enabled...` in the device log, no crash) against the
  real, gitignored `GoogleService-Info.plist` (Firebase project `findly-71f7b`) — that config file
  is never committed and this session confirmed it stays gitignored (`git status` shows nothing).
- **`PushMessageType`/`PushMessageDispatcher`** (`FindlyKit/Push/`) — the `data.type` discriminator
  and routing table, mirroring Android's A9 `PushMessageType`/`PushMessageDispatcher` exactly.
  Unknown types and the §8.7 reserved group types both parse to `.unrecognized` and dispatch to no
  handler at all (001 §1.1 forward compatibility) — never a crash.
- **`LocateRequestPushHandler`** — `now > expiresAt + 10 min` → silently ignored (no GPS burn);
  otherwise calls `LocationProviding.requestSingleFix(source: .locate)` **directly**, bypassing
  `FixCaptureCoordinator` entirely (its own doc explicitly names this pattern) so a paused device
  still fulfills the request, then `POST /locate-requests/{id}/fulfill`. Every failure mode (no
  `deviceId`, capture failure, fulfill-call failure) is a silent give-up, never a crash or retry —
  "the requester's own poll surfaces the outcome" (009 §5.1).
- **`SettingsChangedPushHandler`** — parses both fields defensively (strict `"true"`/`"false"` only,
  matching Android's `toBooleanStrictOrNull`), forwards the full snapshot into
  `DeviceSettingsApplying` (the seam `DeviceSettingsCoordinator`'s own doc names as I12's target) —
  never a delta, exactly as 001 §8.3 requires.
- **`GeofenceEventPushHandler`/`GeofenceEventNotificationTemplate`** — the exact 001 §8.2 title
  template (`"<name> arrived at <geofence>"` / `"<name> left <geofence>"`, no body/time text),
  matched to Android's `GeofenceEventNotificationTemplate` wording; the real notifier
  (`SystemGeofenceEventNotifier`, `FindlyKit`, `#if os(iOS) && canImport(UserNotifications)`) posts
  a genuine local `UNNotificationRequest` built from the push's own `data`, and both are unit-tested.
  **Correction (found via real `xcrun simctl push` injection against the foregrounded app, code
  review): this path is currently dead code, not a deliberate alternative to the OS's own
  rendering.** 001 §8.2's actual wire shape (`aps.alert.title` set, `mutable-content: 1`, **no**
  `content-available`) means iOS auto-displays the push's own server-embedded `notification.title`
  directly — `willPresent` (the pure show/suppress decision) is the only callback that fires;
  `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`, the one thing wired to
  `PushMessageDispatcher`, is never invoked for this shape, foreground or background (confirmed:
  the displayed banner carried the push's own delivery identifier, not a freshly-generated `UUID()`
  from `SystemGeofenceEventNotifier`). Not user-visibly broken today — server and client build the
  identical title off the same template, so the content is correct regardless of which path
  renders it — but `GeofenceEventPushHandler`/`GeofenceEventNotificationTemplate`/
  `SystemGeofenceEventNotifier` don't actually run for any real `GEOFENCE_EVENT` delivery yet. The
  architecturally correct mechanism for what `mutable-content: 1` is meant to enable is a
  `UNNotificationServiceExtension` app-extension target (which doesn't exist) — re-rendering the
  alert from `data` *before* display, per 000 §O8's own wording. That target is a genuinely
  separate, larger task, out of scope tonight; this code stays as the tested logic it would plug
  into once that extension exists. No custom icon needed either way — iOS uses the app icon
  directly (009 §8).
- **`GeofenceConfigChangedPushHandler`/`GeofenceConfigSyncCoordinator`** — the ETag-conditional
  `GET /geofences` fetch-cache sequence (`GeofenceConfigCaching`, in-memory + `UserDefaults`
  implementations); actual platform re-registration is I11's scope, stubbed behind a new
  `GeofenceConfigRegistering` seam (`NoOpGeofenceConfigRegistering` default) with the exact same
  "I12 builds the seam, I11 replaces the no-op" pattern Android's A9→A11 established for
  `GeofenceRegistrar`.
- **Token lifecycle.** `FirebasePushTokenProvider` (app target) bridges the raw APNs device token
  (`AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` →
  `Messaging.messaging().apnsToken`) into the **FCM token** surfaced via `MessagingDelegate` — the
  FCM token, not the raw APNs token, is what `RegisterDeviceRequest.pushToken` expects (matches
  Android's model). Wired into the already-existing, already-tested `DeviceRegistrationService.
  observePushTokenRefreshes` with zero call-site change (same "swap the stub, keep the interface"
  pattern Android's `RealPushTokenProvider` used). `DeviceRegistrationService` gains
  `registerOnLaunchIfNeeded(appVersionTracker:)` — the two remaining specs/004 §5 triggers (first
  launch after sign-in, every app update, keyed per-`userId` via the new
  `AppVersionRegistrationTracking` protocol) — called once at cold launch (`FindlyApp.init()`, if
  already signed in) and again from `RootView`'s `SignInViewModel.onSignedIn` completion (a session
  that starts at the sign-in screen).
- **`LOCATE_REQUEST`'s background-wake payload, checked against the real backend source** (not
  assumed): `backend/src/adapters/push/fcmV1Sender.ts`'s `buildLocateRequestBody` already sends
  `apns.payload.aps["content-available"]: 1` (+ `Info.plist`'s pre-existing `UIBackgroundModes:
  remote-notification`, from I10) — the payload IS shaped to wake the app, matching 001 §8.1
  exactly; on iOS this remains a budgeted/coalesced **best-effort** background push by Apple's own
  design (000 §O1), which the spec already documents as the expected v1 posture pending the
  Location Push entitlement. **A genuine backend gap found while checking this** (not this task's
  scope to fix, flagged and spawned as a follow-up): `fcmV1Sender.ts`'s payload-builder `switch`
  has no case for `"SETTINGS_CHANGED"` and throws `"...is out of B4/B5 scope"` for it — but
  `backend/src/domain/device/patchDeviceSettings.ts` already calls `pushSender.send({ type:
  "SETTINGS_CHANGED", ... })` on every parent-initiated settings change, wrapped in a swallowing
  `catch` (by design, §10's `PUSH_DELIVERY_FAILED` note), so that push has silently never actually
  been sent to a device in production. The iOS handler above is correct and ready for it regardless
  — the two guaranteed pickup paths (§5.1's `deviceSettings` piggyback, the paused-device poll)
  don't depend on this push at all.
- **Logging discipline (009 §9):** no coordinates/`deviceId`/tokens/phone numbers are logged
  anywhere in this task's new code — `FirebasePushTokenProvider.messaging(_:didReceiveRegistrationToken:)`
  deliberately logs nothing at all rather than risk it, and `AppDelegate.application(_:
  didFailToRegisterForRemoteNotificationsWithError:)` is an intentional no-op body for the same
  reason.
- **`onSignedIn` shared-file touches, for I11's awareness:** `FindlyApp.swift` gains
  `@UIApplicationDelegateAdaptor(AppDelegate.self)`, the `PushRuntimeContainer` construction block,
  and the `onSignedIn: () async -> Void` closure/property; `RootView.swift` gains one new init
  parameter (`onSignedIn`) threaded into `SignInViewModel`'s existing `onSignedIn` callback.
  `LocationRuntimeContainer.swift` gains one read-only computed property,
  `settingsApplying: DeviceSettingsApplying { settingsCoordinator }` — no behavior change, just
  exposure of an already-built instance. `project.yml` gains the `FirebaseSDK` package + two target
  dependencies. None of these touch geofence-specific code paths I11 owns.

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

**I12 note:** the first `xcodebuild build` after this task's `project.yml` change resolves the new
`firebase-ios-sdk` remote Swift Package dependency over the network (a full clone of the SDK repo
+ transitive Google dependencies — several minutes on a cold cache, seconds once
`~/Library/Caches/org.swift.swiftpm/repositories/` and `~/Library/Developer/Xcode/DerivedData/*/SourcePackages/`
are warm). CI will pay this cost on its first run too; no different from any other remote SPM
dependency.

## Key decisions (see specs/004 for the full normative text)

- **Location sync (I10, real):** `SystemLocationProvider` wraps `CLLocationManager` with staged onboarding (When-In-Use on first use, an explicit `requestAlwaysAuthorizationUpgrade()` for the app to call after showing an in-app explanation — no I2 screen calls it yet, so it stays dormant until one does); background fixes via significant-change monitoring, routed through `FixCaptureCoordinator`'s suppression rather than straight into the queue; `SystemBackgroundSyncScheduler` submits opportunistic `BGAppRefreshTaskRequest`s under identifier `be.dynex.findly.refresh`. Verified for real: a booted iOS Simulator install triggers the genuine system When-In-Use prompt with the exact `Info.plist` copy, and the app stays alive with no crash. iOS does not honor exact periodic intervals — the interval is a *target*; the UI (I2) must document the delivered cadence honestly.
- **Push-to-locate (000 §O1 — the #1 platform risk):** correct mechanism is the **Location Push Service Extension** (`com.apple.developer.location.push`, `apns-push-type: location`) — **apply to Apple for this entitlement immediately** (human/Apple-account action, not blocking). Until granted, the backend's data-only `LOCATE_REQUEST` push is used exactly as normatively specified; UI (I2) falls back to "last known, updating…". `LocationPushTokenHandling` scaffolds the token capture/registration path so wiring the extension in later is additive only.
- **Geofencing:** `CLCircularRegion` monitoring (max 20 regions — `features.limits.maxGeofences`, 000 §O9) is an I2/I11 concern; `FindlyKit`'s geofences client methods exist now; I12 additionally lands the `GEOFENCE_CONFIG_CHANGED` push→`GET /geofences` fetch-cache half, with the platform-registration half stubbed behind `GeofenceConfigRegistering` for I11.
- **Push tokens (I12, real):** the real FCM token — bridged from APNs via `FirebasePushTokenProvider` (app target, `Messaging.messaging().apnsToken` → `MessagingDelegate`) — is registered via `PushTokenProviding` → `DeviceRegistrationService.observePushTokenRefreshes`, re-`POST /devices` on every refresh (001 §4.1, 000 §O4), plus on first launch after sign-in and every app update (`registerOnLaunchIfNeeded`, specs/004 §5).
- **Push routing (I12, real):** `PushMessageDispatcher` (`FindlyKit/Push/`) routes all four `data.type` values (001 §8) to their handlers — `LOCATE_REQUEST` (bypasses `FixCaptureCoordinator`, fulfills even while paused), `SETTINGS_CHANGED` (full-state, idempotent, into `DeviceSettingsApplying`), `GEOFENCE_EVENT` (local `UNNotificationRequest` from the push's own `data`, matching Android's title template — **but currently unreached for real deliveries**, see the I12 section below: 001 §8.2's actual payload shape lets iOS auto-display its own embedded title before `PushMessageDispatcher` ever sees the push; the handler is correct/tested and would need a `UNNotificationServiceExtension` target to actually run), `GEOFENCE_CONFIG_CHANGED` (ETag-conditional re-fetch). `AppDelegate` (app target) is pure OS-lifecycle glue reaching this dispatcher via `PushRuntimeContainerHolder`.
- **Auth (phone-only sign-in, specs/006):** `AuthProviding` gains `startPhoneVerification(phoneNumberE164:)`/`confirmCode(_:)` and the closed `PhoneAuthError` set (006 §4.2). `StubAuthProvider` implements the two-step dev shape (006 §5) and now emits a **real** unsigned JWT — base64url JSON header/payload with an empty signature, parseable by the backend's `AUTH_MODE=insecure-local` verifier; the previous `"stub-header.…"` shape was not valid base64url JSON and never actually worked against a local backend. `SignInViewModel`/`SignInScreen` implement the 006 §4.1 state machine (phone entry → code entry, 30 s resend cooldown via an injected virtual-time-testable sleep). `FirebaseAuthProvider` (app target) is the real implementation, wired in at the `RootView` seam via `AppConfig.authMode`/`firebaseProjectId` — it compiles to an inert fallback until the Firebase SDK dependency + `GoogleService-Info.plist` land (H1) and Firebase console phone-auth setup is done (H2).
- **Offline (I10, durable):** `FixQueue` (actor, now stateless — every call delegates to `FixStoring`) — freeze-on-first-send `batchId` idempotency, batch upload per 001 §5.1. `SQLiteFixStore` (raw `SQLite3` C API, app-private `Library/Application Support/findly-fixqueue.sqlite`) persists both the fix rows *and* the frozen in-flight batch's identity, so a retry after a crash resends identical content (specs/009 §2) — proven by a test that reopens a fresh store instance against the same file and by a real on-simulator file inspection (see the I10 section above). 1 000-fix cap, oldest-pending-dropped-first, one debug-level count-only log line per drop.
- **I7 hardening (Keychain, not UserDefaults):** `FirebaseAuthProvider`'s `verificationID` — previously plaintext in `UserDefaults` (flagged non-blocking in I3's security review) — now lives behind `KeychainStoring` (`FindlyKit`, protocol + `InMemoryKeychainStore` fake) with a real `Security`-framework `KeychainStore` (app target, generic-password item, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). Storage-mechanism swap only; the verify/confirm lifecycle is unchanged.
- **I8 privacy (export/delete account/delete family, specs/004 §3.6, specs/008):** `Screens/Settings/` gains a hub (`PrivacySettingsScreen`, reachable unconditionally from Home — a store requirement, 008 §4.4) plus `ExportScreen`/`DeleteAccountScreen`/`DeleteFamilyScreen`. `FindlyAPIClient` gains `exportData(userId:)` (raw `Data`, the one unenveloped success response in the API, via a new `URLSessionAPIClient.sendRawData`), `deleteAccount()`, `deleteFamily()` (both bare-204). `AuthProviding` gains `deleteCurrentUser()` — the 008 §1.3 seam FindlyKit calls after `DELETE /users/me` returns 204; `FirebaseAuthProvider` (app target) implements it as `Auth.auth().currentUser?.delete()`, kept out of FindlyKit like the rest of the real Firebase surface. `DeleteAccountViewModel` derives the 008 §4.2 cascade-warning wording from the caller's own role/roster (last parent or sole member), orders backend-then-Firebase-then-local-wipe (`FixQueue.clearAll()` + `DeviceIdProviding.clearDeviceId` + `signOut()` for the Keychain entry), and offers a Firebase-step-only retry on failure. `DeleteFamilyScreen` layers a typed-family-name gate on top of the standard `.confirmationDialog` two-step (008 §5.4's recommended UX).
