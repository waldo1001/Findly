# 004 — iOS client

## Goal

The normative design for the native iOS app: a headless-testable **Swift Package (`FindlyKit`)** holding all logic and the design system, plus a thin SwiftUI app target that wires it to the OS. Builds against [`specs/001-api-contract.md`](001-api-contract.md) (wire contract, complete) and [`specs/002-storage-schema.md`](002-storage-schema.md) (context only — the client never talks to storage directly) and [`specs/000-overview.md`](000-overview.md) (product, esp. **§Open Items O1–O4, O9**). This spec is scoped to **I1 — foundation**: networking, auth abstraction, device registration, the offline fix-queue, navigation scaffold, one proof screen, and — the key architectural requirement — a **design-swappable UX layer**. Feature screens (map, history, geofences editor, locate, settings, invites) are **I2**, out of scope here.

---

## 1. Architecture

### 1.1 SPM-package + app-target split

```
mobile/ios/
├── FindlyKit/                  ← Swift Package, iOS 16 + macOS 13 platforms
│   ├── Package.swift
│   ├── Sources/FindlyKit/      ← ALL logic + design system (no app lifecycle code)
│   └── Tests/FindlyKitTests/   ← Swift Testing (see §9), runs via `swift test` on any host
│                                  (incl. this macOS session, headlessly — no simulator needed)
└── Findly/                ← thin SwiftUI app-target SOURCE FILES (FindlyApp.swift,
                                   RootView.swift, Info.plist, Findly.entitlements) — App
                                   lifecycle + environment wiring ONLY, zero business logic;
                                   depends on FindlyKit as a local package.
```

**No `.xcodeproj` is committed by this session.** Wrapping the sources above into an actual Xcode project is a mechanical, low-risk step *in Xcode* (File → New → Project → App, point sources at `Findly/`, add `FindlyKit` as a local Swift Package dependency) — but hand-authoring a `project.pbxproj` in a text editor, with no Xcode available to validate the result (this session has Command Line Tools only; `xcodebuild` fails with "requires Xcode" here, and there is no tool here that can validate a `.pbxproj`'s object graph beyond plist syntax), risks shipping a project file that looks plausible but doesn't actually open — worse than no project file at all. The source files themselves ARE verified: they type-check cleanly against the real built `FindlyKit` module (`swiftc -typecheck` against `FindlyKit`'s `.build` products, this session). Creating the `.xcodeproj` is deferred to whichever session first has real Xcode (H1-era or later).

**Rule (MUST):** any line of business logic, networking, persistence, or design-system code lives in `FindlyKit`. The app target MAY contain only: `@main App` struct, scene/window wiring, `Info.plist`/entitlements, and passing the OS lifecycle (scene phase, push-registration callbacks, `BGTaskScheduler` registration) into `FindlyKit` types through their public protocols. This split is what makes `swift build`/`swift test` run green on a plain macOS host with no Xcode project involved — the thing this session can actually verify.

**Platform gating (MUST):** `FindlyKit`'s `Package.swift` declares `platforms: [.iOS(.v16), .macOS(.v13)]`. Any file that imports an iOS-only framework (`CoreLocation`'s background APIs, `UIKit`, `BackgroundTasks`) MUST gate the import and the real implementation behind `#if os(iOS)` / `#if canImport(...)`, with a platform-agnostic protocol + a fake/no-op implementation available on all platforms so the package compiles and its tests run on macOS. Real device behavior (GPS fixes, background scheduling) is exercised only when the app runs on-device/in-simulator — out of scope for this session's verification, called out per-component below.

### 1.2 Module layout inside `FindlyKit`

| Folder | Owns |
|---|---|
| `Config/` | `AppConfig` — base URL, auth mode; the one place H1-dependent values are injected |
| `Networking/` | `Envelope<T>`, `APIErrorCode`, `APIErrorBody`, `JSONValue`, `FindlyAPIClient` protocol + `URLSessionAPIClient`, one file per endpoint group (`FamiliesEndpoints`, `DevicesEndpoints`, `LocationsEndpoints`, `LocateEndpoints`, `GeofencesEndpoints`) holding that group's request/response DTOs + client methods |
| `Auth/` | `AuthProviding` protocol, `StubAuthProvider` (dev), token-refresh plumbing |
| `Device/` | `DeviceIdProviding` (+ `UserDefaultsDeviceIdProvider`), `DeviceRegistrationService`, `PushTokenProviding` (+ stub) |
| `Locations/` | `LocationFix`, `FixQueue` (batch/idempotency model), `FixStoring` (+ in-memory impl) |
| `LocationSensing/` | `LocationProviding` protocol, `SystemLocationProvider` (`#if os(iOS)`), `BackgroundSyncScheduling` (`#if os(iOS) && canImport(BackgroundTasks)` — the module imports on macOS too, but `BGTaskScheduler` itself is `API_UNAVAILABLE(macos)`) — scaffolding, real GPS/BG wiring is a runtime TODO |
| `Push/` | `LocationPushTokenHandling` — scaffolding for §8.1 / 000 §O1, entitlement pending (see §5) |
| `DesignSystem/` | `Tokens/` (color, typography, spacing, corner, elevation), `Theme`, environment injection, `Components/` (stateless presentational views) |
| `Navigation/` | `AppRoute`, `AppCoordinator` |
| `Screens/` | View models + SwiftUI views composed **only** from `DesignSystem/Components` |

---

## 2. Design-system contract

The visual design MUST be fully replaceable later without touching any logic, navigation, or view-model code. This is achieved by a strict one-way dependency: `Screens` → `DesignSystem.Components` → `DesignSystem.Theme` → `DesignSystem.Tokens`. Nothing above the `DesignSystem` layer references a concrete `Color`, point size, or `Font` — only semantic token names.

### 2.1 Token vocabulary (normative — identical names to the Android client, `specs/003-android-client.md`, for one design → both platforms)

**Colors** (`ColorTokens`, one instance per scheme) — design direction **2a "Ember / Dusk"** (2026-08-06, `design/findly-design-system/2a-ember-dusk/HANDOFF.md`, superseding the 2026-07-20 teal palette below it in history); WCAG 2.1 AA verified (ratios in that handoff):

| Token | Light (default) | Dark (default) |
|---|---|---|
| `primary` | `#3A46C8` | `#7C8BFF` |
| `onPrimary` | `#FFFFFF` | `#0A0F27` |
| `secondary` | `#0E7C8F` | `#4FE3D0` |
| `surface` | `#F2F4FB` | `#0B0F1C` |
| `onSurface` | `#10142A` | `#E8ECF7` |
| `surfaceVariant` | `#E2E6F5` | `#161D33` |
| `danger` | `#B3261E` | `#FF6B6B` |
| `onDanger` | `#FFFFFF` | `#2A0708` |
| `success` | `#10714A` | `#52E39B` |
| `warning` | `#8A5A00` | `#FFC44D` |
| `outline` | `#A9B0CE` (2.1:1 — **decorative hairlines/dividers only**) | `#3A4463` (**also decorative only — see correction below**) |

Two rules the handoff calls out explicitly and review checks, **both corrected post-review** (independently verified 2026-08-06, WebAIM formula sanity-checked against `#767676`-on-`#FFFFFF` = 4.54:1; both were errors in the handoff document itself):

1. Light `outline` is 2.1:1 and legal only for decorative hairlines/dividers. Any stroke that carries meaning (unselected control border, focus ring, input outline) uses `theme.outlineStrong` (`#6B739A`, 3.4:1-class) instead. **Correction:** the handoff claims dark `outline` (`#3A4463`) "clears 3:1" and can double for both purposes — measured, it does not (1.99:1 vs dark `surface` `#0B0F1C`, 1.74:1 vs `surfaceVariant` `#161D33`). Dark therefore uses the SAME `#6B739A` as light for meaningful strokes (4.13:1 vs `surface`, 3.61:1 vs `surfaceVariant` — both clear 3:1); dark `outline` itself stays decorative-only, same as light.
2. The dot inside a `primary` marker bubble's "● NOW" pill is `Color.findlyMarkerOnlineDot` (`#52E39B`) — light-theme `success` (`#10714A`) measures 1.2:1 there and must never be used for it. **Correction:** the handoff claims `#52E39B` is "5.4:1 in both themes" against `primary` — independently remeasured at 4.44:1 against LIGHT `primary` (`#3A46C8`; the handoff's number was also slightly off) but only 1.83:1 against DARK `primary` (`#7C8BFF`), which fails. Dark inverts the badge instead of reusing light's fill/label pairing: fill `#0B3B26` (vs dark `primary` = 4.19:1), label `#52E39B` (on that fill = 7.69:1). See `Theme.markerOnlineBadgeFill`/`Label`.

**Typography** (`TypographyTokens`, a `TypeStyle { size: CGFloat, weight: Font.Weight, lineHeight: CGFloat, tracking: CGFloat }` per role, identical across schemes — pt on iOS, system font only):

| Role | Size (pt) | Weight | Line height | Tracking |
|---|---|---|---|---|
| `displayLarge` | 34 | bold | 40 | −0.4 |
| `titleLarge` | 24 | bold | 30 | −0.2 |
| `titleMedium` | 18 | semibold | 24 | 0 |
| `bodyLarge` | 17 | regular | 24 | 0 |
| `bodyMedium` | 15 | regular | 20 | 0 |
| `labelSmall` | 12 | bold, uppercase | 16 | +0.4 |

Any elapsed-time or code value uses tabular figures (`.monospacedDigit()`).

**Spacing** (`SpacingTokens`, `CGFloat` points): `xs=4, sm=8, md=12, lg=20, xl=28, xxl=40`.

**Corner radius** (`CornerRadiusTokens`, `CGFloat` points): `sm=12, md=20, lg=28, pill=999` (pill = always fully rounded regardless of view height).

**Elevation** (`ElevationTokens`, a shadow spec per level, resolved per scheme like colors — SwiftUI has no native elevation, so each level is `{ blur: CGFloat, y: CGFloat, opacity: Double, color: Color }`; color is neutral black at every level unless a component explicitly documents a tinted override, e.g. `FindlyButton`'s primary style): `level0 = {0,0,0,black}`; `level1 = {8,2,0.10|0.30,black}`; `level2 = {24,8,0.14|0.45,black}`; `level3 = {48,16,0.18|0.60,black}` (opacity given as light|dark — blur/y/color are scheme-independent, only opacity differs).

### 2.2 `Theme` and injection

```swift
public struct Theme: Equatable {
    public var colors: ColorTokens
    public var typography: TypographyTokens
    public var spacing: SpacingTokens
    public var corner: CornerRadiusTokens
    public var elevation: ElevationTokens
    public static let light = Theme(colors: .light, typography: .standard, spacing: .standard, corner: .standard, elevation: .standard)
    public static let dark  = Theme(colors: .dark,  typography: .standard, spacing: .standard, corner: .standard, elevation: .standard)
}
```

Injected via a custom `EnvironmentKey` (`\.theme`), defaulting to `.light`; the app target's root view resolves `.light`/`.dark` from the SwiftUI `colorScheme` environment value and sets `\.theme` once at the root — no component below the root ever reads `colorScheme` directly. **MUST** ship both `Theme.light` and `Theme.dark` from day one.

### 2.3 Components (stateless, presentational, `DesignSystem/Components/`)

`FindlyButton` (primary/secondary style), `FindlyCard`, `FindlyListRow`, `StatusChip` (e.g. online/stale/paused), `MapMarkerBubble`, `FindlyNavBar`, `EmptyStateView`, `LoadingStateView`, `ErrorStateView`, plus two I2 additions needed by the feature-screen forms: `FindlyTextField` (a labeled single-line text input) and `FindlyToggleRow` (a label/subtitle row with a trailing themed toggle, e.g. device pause/`trackingEnabled`, geofence `notifyOnEnter`/`notifyOnExit`). Each:

- Reads `@Environment(\.theme)` only — **MUST NOT** declare a literal `Color(...)`, `.font(.system(size:))`, or hardcoded point size.
- Takes content/state via parameters (strings, an enum for chip status, a boolean for loading, etc.) — zero knowledge of view models, networking, or navigation.
- SHOULD ship a light + dark `#Preview` pair under Xcode. **Not present in this session's committed source**: `#Preview` needs the `PreviewsMacros` compiler plugin, which ships only with `Xcode.app` — this session has Command Line Tools only, where even an empty `#Preview {}` fails to compile, and the package MUST build clean here. Adding previews back is a trivial, non-blocking follow-up once a real Xcode toolchain is available.

### 2.4 Screens

Screens (`Screens/*/*.swift`) compose `DesignSystem.Components` and read state from an `ObservableObject` view model. View models contain **zero** styling — no `Color`, `Font`, or SwiftUI layout modifiers beyond what a generic container view needs; they expose plain state (strings, enums, booleans) that components render. This seam is what lets a future design pass replace every file under `DesignSystem/` without touching `Screens/`, `Navigation/`, `Networking/`, `Auth/`, `Device/`, or `Locations/`.

### 2.5 Navigation model — the back stack (normative)

**The problem this section exists to prevent.** `AppCoordinator` originally held a *single* `@Published var route: AppRoute`, and `RootView` `switch`ed on it to swap the whole view. That is not a navigation model — it is a router with no history. iOS has no hardware back button, so every screen reached that way was a **dead end**: the user could enter `.geofences`/`.liveMap`/`.history`/`.privacySettings`/`.deviceSettings`/`.familyMembers`/`.createInvite`/`.exportData` and had no way back short of killing the app. Only the handful of screens with a terminal callback (`onExit`/`onCreated`/`onCompleted`) could return, and they did so by *replacing* the route, not popping. Found on the first real TestFlight install, 2026-08-05.

**Rule (MUST): `AppCoordinator` owns a stack, not a route.**

- Internally the coordinator holds a non-empty `[AppRoute]`. `route` remains the public read-only accessor for the **top** of the stack, so existing call sites and tests keep working unchanged.
- Every `showX()` method **pushes**. Pushing the route already on top is a no-op (idempotent — a double tap must not stack duplicates).
- `pop()` removes the top entry and MUST be a **no-op at the root** (the stack never empties).
- `canGoBack` is `true` iff the stack holds more than one entry. This is the single source of truth the UI reads to decide whether to show a back affordance — no screen decides this for itself.
- **Root replacements, not pushes:** `showSignIn()` and `showHome()` **reset** the stack to exactly `[.signIn]` / `[.home]`. These are the two navigation roots; you can never go "back" *into* a sign-in screen, and Home is the top of the app. This is also what makes the post-sign-out and post-account-deletion paths land on a stack with no stale authenticated screens behind them (a real data-leak concern, not just cosmetics — specs/008 §4.4).
- `handleDeepLink` **pushes** `.groupJoin` onto the existing stack when the app is already running, so dismissing a deep-linked join screen returns the user where they were. On a cold start the stack root is whatever §2.6 selected, so back from a deep link always has somewhere to land.

**Rule (MUST): modally-presented views clear the back action.** A `.sheet`/`.fullScreenCover` is not part of the navigation stack, but SwiftUI *does* propagate custom environment values into presented content — so a modal that renders a `FindlyNavBar` inherits the app-level back action and would navigate the app **behind** a sheet that stays open. Any modal root MUST therefore set `.environment(\.navBarBackAction, nil)`; its own explicit Cancel/Save controls are its only dismissal.

**Rule (MUST): the back affordance is rendered once, centrally.** `RootView` renders it above the switched-on screen content, driven solely by `coordinator.canGoBack`. Individual screens MUST NOT each grow their own back button — that is what produced 20 screens with 20 different (or absent) answers. `FindlyNavBar` therefore takes an optional `onBack` closure and renders a themed, `.accessibilityLabel("Back")` control when one is supplied.

**Terminal callbacks vs. back.** A screen's own completion callback (`onCreated`, `onCompleted`, `onExit`) expresses *where the flow ends*, which is not always "one screen back". Back is strictly "undo the last push"; a completion callback that means "this flow is over, return to the screen that started it" MUST use `popTo(_:)` — the counterpart to Android's `popBackStack(route, inclusive = false)` — which unwinds to the **existing** stack entry. Pushing the destination instead would leave the just-finished screen sitting *behind* it, so back would walk into a group the user has already left or a family they just deleted. When the target isn't on the stack at all (reachable when a cold-start deep link opened the flow directly), `popTo` rebuilds a minimal sane stack under it rather than stranding the user on a finished screen.

### 2.6 Launch route — session restore (normative)

**The problem this section exists to prevent.** `AppCoordinator`'s launch route was hardcoded to `.signIn`, and nothing at launch ever consulted `AuthProviding`. Firebase Auth **does** persist its session across launches (its keychain-backed `currentUser` survives process death), so the session was in fact restored — the app simply never asked, and forced a full SMS re-verification on every cold start. The same file's cold-launch device-registration closure already guarded on `authProvider.currentUserId != nil`, proving the restored session was observable at that exact point. Found on the first real TestFlight install, 2026-08-05.

**Rule (SHOULD): avoid touching `FirebaseAuth` during `FindlyApp.init()`.** Deferring the session read costs nothing and keeps `App.init()` free of SDK initialization order hazards.

> **Correction (2026-08-05).** An earlier revision of this section asserted that reading `currentUserId` in `App.init()` *caused* the launch crash in build 5, by making Firebase's `protectedDataInitialization()` fail its reflective `UIApplication.shared` lookup and leave `tokenManager` nil. **That attribution was wrong and is retracted.** The crash was reproduced identically with the early read removed. The real cause was an unguarded manual APNs-token forward in `AppDelegate` — see specs/004 §5 and the `AppDelegate` comment. The deferral is retained on its own merits (no sign-in flash, no early SDK construction), not as a crash fix.

**Rule (MUST):** the launch route is resolved **after** the UI exists, not during `App.init()`:

- The coordinator's stack starts at **`.launching`**, a neutral route rendering a themed splash — never `.signIn`, so a returning user never sees a sign-in screen flash before being restored.
- `RootView` resolves it on first appear (`.task`), by which point `UIApplication.shared` genuinely exists: `authProvider.currentUserId != nil` → `.home`, otherwise → `.signIn`. Resolution replaces the stack root; `.launching` is never returned to and never appears behind a back button.
- The cold-launch device/push registration (`onSignedIn`) moves to the same place, for the same reason — it reads `currentUserId` too.
- `FindlyApp.init()` MAY still call `FirebaseAuthProvider.configureFirebaseIfNeeded()`, which touches `FirebaseApp` only and constructs no `Auth` instance.

A restored session MUST NOT re-prompt for SMS verification. Sign-in is reached on a cold start only when there is genuinely no persisted user. Token *expiry* is a separate, already-specified concern: the client refreshes via `refreshIDToken()`, and only a second `AUTH_TOKEN_EXPIRED` forces sign-out (specs/009 §9) — an expired token at launch is a refresh, never an immediate bounce to sign-in.

---

## 3. Networking — full 001 client

`URLSession` + `Codable`, `async`/`await`. One `FindlyAPIClient` protocol (mockable in tests) + `URLSessionAPIClient` (real). Every call sets `Authorization: Bearer <token>` (from `AuthProviding`) and `Content-Type: application/json; charset=utf-8`; device-originated calls additionally set `X-Device-Id` (§1.2 of 001). Base URL from `AppConfig` (§6).

### 3.1 Envelope & error decoding

```swift
public struct Envelope<T: Decodable>: Decodable { public let data: T; public let features: Features }
public struct APIErrorBody: Decodable { public let code: APIErrorCode; public let message: String
                                          public let details: [String: JSONValue]?; public let requestId: String }
public struct APIErrorEnvelope: Decodable { public let error: APIErrorBody }
```

`APIErrorCode` is a `String`-backed enum with one case per 001 §10 row (27 codes, incl. the six group-era ones: `PROFILE_NOT_FOUND`, `GROUP_NOT_FOUND`, `GROUP_EXPIRED`, `GROUP_CODE_INVALID`, `GROUP_ALREADY_MEMBER`, `GROUP_FULL`) **plus** `case unknown(String)` as a forward-compatible fallback (defensive only — 001 states codes come solely from the catalog; `unknown` never occurs against a conforming server but protects the client against additive server-side codes shipping before the client updates). `Features`/`PlanLimits`/`PlanFlags` mirror 001 §9 exactly (incl. the group limits and `flags.groups`).

### 3.2 Endpoint → client method mapping (complete — every row of 001 §1.6)

| 001 § | Method & path | `FindlyAPIClient` method |
|---|---|---|
| 3.1 | `POST /families` | `createFamily(familyName:displayName:)` |
| 3.2 | `GET /families/me` | `getMyFamily()` |
| 3.3 | `POST /families/me/invites` | `createInvite(role:emailHint:)` |
| 3.4 | `POST /invites/accept` | `acceptInvite(inviteCode:displayName:)` |
| 3.5 | `PATCH /families/me/members/{userId}` | `updateMember(userId:role:displayName:)` |
| 3.6 | `DELETE /families/me/members/{userId}` | `removeMember(userId:)` → `Void` (204, no envelope) |
| 4.1 | `POST /devices` | `registerDevice(_:RegisterDeviceRequest)` |
| 4.2 | `GET /devices` | `listDevices()` |
| 4.3 | `PATCH /devices/{deviceId}` | `updateDevice(deviceId:_:UpdateDeviceRequest)` |
| 5.1 | `POST /locations` | `reportLocations(batchId:fixes:)` |
| 5.2 | `GET /locations/latest` | `getLatestLocations()` |
| 5.3 | `GET /locations/history` | `getLocationHistory(userId:deviceId:from:to:limit:cursor:)` |
| 6.1 | `POST /locate-requests` | `createLocateRequest(target:)` (`target` = `.user(String)` \| `.device(String)`) |
| 6.2 | `GET /locate-requests/{requestId}` | `pollLocateRequest(requestId:)` |
| 6.3 | `POST /locate-requests/{requestId}/fulfill` | `fulfillLocateRequest(requestId:fix:)` |
| 7.1 | `GET /geofences` | `getGeofences(ifNoneMatch:)` → `.notModified` \| `.ok(GeofenceConfig, etag:)` |
| 7.2 | `PUT /geofences` | `replaceGeofences(_:ifMatch:)` → `(config:, etag:)` — the new ETag response header, cached for the next `getGeofences` |
| 7.3 | `POST /geofence-events` | `reportGeofenceEvents(_:)` |
| 7.4 | `GET /geofence-events` | `getGeofenceEventHistory(from:to:userId:limit:cursor:)` |
| 12.1 | `POST /groups` | `createGroup(name:endsAt:expiryPolicy:displayName:)` |
| 12.2 | `GET /groups` | `listGroups()` |
| 12.3 | `GET /groups/{groupId}` | `getGroup(groupId:)` |
| 12.4 | `PATCH /groups/{groupId}` | `updateGroup(groupId:name:endsAt:)` |
| 12.5 | `DELETE /groups/{groupId}` | `deleteGroup(groupId:)` → `Void` (204, no envelope — as 3.6) |
| 12.6 | `POST /groups/join` | `joinGroup(code:displayName:)` |
| 12.7 | `POST /groups/{groupId}/code/rotate` | `rotateGroupCode(groupId:)` |
| 12.8 | `POST /groups/{groupId}/leave` | `leaveGroup(groupId:)` → `Void` (204) |
| 12.9 | `DELETE /groups/{groupId}/members/{userId}` | `removeGroupMember(groupId:userId:)` → `Void` (204) |
| 12.10 | `GET /groups/{groupId}/locations/latest` | `getGroupLatestLocations(groupId:)` |

### 3.4 Groups screens (specs/005; wire shapes 001 §12)

Screen inventory and behavior mirror the Android spec **exactly** — see [003 §12.2](003-android-client.md) (groups list = family-less home, create sheet with the 005 §2.1 policy copy, detail + share-sheet code + owner controls per the 005 §2.3 state matrix, join with code entry, group map through the existing map seam, position-only markers). iOS specifics: new `AppRoute` cases (`groups`, `groupDetail`, `groupJoin`, `groupMap`) in `AppCoordinator`; the `findly://group-join?code=…` deep link is parsed **in FindlyKit** (pure, testable — same as the invites deep-link validation) and forwarded by the app target's `onOpenURL`; group DTOs carry no battery/device fields, by construction.

All request/response field names match 001 verbatim (`camelCase`, identical keys). `syncIntervalMinutes` request validation (allowed set, floor) is **not** duplicated client-side beyond what the UI needs for a sane picker (I2 concern) — the server is the source of truth; the client surfaces `VALIDATION_FAILED`/`LIMIT_EXCEEDED` as returned.

### 3.5 Public join links & QR ([007](007-public-join-links.md))

- `AppConfig` (§8) gains **`joinLinkHost`** — the 007 §1 deployment constant (recorded at H4).
- **Associated Domains** entitlement `applinks:{JOIN_LINK_HOST}` on the app target — requires a paid Apple Developer membership: **prepared now, activated at H6** (the AASA file's `{TEAMID}.{bundleId}` appID is likewise completed server-side at H6, 007 §3 — no app change needed then).
- SwiftUI delivers universal links through the existing `.onOpenURL`; `GroupCodeParsing` (FindlyKit, pure/testable) gains the https form — `{JOIN_LINK_HOST}` host + `/g` path + **fragment-carried code** (007 §1), same charset whitelist and hyphen tolerance as the `findly://` form; wrong host/path rejected; valid link without a usable fragment routes to `GroupJoinScreen` with an empty prefill.
- Sharing: `ShareLink` switches to the 007 §1 https link; the detail screen renders a **QR of that link generated on-device** (CoreImage `CIQRCodeGenerator` — never a networked QR service, 007 §4). The `findly://` deep link stays supported.

### 3.6 Privacy: export & account deletion ([008](008-privacy-endpoints.md); wire shapes 001 §13)

Screen inventory and behavior mirror the Android spec **exactly** — see [003 §12.4](003-android-client.md) (settings entries for export / delete account / delete family; two-step confirmations incl. the last-parent cascade wording; family-name typing on family delete; `FAMILY_NOT_FOUND` lands on the existing family-less home). iOS specifics:

- The three 001 §13 calls extend the §3.2 client mapping in FindlyKit. `GET /export` is the one **unenveloped** response (001 §13.1): the client method returns raw `Data` (never decoded through the §3.1 envelope path) handed to a `ShareLink`/document exporter; `.confirmationDialog` is the confirmation surface (the I5-established pattern).
- After `DELETE /users/me` returns `204`: `Auth.auth().currentUser?.delete()` (008 §1.3). On failure follow 008 §1.3's **sign out → sign in → re-run delete** recovery — a bare retry is a trap, since `requires-recent-login` never clears by retrying — with the sign-out action reachable from the failure state itself. On success wipe all local state: fix queue, cached ETags, `deviceId`, the Keychain entries written by I7's `KeychainStore` (removed explicitly, **not** left to `signOut()`'s internal ordering — if `signOut()` throws, the entry survives), and the **export artifacts of 008 §3.1**.
- Test checklist additions (§10 applies): confirmation gating, cascade wording trigger, Firebase-delete ordering + failure/retry, Keychain/local wipe completeness, raw-`Data` export path bypassing envelope decoding, `exportsPerDay` message mapping.

### 3.3 Token-expiry retry (001 §2.1)

`URLSessionAPIClient` catches a decoded `AUTH_TOKEN_EXPIRED` error, calls `authProvider.refreshIDToken()`, and retries the **same** request exactly once; a second `AUTH_TOKEN_EXPIRED` propagates to the caller. This is orthogonal to §4 below (which reacts to the **push**-token refreshing, not the Firebase ID token).

---

## 4. Auth abstraction — phone-number sign-in (specs/006)

Sign-in is **phone-number-only** (SMS OTP): flow, state machine, E.164 normalization, and the error/message catalog are normative in [`specs/006-phone-auth.md`](006-phone-auth.md) §3–§5; this section owns the iOS shapes.

```swift
public protocol AuthProviding: AnyObject {
    var currentUserId: String? { get }
    func currentIDToken() async throws -> String
    func refreshIDToken() async throws -> String
    func signOut() throws
    /// Starts SMS verification for the (already 006 §3-normalized) number.
    /// Re-calling with the same number = resend. The verification session is
    /// provider-internal. Throws PhoneAuthError.
    func startPhoneVerification(phoneNumberE164: String) async throws
    /// Confirms the code for the in-flight verification; on success currentUserId != nil.
    func confirmCode(_ code: String) async throws
}

// The closed error set of 006 §4.2; messages in PhoneAuthUserMessage (pure, FindlyKit)
public enum PhoneAuthError: Error, Equatable {
    case invalidPhoneNumber, tooManyRequests, smsQuotaExceeded,
         appVerificationFailed, invalidCode, codeExpired, network, unknown
}
```

iOS has no instant verification, so plain `async` methods suffice — no event stream (the Android `Flow` shape, 003 §7, is not mirrored). `PhoneNumberNormalizer` (pure, FindlyKit) implements 006 §3 with rules identical to Android's.

`StubAuthProvider` (dev, `AuthMode == .stubLocal`) implements the two-step phone shape per 006 §5: `startPhoneVerification` records the normalized number; `confirmCode` accepts any non-blank code and sets `currentUserId = <normalized E.164 number>`. Its token is corrected to a **real unsigned JWT** — base64url JSON header/payload carrying `iss`/`aud`/`sub`/`iat`/`exp` (`sub` = the E.164 uid) with an empty signature, like Android's `DevAuthProvider` — because the previous `"stub-header.…"` shape cannot be parsed by the backend's `AUTH_MODE=insecure-local` verifier (its payload isn't base64url JSON), so the iOS dev build never actually worked against a local backend. The fake `iss`/`aud` come from `AppConfig.firebaseProjectId` (§8).

### 4.1 Phone sign-in flow

- **`FirebaseAuthProvider` — the first real `AuthProviding` implementation — lives in the app target (`Findly/`), not FindlyKit**, keeping FindlyKit Firebase-SDK-free so `swift test` keeps running headless on macOS. It is swapped in at the existing composition-root seam (`RootView`, `AuthMode == .firebase`). Internals: `PhoneAuthProvider.provider().verifyPhoneNumber(_:uiDelegate:nil)` → store the `verificationID` (in-memory + `UserDefaults`, per Firebase guidance — the app may be backgrounded while the SMS arrives); `confirmCode` → `PhoneAuthProvider.provider().credential(withVerificationID:verificationCode:)` + `Auth.auth().signIn(with:)`. SDK failures map onto `PhoneAuthError` per the 006 §4.2 table; raw SDK text never reaches a screen.
- **APNs is a phone-auth prerequisite (006 §6.6):** Firebase verifies the iOS app via **silent APNs push** — requires the Push Notifications capability + remote-notification background mode on the app target, the APNs auth key uploaded to Firebase, and thin app-delegate forwarding (`Auth.auth().setAPNSToken(_:type:)`, `Auth.auth().canHandleNotification(_:)`) — app-target lifecycle wiring, allowed by §1.1's rule. **Fallback:** without APNs (simulator; key not yet uploaded) Firebase falls back to reCAPTCHA in a web sheet, which requires the `REVERSED_CLIENT_ID` custom URL scheme in Info.plist plus `Auth.auth().canHandle(url)`. Dev/E2E on the simulator uses **Firebase test phone numbers** (006 §6.4), which need neither.
- **`SignInViewModel`** implements the 006 §4.1 state machine (minus the Android-only instant-verification arrows), with a 30 s resend cooldown driven by injected virtual-time-testable ticking:

```swift
public enum SignInState: Equatable {
    case enteringPhone(error: String?)
    case sendingCode(phone: String)
    case enteringCode(phone: String, resendSecondsLeft: Int, error: String?)
    case confirmingCode(phone: String)
    case signedIn(userId: String)
}
```

  (`signedIn` is kept — iOS navigates via the existing `onSignedIn` callback from `RootView`, unlike Android's authState-observing nav.) `SignInScreen` renders phone entry or code entry from the state using existing components (`FindlyTextField`, `FindlyButton`, `ErrorStateView`) — one screen, two steps.

**Push-token refresh → re-registration (001 §4.1, 000 §O4):** `PushTokenProviding` exposes an `AsyncStream<String>` of push-token values (FCM/APNs token). `DeviceRegistrationService` subscribes and calls `POST /devices` with the new `pushToken` on every emission — this is what satisfies "re-`POST /devices` on token refresh"; it is **not** triggered by Firebase ID-token refresh (that's §3.3's concern, a different token, a different reason).

---

## 5. Device registration (001 §4.1)

`DeviceIdProviding` persists a client-generated **UUIDv4** `deviceId` keyed by `currentUserId`, generating a **fresh** id whenever the signed-in user changes (001 §1.4: "clients MUST generate a fresh `deviceId` when the signed-in user changes"). `DeviceRegistrationService.registerOrUpdate()` builds a `RegisterDeviceRequest{ deviceId, platform: "ios", model, appVersion, pushToken?, locationPushToken?, deviceName? }` from `DeviceIdProviding` + `UIDevice`/`Bundle` info (gated `#if canImport(UIKit)`, with a fake device-info source for macOS/test builds) and calls `registerDevice`. Triggers (MUST, per 001 §4.1 + the task's runtime wiring, executed by the app target through `FindlyKit`'s public API): first launch after sign-in; every push-token refresh (§4); every app update (compare stored vs. running `appVersion`).

Push tokens are **write-only** (never read back, 001 §4.1/§4.2) — `FindlyKit`'s `Device` response models simply have no `pushToken`/`locationPushToken` fields, by construction, not by filtering.

---

## 6. Offline fix-queue & `batchId` idempotency (001 §5.1)

`FixQueue` (an `actor`, so concurrent enqueue-from-CoreLocation-callback and send-from-background-task are race-free) models the exact rules of 001 §5.1 and 000 §D7:

- **Freeze-on-first-send:** `nextBatchToSend(maxBatchSize: 100)` either returns the **existing in-flight `PendingBatch`** (a retry — same `batchId`, same frozen `fixes`) or, if none is in-flight, freezes up to 100 queued fixes into a **new** `PendingBatch` with a fresh UUIDv4 `batchId` and holds it as in-flight. Fixes recorded after freezing are never added to that batch — they wait for the next one (queue > 100 splits across multiple sequential batches, oldest first).
- **Transient failure** (network error, 5xx): `handleTransientFailure()` — the in-flight batch is kept **unchanged** for the next retry (same `batchId`, identical content, satisfying "retries MUST resend identical content under the same `batchId`").
- **Accepted (2xx, incl. a duplicate-replay 200):** `handleAccepted(batchId:)` — the batch's fixes are permanently removed from the queue; in-flight cleared.
- **Definitive rejection (any 4xx):** `handleDefinitiveRejection(batchId:, dropFixIds:)` — per 001 §5.1 ("no marker was written — the batch is dead"), the offending fixes are dropped (`details.fields`-identified ones, or the whole batch if the client can't map fields) and in-flight is cleared; the **remaining** fixes get a **new** `batchId` on the next `nextBatchToSend` call, never the dead one.
- **Persistence:** `FixStoring` protocol abstracts the queue's backing store; I1 ships `InMemoryFixStore` only — a Core Data/SQLite-backed store is a runtime TODO for the on-device build (not required for `swift test`, which exercises the queue's rules against the in-memory store).

---

## 7. Location & push-to-locate strategy (000 §O1, §O2, §O3; 001 §5–§6, §8)

> The on-device runtime contract — the three opportunistic iOS triggers (`BGAppRefreshTask`, significant-location-change, geofence transitions) and the `× 0.8` elapsed-time rule, the durable Core Data/SQLite queue replacing §6's in-memory store, push routing, region-monitoring lifecycle, and the When-In-Use → Always staging — is normative in **[009](009-device-runtime.md)** (tasks I10–I12). The scaffolding described below is what those tasks replace.


- **Sync:** `LocationProviding` protocol (foreground high-accuracy fix + background significant-change monitoring); `SystemLocationProvider` (`#if os(iOS)`) wraps `CLLocationManager` with staged authorization (When-In-Use → Always upgrade prompt) — implementation body is scaffolded with `// TODO(I2 or on-device session):` markers for the actual `CLLocationManagerDelegate` wiring, since it cannot be exercised without a device/simulator. `BackgroundSyncScheduling` (`#if os(iOS) && canImport(BackgroundTasks)`) scaffolds `BGAppRefreshTask` registration the same way. Both conform to protocols with fully-tested fakes so `FixQueue`/`DeviceRegistrationService` consumers are unit-testable without either framework.
- **Interval honesty (000 §O2):** the UI (I2) must present the configured interval as a *target*; this spec's models carry `syncIntervalMinutes` verbatim from the server — no client-side reinterpretation.
- **"1 day" interval (000 §O3):** scheduling semantics (first opportunistic fix per device-local calendar day) belong to the on-device scheduler (I2/runtime), not to any I1 type; noted here so the eventual scheduler implementation has a normative pointer.
- **Push-to-locate reliability (000 §O1 — the #1 platform risk):** `LocationPushTokenHandling` scaffolds capture of the APNs Location Push token (`CLLocationManager.startMonitoringLocationPushes`, `#if os(iOS)`) and its plumbing into `RegisterDeviceRequest.locationPushToken` (§5 above) — the token is captured and sent the moment it's available, exactly like `pushToken`. **The `com.apple.developer.location.push` entitlement itself is a human/Apple-account action** (Apple Developer Program enrollment, $99/yr, then a formal entitlement request) — **apply immediately**; it is explicitly **not** blocking I1/I2 coding. Until granted, the client relies on the FCM data-only `LOCATE_REQUEST` push (001 §8.1) exactly as normatively specified, with UI (I2) falling back to "last known, updating…" per 000 §O1. The Location Push Service Extension **target** itself (a second app extension target using the entitlement) is not created in I1 — it has no code to write until the entitlement exists; adding it later is purely additive (a new Xcode target, no changes to `FindlyKit`).
- **Geofencing (000 §O9):** out of scope for I1 (I2 builds the editor + `CLCircularRegion` registration); `FindlyKit`'s `GeofencesEndpoints` client methods exist now so I2 has them ready.

---

## 8. Config & H1-dependent stubbing

```swift
public struct AppConfig {
    public var baseURL: URL             // default: a placeholder, non-resolving host — see below
    public var authMode: AuthMode       // .stubLocal (default) | .firebase
    public var firebaseProjectId: String // dev default fine — feeds StubAuthProvider's fake iss/aud (§4)
}
public enum AuthMode { case stubLocal, firebase }
```

Default `baseURL` is `https://api.findly.invalid/api/v1` — the `.invalid` TLD (RFC 2606) makes it obviously non-resolving and non-real, so no third-party/production host is ever hardcoded. H1 supplies the real Azure Functions base URL (and a `.firebase` `AuthMode` backed by `FirebaseAuthProvider`) via the app target's build configuration (e.g. an `.xcconfig` per environment) — no `FindlyKit` code changes. `GoogleService-Info.plist` stays **absent and gitignored** (already covered by `mobile/ios/.gitignore`) until H1; the app target's Firebase SDK integration itself is also an H1 follow-up (adding the SDK now, with no config file, would crash at launch).

---

## 9. Testing strategy

**Framework note (environment-driven, decided this session):** `Tests/FindlyKitTests/` uses **Swift Testing** (`import Testing`, `@Test`, `#expect`) rather than XCTest. This session's host has only Xcode Command Line Tools installed (no `Xcode.app`), and no `XCTest.framework` exists anywhere on it — `import XCTest` cannot compile here. `Testing.framework` (Swift Testing, XCTest's first-party successor, part of the Swift toolchain since Swift 6) IS present under the Command Line Tools install, but `swift test` doesn't add its framework/plugin search paths automatically in a CLT-only setup; `FindlyKit/Package.swift`'s `FindlyKitTests` target pins them explicitly via `unsafeFlags` (harmless on a full-Xcode host, where these exact paths won't exist and are simply unused) so plain `swift test` works everywhere, including this session. On a full Xcode install (H1-era CI, `macos-14` runners) either framework works fine; Swift Testing was chosen because it is what this session could actually run and verify.

Runs via `swift test` on any host (this session: macOS, headless, no simulator). Coverage (see §10 checklist for the full list): envelope success/error decoding; all 27 `APIErrorCode` cases decode to their case (plus one forward-compat `unknown` case); request-building for every one of the 29 methods in §3.2 (URL, HTTP method, headers incl. `X-Device-Id` only where required, JSON body shape); device-registration request construction (first-registration defaults are the server's job, but the client's *request* omits fields it doesn't have, and never sends role/entitlement data); `FixQueue` batch/idempotency behavior (freeze, retry-same-id, split >100, definitive-rejection new-id, transient-failure same-id); token-refresh triggers (push-token refresh ⇒ re-register call recorded; `AUTH_TOKEN_EXPIRED` ⇒ refresh + retry-once observed on a mock client); design-system `Theme` (light/dark both defined, all token fields present); `SignInViewModel` state transitions per the 006 §4.1 machine (§4.1) against a fake `AuthProviding`. The Xcode app-target build (and any `xcodebuild`/simulator run) is explicitly **not** part of this session's verification — noted, not attempted, since only Command Line Tools (no Xcode.app) are present here.

---

## 10. Test checklist

- `Envelope<T>` decodes `{data,features}`; `APIErrorEnvelope` decodes `{error:{code,message,details,requestId}}`.
- Every one of the 27 `APIErrorCode` catalog values round-trips through decoding; an unrecognized string decodes to `.unknown`.
- One request-building test per §3.2 row (29 methods) asserting method, path, headers, and body against a 001 example.
- `X-Device-Id` header present only on `reportLocations`, `reportGeofenceEvents`, `fulfillLocateRequest`; absent elsewhere.
- The bare-`204` methods (`removeMember`, `deleteGroup`, `leaveGroup`, `removeGroupMember`) and a `304` `getGeofences` response are handled without attempting envelope decode.
- Groups (005 §7 client side): view-model logic for list/create/join/detail/map against a fake client — state chips from `state`, countdown from `endsAt`, 005 §2.1 policy copy shown at create, `findly://group-join` deep-link parsing (valid/invalid/rotated-code shapes), grace/archived rendering per the 005 §2.3 matrix; group DTOs contain no battery/device fields.
- `DeviceIdProviding` issues a stable id per user and a fresh one when the user changes.
- `DeviceRegistrationService` builds a request with `platform: "ios"` and omits absent optional token fields (never sends empty-string tokens).
- `FixQueue`: enqueue→freeze→same-batch-on-retry; accept clears queue; definitive rejection drops + issues new id on next send; queue > 100 splits into sequential batches.
- Push-token refresh triggers exactly one `registerDevice` call with the new token; ID-token expiry triggers exactly one refresh + one retry, not a device re-registration.
- `Theme.light` and `Theme.dark` both populate every token in §2.1; components read only `\.theme` (spot-checked by a components test asserting no direct `Color(...)` literal type is reachable — enforced by code review, not automatable in XCTest, so this is a review-gate item, not a test).
- Phone sign-in (006 §10, iOS side): `PhoneNumberNormalizer` covers every 006 §3 rule; `SignInViewModel` covers every 006 §4.1 transition (minus Android-only instant verification) against a fake `AuthProviding` — happy path, every `PhoneAuthError` landing in its specced state/message, resend blocked until the cooldown hits 0 then exactly one re-invocation, `.invalidCode` staying on code entry vs `.codeExpired` returning to phone entry; `StubAuthProvider` two-step shape + unsigned-JWT token whose payload parses as base64url JSON with `sub` = the E.164 uid; no test imports the Firebase SDK.

## 11. Open questions

None — ambiguities in 001/000 relevant to this client (O1–O4, O9) have normative v1 behavior already; anything left (real `CLLocationManager`/`BGTaskScheduler` wiring, the Location Push extension target, feature screens) is explicitly deferred to I2 or to H1/human action, not an open question against this spec.
