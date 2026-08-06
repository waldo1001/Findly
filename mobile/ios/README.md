# Findly — iOS app (Swift)

**I1 (foundation) + I2 (feature screens) + I3 (phone sign-in) + I7 (Keychain hardening) + I8 (privacy: export/delete) + I9 (Xcode app-target project) + I10 (real device runtime) + I11 (geofencing) + I12 (push registration + handling) + I15 (Notification Service Extension) implemented.** Normative design: [`specs/004-ios-client.md`](../../specs/004-ios-client.md) — read that first; it owns the architecture, the design-system token contract, the full 001 endpoint mapping, auth/token-refresh, and the fix-queue model's *rules* (batch/idempotency — the *runtime* behind those rules, incl. persistence, capture, scheduling, and push/geofence handling, is normative in [`specs/009-device-runtime.md`](../../specs/009-device-runtime.md), which 004 §7 points to rather than duplicating). Phone sign-in is normative in [`specs/006-phone-auth.md`](../../specs/006-phone-auth.md) (004 §4 owns only the iOS shapes). Wire contract: [`specs/001-api-contract.md`](../../specs/001-api-contract.md). Product context: [`specs/000-overview.md`](../../specs/000-overview.md), esp. open items **O1–O4, O9**.

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
│   │                       `SystemGeofenceRegistrar`, `GeofenceTransitionHandler`, I11), Push (I12 —
│   │                       `PushMessageType`/`PushMessageDispatcher` + the four per-type handlers,
│   │                       `PushRuntimeContainer` composition root, `LocationPushTokenHandling`
│   │                       scaffolding — its `GEOFENCE_CONFIG_CHANGED` handler shares I11's real
│   │                       `GeofenceConfigSyncCoordinator` instance, not a second one;
│   │                       `GeofenceEventServiceExtensionRendering`, I15 — the pure re-render
│   │                       function the `FindlyNotificationService` extension target calls, reusing
│   │                       `GeofenceEventNotificationTemplate` rather than duplicating it;
│   │                       `PushPayloadParsing`, I15 round 2 — the shared `userInfo` ->
│   │                       `[String: String]` bridging both `NotificationService` and `AppDelegate`
│   │                       call, replacing what were two independent inline copies), DesignSystem
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
└── FindlyNotificationService/   ← Notification Service Extension app-extension target (I15,
                         specs/001 §8.2, specs/000 §O8). `NotificationService.swift` — the ONLY file
                         here — is deliberately logic-free: it bridges `UNNotificationRequest.
                         content.userInfo` into the `[String: String]` shape FindlyKit's push types
                         already parse (same conversion `AppDelegate` does inline) and applies
                         `GeofenceEventServiceExtensionRendering.title(for:)` (FindlyKit, unit-
                         tested) to a mutable copy of the content, falling back to the untouched
                         server content — both on a normal completion and on
                         `serviceExtensionTimeWillExpire()` — if nothing renders. Depends on
                         FindlyKit only, not the Firebase SDK (it never talks to FCM/APNs
                         registration, only receives an already-delivered push from the OS).
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
- **`GEOFENCE_CONFIG_CHANGED` push arrival (I12, reconciled post-merge):** `GeofenceConfigSyncCoordinator.sync()`
  (this section, above) is exactly the seam `GeofenceConfigChangedPushHandler` (I12, below) calls —
  I12 originally built its own placeholder trio ahead of I11 landing; once I11 merged, that trio was
  deleted and the push handler retargeted at this real coordinator, sharing the SAME instance
  `LocationRuntimeContainer` builds (see the I12 section below for the reconciliation detail). I11
  itself never touched any push-message DTO/handler file — the actual merge conflicts, as predicted,
  were limited to `FindlyApp.swift`/`RootView.swift` (both sessions' additive composition-root
  wiring landing near the same lines) plus the `Push/GeofenceConfig*` naming collision, not any
  logical disagreement.
- **A spec judgment call worth flagging:** iOS's `CLLocationManagerDelegate` region-monitoring
  callbacks (`didEnterRegion`/`didExitRegion`) carry no triggering-location field, unlike Android's
  `GeofencingEvent.triggeringLocation`. specs/009 §6.3's "MAY reuse the transition's own coordinates"
  is interpreted here as: prefer `CLLocationManager`'s own last-known `location` (a real GPS
  observation) when CoreLocation happens to have one cached, falling back to the triggering
  `CLCircularRegion`'s own `center`/`radius` otherwise. This is the best available proxy on this
  platform, not a literal reading of a field the platform doesn't provide.

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
  `SystemGeofenceEventNotifier` don't actually run for any real `GEOFENCE_EVENT` delivery yet
  **(now addressed — see the I15 section below).** The architecturally correct mechanism for what
  `mutable-content: 1` is meant to enable is a `UNNotificationServiceExtension` app-extension
  target — re-rendering the alert from `data` *before* display, per 000 §O8's own wording. No
  custom icon needed either way — iOS uses the app icon directly (009 §8).
- **`GeofenceConfigChangedPushHandler`** — a thin delegate onto `GeofenceConfigSyncCoordinator.sync()`.
  **Reconciled post-I11-merge:** I12 originally shipped its own placeholder
  `GeofenceConfigCaching`/`GeofenceConfigRegistering`/`GeofenceConfigSyncCoordinator` trio ahead of
  I11 landing (same "build the seam, a later session replaces the no-op" pattern Android's A9→A11
  established for `GeofenceRegistrar`). Once I11 merged with the real
  `LocationSensing/GeofenceConfigSyncCoordinator.swift` — same module, same public `sync()` shape —
  the placeholder trio was deleted outright and `GeofenceConfigChangedPushHandler.handle(_:)` needed
  **zero body changes** (it already just called `syncCoordinator.sync()`). `PushRuntimeContainer`
  now takes `geofenceConfigSyncCoordinator: GeofenceConfigSyncCoordinator` as a required parameter
  and `FindlyApp.init()` passes it the exact SAME instance `LocationRuntimeContainer` builds
  (`container.geofenceConfigSyncCoordinator`, exposed `public` for this) rather than constructing a
  second, independent one — two instances would each own their own cached ETag/geofence-list read
  from the same `UserDefaults` keys and could disagree about what's current, defeating the single
  source of truth specs/009 §6.1 requires. Mirrors exactly how `settingsApplying` is already shared
  between the location and push sides.
- **Token lifecycle.** `FirebasePushTokenProvider` (app target) bridges the raw APNs device token
  (`AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` →
  `Messaging.messaging().apnsToken`) into the **FCM token** surfaced via `MessagingDelegate` — the
  FCM token, not the raw APNs token, is what `RegisterDeviceRequest.pushToken` expects (matches
  Android's model). Wired into the already-existing, already-tested `DeviceRegistrationService.
  observePushTokenRefreshes` with zero call-site change (same "swap the stub, keep the interface"
  pattern Android's `RealPushTokenProvider` used). `DeviceRegistrationService` gains
  `registerOnLaunchIfNeeded()` — the two remaining specs/004 §5 triggers (first launch after
  sign-in, every app update, keyed per-`userId` via the new `AppVersionRegistrationTracking`
  protocol, injected into `DeviceRegistrationService.init` rather than passed per-call as of I24) —
  called once at cold launch (`FindlyApp.init()`, if already signed in) and again from `RootView`'s
  `SignInViewModel.onSignedIn` completion (a session that starts at the sign-in screen).
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
- **Shared-file reconciliation with I11 (actual outcome, not the prediction):** `FindlyApp.swift`,
  `RootView.swift`, and `LocationRuntimeContainer.swift` all landed real (textual, not logical)
  merge conflicts once I11 merged — both sessions' additive composition-root wiring inserted near
  the same lines (I11's `geofenceRegistrar`/`wipeLocalState()`/`syncGeofenceConfigOnColdStart()`
  next to I12's `@UIApplicationDelegateAdaptor`/`PushRuntimeContainer`/`onSignedIn`), resolved by
  keeping both sides' additions. `RootView`'s `SignInScreen(onSignedIn:)` closure now fires BOTH
  `Task { await onSignedIn() }` (I12: push registration + device re-registration) and
  `Task { await locationRuntimeContainer.onSignedIn() }` (I11: first geofence-config sync after
  sign-in) — two independent, non-conflicting reactions to the same event.
  `LocationRuntimeContainer.swift` gains two read-only exposed properties for this reconciliation:
  `settingsApplying: DeviceSettingsApplying { settingsCoordinator }` (computed) and
  `geofenceConfigSyncCoordinator: GeofenceConfigSyncCoordinator` (widened from `private` to
  `public let`) — both exist so the app target can hand `PushRuntimeContainer` the SAME instances
  `LocationRuntimeContainer` already built, never a second independently-constructed one.
  `project.yml` gains the `FirebaseSDK` package + two target dependencies (no I11 overlap there).

**I15** adds `FindlyNotificationService`, a `UNNotificationServiceExtension` app-extension target
(specs/001-api-contract.md §8.2, specs/000-overview.md §O8), making I12's `GeofenceEventPushHandler`/
`GeofenceEventNotificationTemplate`/`SystemGeofenceEventNotifier` path actually reachable for real
`GEOFENCE_EVENT` deliveries instead of unreachable dead code (see the I12 correction above for the
root cause this fixes).

- **New target, added via `project.yml` + `xcodegen generate`, not hand-edited.** Mirrors I9's own
  rule against hand-authoring `project.pbxproj`. `type: app-extension`, `PRODUCT_BUNDLE_IDENTIFIER:
  com.findly.ios.NotificationService` (a sub-identifier under the app's own `com.findly.ios`, the
  standard app-extension convention), `NSExtensionPointIdentifier: com.apple.usernotifications.
  service` in its `Info.plist`. Depends on the `FindlyKit` package product ONLY — no Firebase SDK
  linkage, since this target never talks to FCM/APNs registration, it only receives an
  already-delivered push from the OS. Embedded into `Findly.app/PlugIns/` automatically by
  xcodegen's default behavior for an app-extension target listed as a dependency of the app target
  (no explicit `embed: true`/copy-files phase needed) — verified in the build log
  (`Copy .../Findly.app/PlugIns/FindlyNotificationService.appex`).
- **Shares the rendering logic, doesn't duplicate it.** `GeofenceEventServiceExtensionRendering.
  title(for:)` (`FindlyKit/Push/`, unit-tested) checks `PushMessageType.from(data) ==
  .geofenceEvent` (defensive — only `GEOFENCE_EVENT` ever carries `mutable-content: 1`, but a
  future message type might) and, if so, delegates straight to the existing
  `GeofenceEventNotificationTemplate.title(for:)` — the exact same template `GeofenceEventPushHandler`
  already uses on the in-app dispatch path.
- **`NotificationService.swift` (the extension target's ONLY file) is genuinely logic-free, not
  just nominally so.** Round-2 code review found its `userInfo` -> `[String: String]` bridging had
  zero coverage — `swift test` can't reach code outside the FindlyKit package, and (per the negative
  result below) `simctl push` never reaches the extension on Simulator either, so nothing exercised
  it. A direct-instantiation XCTest/Testing target for the `FindlyNotificationService` app-extension
  target was attempted first (the stronger evidence — executing the real `didReceive` override
  directly, no Simulator push pipeline needed) but hit a genuine structural wall: even with
  `BUNDLE_LOADER` pointed at the extension's own Mach-O binary inside its built `.appex` (the
  classic pre-testable-dylib pattern for linking a test bundle against another target's symbols),
  the linker reported `NotificationService`'s own methods as undefined — an app-extension
  executable doesn't retain its internal symbols for another test bundle to resolve against the way
  an app target's Xcode-managed testable dylib does. Rather than force it, the bridging conversion
  was extracted into `PushPayloadParsing.stringData(from:)` (`FindlyKit/Push/`, unit-tested, 5
  cases) and both call sites — `NotificationService` here AND `AppDelegate.application(_:
  didReceiveRemoteNotification:fetchCompletionHandler:)` (app target), which the reviewer found was
  a byte-for-byte duplicate of the same conversion — now call the one shared implementation instead
  of each keeping an inline copy. What's left in `NotificationService.didReceive` is: bridge via a
  tested function, call another tested function, conditionally set one property, invoke a closure —
  no independent logic of its own remains to test.
- **Fallback contract.** `didReceive(_:withContentHandler:)` starts `bestAttemptContent` as an
  unmodified mutable copy of the request's own content and only mutates `.title` if a title
  actually renders; both the normal completion path and `serviceExtensionTimeWillExpire()` (the
  hard OS time-budget callback) deliver whatever `bestAttemptContent` currently holds. A
  malformed/non-`GEOFENCE_EVENT` payload, or the time budget expiring before rendering completes,
  both degrade to the server's original `aps.alert.title` — never to no notification at all.
- **Verified for real on the Simulator, with an important negative result.** `xcodebuild build
  -scheme Findly -destination 'generic/platform=iOS Simulator'` succeeds and the build log shows
  `FindlyNotificationService` actually compiling (`SwiftDriver`/`CompileSwift` steps, not just an
  empty target) and its `.appex` being copied into `Findly.app/PlugIns/`; `xcrun simctl install` +
  `launch` on a real booted iPhone 17 Simulator (iOS 26.5) run cleanly, and the extension's own
  `Info.plist` (inspected inside the built `.appex`) carries the correct `CFBundleIdentifier`
  (`com.findly.ios.NotificationService`), `NSExtensionPointIdentifier`
  (`com.apple.usernotifications.service`), and `NSExtensionPrincipalClass`
  (`FindlyNotificationService.NotificationService`). **However, `xcrun simctl push` injection
  (both with the app foregrounded and with it terminated) does NOT invoke the extension on
  Simulator** — confirmed via `log show`: the pushed notification is posted directly by
  `CoreSimulatorBridge` into SpringBoard's notification datastore within milliseconds, with no
  `runningboardd`/`pkd` "Executing launch request for xpcservice..." entry for
  `com.findly.ios.NotificationService` at any point (contrasted directly against unrelated system
  extensions launched in the same log window, which DO show that exact pattern). This is a known
  iOS Simulator limitation in how `simctl push` injects notifications (it bypasses the `apsd`/
  push-delivery pipeline a Notification Service Extension actually hooks into), not a defect in
  this target — Apple's own supported way to exercise an NSE's `didReceive` locally is Xcode's GUI
  scheme-editor "Notification Payload" debug-launch feature for the extension's own scheme, which
  isn't drivable from a non-interactive CLI session. Full end-to-end confirmation (content
  genuinely re-rendered on arrival) needs either that GUI flow or a real device receiving a real
  APNs-routed push — flagged here rather than implied to have been done.
- **No entitlements, no App Group.** The extension needs neither: all the data it re-renders from
  (`displayName`, `geofenceName`, `transition`) already arrives in the push's own `data` payload —
  nothing needs to be read from or shared into app-group-scoped storage, and no capability beyond
  the extension point itself is required.
- **H6 follow-up.** A real signed/on-device build needs `com.findly.ios.NotificationService`
  registered as its own App ID in the Apple Developer portal (a sibling of the existing
  `com.findly.ios` App ID), alongside H6's other still-open portal items (Associated Domains/Push/
  App Attest activation on `com.findly.ios` itself). No new capability/entitlement needs enabling
  on it — it's a plain app-extension App ID with no special capabilities checked.

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
- **Geofencing (I11, real):** `SystemGeofenceRegistrar` wraps a dedicated `CLLocationManager` for `CLCircularRegion` monitoring, capped at `min(features.limits.maxGeofences, 20)` (000 §O9's platform ceiling). `GeofenceConfigSyncCoordinator` drives the fetch/cache/full-replace-register sequence across all five specs/009 §6.2 triggers (first sync after sign-in, two `geofenceEtag`-piggyback mismatch paths, resume from pause, cold start) — I12's `GEOFENCE_CONFIG_CHANGED` push handler shares this SAME instance rather than building its own (see the I12 section above). `GeofenceTransitionHandler` builds the durable per-transition event (`SQLiteGeofenceEventQueueStore`, same durability bar as the fix queue) and the accompanying `source: "geofence"` fix via I10's `FixCaptureCoordinator` hint seam. See the I11 section above for the full breakdown.
- **Push tokens (I12, real):** the real FCM token — bridged from APNs via `FirebasePushTokenProvider` (app target, `Messaging.messaging().apnsToken` → `MessagingDelegate`) — is registered via `PushTokenProviding` → `DeviceRegistrationService.observePushTokenRefreshes`, re-`POST /devices` on every refresh (001 §4.1, 000 §O4), plus on first launch after sign-in and every app update (`registerOnLaunchIfNeeded`, specs/004 §5).
- **Push routing (I12, real):** `PushMessageDispatcher` (`FindlyKit/Push/`) routes all four `data.type` values (001 §8) to their handlers — `LOCATE_REQUEST` (bypasses `FixCaptureCoordinator`, fulfills even while paused), `SETTINGS_CHANGED` (full-state, idempotent, into `DeviceSettingsApplying`), `GEOFENCE_EVENT` (local `UNNotificationRequest` from the push's own `data`, matching Android's title template — this path itself is still only reached when the OS invokes the app delegate directly, e.g. a data-only-shaped delivery; the *alert-carrying* `GEOFENCE_EVENT` shape's actual re-rendering now happens earlier, in the extension — see the I15 bullet below), `GEOFENCE_CONFIG_CHANGED` (ETag-conditional re-fetch, delegating to I11's `GeofenceConfigSyncCoordinator`). `AppDelegate` (app target) is pure OS-lifecycle glue reaching this dispatcher via `PushRuntimeContainerHolder`.
- **`GEOFENCE_EVENT` re-rendering, made reachable (I15, real):** the `FindlyNotificationService` `UNNotificationServiceExtension` target (specs/001 §8.2, specs/000 §O8) intercepts the push before the OS displays it and replaces `aps.alert.title` with `GeofenceEventServiceExtensionRendering.title(for:)`'s output (`FindlyKit/Push/`, unit-tested, delegates to the same `GeofenceEventNotificationTemplate` `GeofenceEventPushHandler` already used) — this is what fixes the I12-discovered dead-code path. Falls back to the server's own unmodified content on a malformed payload or on `serviceExtensionTimeWillExpire()`. See the I15 section above for the full build/verification breakdown, including the honest negative result on `simctl push` injection (Simulator's push-injection path bypasses NSEs entirely — a documented Simulator limitation, not unverified-by-omission).
- **Auth (phone-only sign-in, specs/006):** `AuthProviding` gains `startPhoneVerification(phoneNumberE164:)`/`confirmCode(_:)` and the closed `PhoneAuthError` set (006 §4.2). `StubAuthProvider` implements the two-step dev shape (006 §5) and now emits a **real** unsigned JWT — base64url JSON header/payload with an empty signature, parseable by the backend's `AUTH_MODE=insecure-local` verifier; the previous `"stub-header.…"` shape was not valid base64url JSON and never actually worked against a local backend. `SignInViewModel`/`SignInScreen` implement the 006 §4.1 state machine (phone entry → code entry, 30 s resend cooldown via an injected virtual-time-testable sleep). `FirebaseAuthProvider` (app target) is the real implementation, wired in at the `RootView` seam via `AppConfig.authMode`/`firebaseProjectId` — it compiles to an inert fallback until the Firebase SDK dependency + `GoogleService-Info.plist` land (H1) and Firebase console phone-auth setup is done (H2).
- **Offline (I10, durable):** `FixQueue` (actor, now stateless — every call delegates to `FixStoring`) — freeze-on-first-send `batchId` idempotency, batch upload per 001 §5.1. `SQLiteFixStore` (raw `SQLite3` C API, app-private `Library/Application Support/findly-fixqueue.sqlite`) persists both the fix rows *and* the frozen in-flight batch's identity, so a retry after a crash resends identical content (specs/009 §2) — proven by a test that reopens a fresh store instance against the same file and by a real on-simulator file inspection (see the I10 section above). 1 000-fix cap, oldest-pending-dropped-first, one debug-level count-only log line per drop.
- **I7 hardening (Keychain, not UserDefaults):** `FirebaseAuthProvider`'s `verificationID` — previously plaintext in `UserDefaults` (flagged non-blocking in I3's security review) — now lives behind `KeychainStoring` (`FindlyKit`, protocol + `InMemoryKeychainStore` fake) with a real `Security`-framework `KeychainStore` (app target, generic-password item, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). Storage-mechanism swap only; the verify/confirm lifecycle is unchanged.
- **I8 privacy (export/delete account/delete family, specs/004 §3.6, specs/008):** `Screens/Settings/` gains a hub (`PrivacySettingsScreen`, reachable unconditionally from Home — a store requirement, 008 §4.4) plus `ExportScreen`/`DeleteAccountScreen`/`DeleteFamilyScreen`. `FindlyAPIClient` gains `exportData(userId:)` (raw `Data`, the one unenveloped success response in the API, via a new `URLSessionAPIClient.sendRawData`), `deleteAccount()`, `deleteFamily()` (both bare-204). `AuthProviding` gains `deleteCurrentUser()` — the 008 §1.3 seam FindlyKit calls after `DELETE /users/me` returns 204; `FirebaseAuthProvider` (app target) implements it as `Auth.auth().currentUser?.delete()`, kept out of FindlyKit like the rest of the real Firebase surface. `DeleteAccountViewModel` derives the 008 §4.2 cascade-warning wording from the caller's own role/roster (last parent or sole member), orders backend-then-Firebase-then-local-wipe (`FixQueue.clearAll()` + `DeviceIdProviding.clearDeviceId` + `signOut()` for the Keychain entry), and offers a Firebase-step-only retry on failure. `DeleteFamilyScreen` layers a typed-family-name gate on top of the standard `.confirmationDialog` two-step (008 §5.4's recommended UX).
