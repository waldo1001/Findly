# Findly — iOS app (Swift)

**I1 (foundation) + I2 (feature screens) + I3 (phone sign-in) + I7 (Keychain hardening) + I8 (privacy: export/delete) + I9 (Xcode app-target project) + I10 (real device runtime) + I11 (geofencing) implemented.** Normative design: [`specs/004-ios-client.md`](../../specs/004-ios-client.md) — read that first; it owns the architecture, the design-system token contract, the full 001 endpoint mapping, auth/token-refresh, and the fix-queue model's *rules* (batch/idempotency — the *runtime* behind those rules, incl. persistence, capture, scheduling, and push/geofence handling, is normative in [`specs/009-device-runtime.md`](../../specs/009-device-runtime.md), which 004 §7 points to rather than duplicating). Phone sign-in is normative in [`specs/006-phone-auth.md`](../../specs/006-phone-auth.md) (004 §4 owns only the iOS shapes). Wire contract: [`specs/001-api-contract.md`](../../specs/001-api-contract.md). Product context: [`specs/000-overview.md`](../../specs/000-overview.md), esp. open items **O1–O4, O9**.

## What's here

```
mobile/ios/
├── FindlyKit/         ← Swift Package — ALL logic + the design system. Builds & tests headlessly:
│   │                    `cd FindlyKit && swift build && swift test`
│   ├── Sources/FindlyKit/   Config, Networking (full 001 client, 19 endpoints), Auth (phone-only
│   │                       sign-in: AuthProviding, PhoneAuthError, PhoneNumberNormalizer,
│   │                       StubAuthProvider — specs/006), Device, Locations (the durable offline
│   │                       fix-queue — `FixQueue`/`FixStoring`/`SQLiteFixStore` — plus the sync
│   │                       runner: `LocationSyncCoordinator`/`LocationSyncRunner`, I10; and the
│   │                       durable geofence-event queue — `GeofenceEventQueue`/
│   │                       `GeofenceEventQueueStoring`/`SQLiteGeofenceEventQueueStore` +
│   │                       `GeofenceEventSyncCoordinator`, I11),
│   │                       LocationSensing (real CoreLocation/BackgroundTasks wiring +
│   │                       `LocationRuntimeContainer`, I10; region-monitoring registration +
│   │                       transition handling — `GeofenceConfigSyncCoordinator`,
│   │                       `SystemGeofenceRegistrar`, `GeofenceTransitionHandler`, I11), Push, DesignSystem (tokens/theme/11
│   │                       components), Navigation, Screens/ — two-step phone sign-in (I3) + Home, Map (live
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
- **Deferred/not this task's scope (at the time):** geofence region-monitoring lifecycle and
  `source: "geofence"` captures — a `GeofenceRegistrarStub` no-op seam was left for it, mirroring
  Android's A9→A11 pattern. **I11 (below) has since landed this.** `SETTINGS_CHANGED`/
  `LOCATE_REQUEST`/`GEOFENCE_*` push routing (I12 — `DeviceSettingsApplying` is the seam a push
  handler plugs into, and I11 adds `GeofenceConfigSyncCoordinator.sync()` as the identical seam for
  `GEOFENCE_CONFIG_CHANGED`); a manual-refresh UI call site for `source: "manual"` (no
  I2 screen currently calls it — the seam accepts a source/accuracy pair regardless, `requestSingleFix(source:)`,
  ready for whenever one lands). Also noted: nothing in I1–I9 ever wired `DeviceRegistrationService`
  to a "first launch after sign-in" trigger — a pre-existing gap, not an I10 regression — so this
  task wired `onReRegisterDevice` (the `009 §9` `DEVICE_NOT_FOUND` reaction) to call it, which
  self-heals a never-registered `deviceId` on the very first sync attempt; a proper eager trigger
  right after sign-in is still a good follow-up (I11's own "first config sync after sign-in"
  geofence trigger has the identical gap and works around it the same way — see below).

**I11** implements geofencing end to end (specs/009-device-runtime.md §6, §7). Summary — see the
file-level doc comments for the full rationale on each:

- **The registration seam** — `GeofenceRegistering` (`LocationSensing/GeofenceRegistering.swift`)
  widens I10's `GeofenceRegistrarStub` (`unregisterAll()` only) with `registerAll(geofences:etag:)`.
  `SystemGeofenceRegistrar` (`LocationSensing/SystemGeofenceRegistrar.swift`) is the one real class
  implementing both halves, mirroring how Android's A11 ended up with one `GeofencingClientManager`
  implementing both `GeofenceRegistry`/`GeofenceRegistrar` — a dedicated `CLLocationManager`
  instance (separate from `SystemLocationProvider`'s), so I11 never touches I10's already-reviewed
  single-fix/significant-location-change code at all. Full replace ("unregister all, then register
  all") on every call; non-atomicity between the two platform calls is accepted, not fixed
  (specs/009 §6.2, normative) — the self-healing bound is the existing `geofenceEtag` piggyback
  trigger set. Defensively capped at `min(features.limits.maxGeofences, 20)` — the CLLocationManager
  platform ceiling (000 §O9) — even though its only caller already caps there first.
- **The local geofence-config cache** — `GeofenceConfigStateStoring` (`CachedGeofenceConfig`
  doc+ETag, `InMemoryGeofenceConfigStateStore`/`UserDefaultsGeofenceConfigStateStore`) — the same
  protocol+real/fake split as `DeviceSettingsStateStoring`. `GeofenceConfigSyncCoordinator`
  (`LocationSensing/GeofenceConfigSyncCoordinator.swift`) is the consolidated "fetch (`If-None-Match`)
  → cache → full re-register" sequence every trigger below calls through — a `304`/failed fetch
  still re-registers from cache (resume/cold-start need the OS-level registrations rebuilt even when
  the config itself didn't change).
- **All five registration triggers (specs/009 §6.2) are wired:**
  1. *First config sync after sign-in* — `LocationRuntimeContainer.onSignedIn()`, called from
     `RootView`'s `SignInViewModel(onSignedIn:)` completion callback. (iOS has no
     `DeviceRegistrar.onRegistered`-shaped hook the way Android does — a pre-existing gap flagged in
     I10's own section above — so this in-app sign-in-flow callback is the closest unambiguous
     signal; it also correctly covers an in-app sign-out→sign-in cycle that never re-runs
     `FindlyApp.init()`, which a cold-start-only trigger would miss.)
  2. *`geofenceEtag` mismatch from the `POST /locations` piggyback* — `LocationSyncRunner`'s fix-queue
     drain now applies `GeofenceConfigSyncing.syncIfEtagChanged(_:)` on every `.synced` outcome,
     alongside the pre-existing mandatory `deviceSettings` piggyback.
  3. *`geofenceEtag` mismatch from `POST /geofence-events` responses* — `LocationSyncRunner` gained a
     second drain loop (`drainGeofenceEventQueue()`, run right after the fix-queue drain, both against
     the identical `MAX_BATCHES_PER_RUN`/piggyback-application pattern) applying the same trigger.
  4. *Resume from pause* — `DeviceSettingsCoordinator`'s `onResume` closure (wired in
     `LocationRuntimeContainer.init`) now also calls `GeofenceConfigSyncCoordinator.sync()`, alongside
     restarting significant-location-change monitoring/the BG schedule.
  5. *App cold start* (covers reboot/reinstall, both of which lose OS-level geofence registrations
     without changing anything server-side) — `LocationRuntimeContainer.syncGeofenceConfigOnColdStart()`,
     called from `FindlyApp.init()` in its own `Task` right after `container.start()`. Deliberately
     **not** folded into `start()` itself — `start()` stays a plain synchronous call with no
     fire-and-forget async work racing its own synchronous side effects (every existing `start()`
     test asserts those immediately after calling it).
- **Transition handling (specs/009 §6.3).** `GeofenceTransitionHandler`
  (`LocationSensing/GeofenceTransitionHandler.swift`, pure/tested, mirrors `FixCaptureCoordinator`'s
  CoreLocation-free split) builds one durable event per callback (client-generated UUIDv4 `eventId`,
  assigned once at enqueue and never regenerated on retry) and additionally calls
  `fixCaptureCoordinator.captureAndQueue(source: .geofence, hint:)` — I10's own seam, built exactly
  for this — using the region's own center/`manager.location` as "the transition's own coordinates"
  (iOS's `CLLocationManagerDelegate` region callbacks carry no triggering-location field the way
  Android's `GeofencingEvent` does; a documented judgment call). A transition detected while paused
  is dropped, not queued (specs/009 §4) — checked here directly since the event-queue enqueue
  bypasses `FixCaptureCoordinator`'s own pause gate entirely. `SystemGeofenceRegistrar`'s
  `CLLocationManagerDelegate` conformance is the thin, untested glue that forwards
  `didEnterRegion`/`didExitRegion` into this handler (a `weak`, post-construction-settable reference
  — `SystemGeofenceRegistrar` is built before `LocationRuntimeContainer`/the handler exist, same
  "settable reference wired after the fact" pattern I10 established for
  `SystemLocationProvider`/`FixCaptureCoordinator`).
- **The durable geofence-event queue (specs/009 §6.3), same durability bar as I10's fix queue
  (specs/009 §2).** `GeofenceEventQueueStoring` mirrors `FixStoring`'s freeze-on-first-ask shape
  (`InMemoryGeofenceEventQueueStore`/`SQLiteGeofenceEventQueueStore`) — simpler than the fix store in
  two ways: no overflow cap (not specified for events; a detected transition must never be dropped
  for capacity reasons) and no per-event rejection method (001 §7.3 defines none — every
  non-`TRACKING_PAUSED` failure just retries the whole frozen batch). `SQLiteGeofenceEventQueueStore`
  follows `SQLiteFixStore`'s exact pattern: one atomic `BEGIN IMMEDIATE...COMMIT` transaction per
  composite operation, every runtime value bound via `sqlite3_bind_*` (never string-interpolated —
  I10's review caught and fixed one violation of that rule; this file was written with the same
  discipline from the start). `GeofenceEventQueue` (actor, stateless, mirrors `FixQueue`) +
  `GeofenceEventSyncCoordinator` (mirrors `LocationSyncCoordinator`) complete the parallel.
- **Local-state wipe (specs/008 §4.4).** `DeleteAccountViewModel` now also clears the geofence-event
  queue and cached geofence config/ETag, the same "local state" reasoning that already covered
  `FixQueue` — a stale batch or a now-meaningless-but-still-"unchanged"-looking ETag surviving
  deletion could otherwise resurface a since-deleted user's data or silently skip a re-signed-in
  account's re-registration.
- **Permissions (specs/009 §7).** `SystemGeofenceRegistrar.registerAll` checks current authorization
  (`.authorizedWhenInUse`/`.authorizedAlways`) before calling `startMonitoring(for:)` — a proactive
  gate, mirroring `FixCaptureCoordinator.isPermissionGranted`, not just letting `CLLocationManager`
  silently no-op. Does not itself request authorization — `SystemLocationProvider`'s staged
  When-In-Use → Always flow (I10) already owns that, and duplicating a request here would risk a
  second, redundant system prompt.
- **Deferred/not this task's scope:** the `GEOFENCE_CONFIG_CHANGED` push arrival path itself (I12) —
  `GeofenceConfigSyncCoordinator.sync()` is the exact seam a future push handler calls (mirrors
  `DeviceSettingsApplying`'s role for `SETTINGS_CHANGED`), the same pattern
  `GeofenceConfigChangedPushHandler` uses on Android against its own `GeofenceConfigSyncCoordinator.sync()`.
  I11 does not touch `FindlyApp.swift`'s push-registration wiring or any push-message DTO/handler
  file, so no merge conflict with I12's own work is expected there.
- **A spec judgment call worth flagging:** iOS's `CLLocationManagerDelegate` region-monitoring
  callbacks (`didEnterRegion`/`didExitRegion`) carry no triggering-location field, unlike Android's
  `GeofencingEvent.triggeringLocation`. specs/009 §6.3's "MAY reuse the transition's own coordinates"
  is interpreted here as: prefer `CLLocationManager`'s own last-known `location` (a real GPS
  observation) when CoreLocation happens to have one cached, falling back to the triggering
  `CLCircularRegion`'s own `center`/`radius` otherwise. This is the best available proxy on this
  platform, not a literal reading of a field the platform doesn't provide.

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

- **Location sync (I10, real):** `SystemLocationProvider` wraps `CLLocationManager` with staged onboarding (When-In-Use on first use, an explicit `requestAlwaysAuthorizationUpgrade()` for the app to call after showing an in-app explanation — no I2 screen calls it yet, so it stays dormant until one does); background fixes via significant-change monitoring, routed through `FixCaptureCoordinator`'s suppression rather than straight into the queue; `SystemBackgroundSyncScheduler` submits opportunistic `BGAppRefreshTaskRequest`s under identifier `be.dynex.findly.refresh`. Verified for real: a booted iOS Simulator install triggers the genuine system When-In-Use prompt with the exact `Info.plist` copy, and the app stays alive with no crash. iOS does not honor exact periodic intervals — the interval is a *target*; the UI (I2) must document the delivered cadence honestly.
- **Push-to-locate (000 §O1 — the #1 platform risk):** correct mechanism is the **Location Push Service Extension** (`com.apple.developer.location.push`, `apns-push-type: location`) — **apply to Apple for this entitlement immediately** (human/Apple-account action, not blocking). Until granted, the backend's data-only `LOCATE_REQUEST` push is used exactly as normatively specified; UI (I2) falls back to "last known, updating…". `LocationPushTokenHandling` scaffolds the token capture/registration path so wiring the extension in later is additive only.
- **Geofencing (I11, real):** `SystemGeofenceRegistrar` wraps a dedicated `CLLocationManager` for `CLCircularRegion` monitoring, capped at `min(features.limits.maxGeofences, 20)` (000 §O9's platform ceiling). `GeofenceConfigSyncCoordinator` drives the fetch/cache/full-replace-register sequence across all five specs/009 §6.2 triggers (first sync after sign-in, two `geofenceEtag`-piggyback mismatch paths, resume from pause, cold start). `GeofenceTransitionHandler` builds the durable per-transition event (`SQLiteGeofenceEventQueueStore`, same durability bar as the fix queue) and the accompanying `source: "geofence"` fix via I10's `FixCaptureCoordinator` hint seam. See the I11 section above for the full breakdown.
- **Push tokens:** FCM/APNs token registered via `PushTokenProviding` → `DeviceRegistrationService`, re-`POST /devices` on every refresh (001 §4.1, 000 §O4).
- **Auth (phone-only sign-in, specs/006):** `AuthProviding` gains `startPhoneVerification(phoneNumberE164:)`/`confirmCode(_:)` and the closed `PhoneAuthError` set (006 §4.2). `StubAuthProvider` implements the two-step dev shape (006 §5) and now emits a **real** unsigned JWT — base64url JSON header/payload with an empty signature, parseable by the backend's `AUTH_MODE=insecure-local` verifier; the previous `"stub-header.…"` shape was not valid base64url JSON and never actually worked against a local backend. `SignInViewModel`/`SignInScreen` implement the 006 §4.1 state machine (phone entry → code entry, 30 s resend cooldown via an injected virtual-time-testable sleep). `FirebaseAuthProvider` (app target) is the real implementation, wired in at the `RootView` seam via `AppConfig.authMode`/`firebaseProjectId` — it compiles to an inert fallback until the Firebase SDK dependency + `GoogleService-Info.plist` land (H1) and Firebase console phone-auth setup is done (H2).
- **Offline (I10, durable):** `FixQueue` (actor, now stateless — every call delegates to `FixStoring`) — freeze-on-first-send `batchId` idempotency, batch upload per 001 §5.1. `SQLiteFixStore` (raw `SQLite3` C API, app-private `Library/Application Support/findly-fixqueue.sqlite`) persists both the fix rows *and* the frozen in-flight batch's identity, so a retry after a crash resends identical content (specs/009 §2) — proven by a test that reopens a fresh store instance against the same file and by a real on-simulator file inspection (see the I10 section above). 1 000-fix cap, oldest-pending-dropped-first, one debug-level count-only log line per drop.
- **I7 hardening (Keychain, not UserDefaults):** `FirebaseAuthProvider`'s `verificationID` — previously plaintext in `UserDefaults` (flagged non-blocking in I3's security review) — now lives behind `KeychainStoring` (`FindlyKit`, protocol + `InMemoryKeychainStore` fake) with a real `Security`-framework `KeychainStore` (app target, generic-password item, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). Storage-mechanism swap only; the verify/confirm lifecycle is unchanged.
- **I8 privacy (export/delete account/delete family, specs/004 §3.6, specs/008):** `Screens/Settings/` gains a hub (`PrivacySettingsScreen`, reachable unconditionally from Home — a store requirement, 008 §4.4) plus `ExportScreen`/`DeleteAccountScreen`/`DeleteFamilyScreen`. `FindlyAPIClient` gains `exportData(userId:)` (raw `Data`, the one unenveloped success response in the API, via a new `URLSessionAPIClient.sendRawData`), `deleteAccount()`, `deleteFamily()` (both bare-204). `AuthProviding` gains `deleteCurrentUser()` — the 008 §1.3 seam FindlyKit calls after `DELETE /users/me` returns 204; `FirebaseAuthProvider` (app target) implements it as `Auth.auth().currentUser?.delete()`, kept out of FindlyKit like the rest of the real Firebase surface. `DeleteAccountViewModel` derives the 008 §4.2 cascade-warning wording from the caller's own role/roster (last parent or sole member), orders backend-then-Firebase-then-local-wipe (`FixQueue.clearAll()` + `DeviceIdProviding.clearDeviceId` + `signOut()` for the Keychain entry), and offers a Firebase-step-only retry on failure. `DeleteFamilyScreen` layers a typed-family-name gate on top of the standard `.confirmationDialog` two-step (008 §5.4's recommended UX).
