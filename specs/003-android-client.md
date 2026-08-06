# 003 — Android client (Kotlin / Jetpack Compose)

## 1. Goal

The Android client for Findly: a single-module Jetpack Compose app that implements the **complete** wire contract of [`specs/001-api-contract.md`](001-api-contract.md), with a **design-swappable UX layer** so the visual design can be replaced later without touching any business logic. This spec is normative for the Android session; it does not redefine any wire shape (those live in 001 only) or storage shape (002 only). Product context and open items (O1–O10) are in [`specs/000-overview.md`](000-overview.md).

This task (**A1**) builds the **foundation only**: networking for all of 001 §3–§7, auth + device-identity + push-token abstractions, the offline fix-queue idempotency model (§5.1), a navigation scaffold, one proof screen, and the design-system layer itself. Feature screens (live map, history, geofence editor, locate-to-request UI, settings) are **task A2** and are explicitly out of scope here.

## 2. Scope & non-scope

**In scope (A1):**
- Gradle (Kotlin DSL) project skeleton, min SDK 26, target/compile SDK 36, JDK 17.
- A typed network client covering every endpoint in 001 §3–§7, the `{data,features}` / `{error}` envelopes, and the complete §10 error catalog.
- `AuthProvider` abstraction (Firebase Auth ID token source) with a dev/stub implementation; no real `google-services.json`.
- `PushTokenProvider` abstraction (FCM registration token source) with a stub implementation; the re-`POST /devices`-on-refresh trigger (§4.1, 000 §O4).
- Device registration (§4.1) end-to-end at the data/viewmodel layer.
- Offline fix-queue scaffolding with the §5.1 `batchId` idempotency model — logic + tests. The periodic upload worker is scaffolded with runtime TODOs (no real scheduling wired yet).
- Navigation scaffold + one proof screen ("Home"), rendered only through the design system, in light and dark.
- The design-system layer: tokens, `FindlyTheme`, stateless presentational components.

**Out of scope (A2 or later):**
- Live map, history replay, geofence editor, push-to-locate UI, device/family settings screens, invite UI.
- Real Firebase Auth / FCM wiring (needs `google-services.json`, waived per H1 — see §13).
- Real platform geofencing registration, foreground service implementation, WorkManager enqueue call sites (scaffolded, not activated).
- Persistent (Room) fix-queue storage — see §10.4 for the explicit deferral and rationale.

## 3. Module & package architecture

Single Gradle module, per `mobile/android/README.md`'s stated plan ("single-module app first"):

```
mobile/android/
├── settings.gradle.kts, build.gradle.kts, gradle.properties
├── gradle/wrapper/gradle-wrapper.properties   (wrapper jar/scripts generated later — see §13.4)
└── app/
    ├── build.gradle.kts
    └── src/
        ├── main/java/com/findly/android/
        │   ├── FindlyApplication.kt, AppContainer.kt, MainActivity.kt
        │   ├── config/            AppConfig.kt (BuildConfig → typed config, §13)
        │   ├── auth/               AuthProvider, AuthState, DevAuthProvider, FirebaseAuthProviderStub
        │   ├── push/               PushTokenProvider, StubPushTokenProvider
        │   ├── device/             DeviceIdStore/Provider, DeviceInfoProvider, DeviceRegistrar
        │   ├── network/            DTOs (dto/), ApiError, ApiErrorMapper, ApiResult, ports/ (FamilyApi,
        │   │                       DevicesApi, LocationsApi, LocateApi, GeofenceApi, GroupsApi),
        │   │                       FindlyApiService (Retrofit interface), FindlyApiClient (implements
        │   │                       the ports), AuthInterceptor, RetrofitFactory, FeaturesMapper
        │   ├── queue/              QueuedFix, FixBatch, FixQueueStore, InMemoryFixQueueStore,
        │   │                       LocationSyncCoordinator, worker/ (LocationSyncWorker, Scheduler — scaffold)
        │   ├── pushmessages/        PushMessageType (FCM `data.type` discriminator + parser)
        │   └── ui/
        │       ├── designsystem/   token/ (Color, Typography, Spacing, Corner, Elevation), FindlyTheme,
        │       │                   components/ (Button, Card, ListRow, StatusChip, MapMarkerBubble,
        │       │                   TopBar, EmptyState, LoadingState, ErrorState)
        │       ├── nav/            Destinations, FindlyNavHost
        │       └── home/           HomeUiState, HomeStateHolder (pure), HomeViewModel (thin), HomeScreen
        └── test/java/com/findly/android/   (JVM unit tests mirroring the tree above)
```

**Rule (mirrors `backend/README.md`'s hexagonal split):** everything under `network/`, `queue/`, `auth/` (state, not the Android-specific stub wiring), `device/` (state, not `SharedPreferencesDeviceIdStore`), `pushmessages/`, and the `HomeStateHolder` is **pure Kotlin/JVM logic with zero `android.*` framework imports** — unit-testable with plain JUnit, no emulator, no Robolectric. Only the thin Android-framework touch points (`FindlyApplication`, `MainActivity`, `SharedPreferencesDeviceIdStore`, `AndroidDeviceInfoProvider`, `LocationSyncWorker`, Compose UI itself) reference `android.*` / `androidx.*` platform APIs, exactly as `src/functions`/`src/adapters` are the thin, untested integration surface on the backend.

Package / applicationId: `com.findly.android`.

## 4. Design-system contract

A dedicated layer under `ui/designsystem/` is the **only** place styling constants exist. Screens, ViewModels, navigation, and data layers contain **zero** styling — no `Color(...)`, `.dp`, `.sp`, or hardcoded shapes outside `ui/designsystem/token/`.

### 4.1 Token vocabulary (normative names — do not rename without a spec PR)

| Category | Token names | Kotlin type |
|---|---|---|
| Color | `primary, onPrimary, secondary, surface, onSurface, surfaceVariant, danger, onDanger, success, warning, outline` | `androidx.compose.ui.graphics.Color` |
| Type role | `displayLarge, titleLarge, titleMedium, bodyLarge, bodyMedium, labelSmall` | `androidx.compose.ui.text.TextStyle` |
| Spacing | `xs, sm, md, lg, xl, 2xl` | `androidx.compose.ui.unit.Dp` |
| Corner | `sm, md, lg, pill` | `Dp` |
| Elevation | `level0, level1, level2, level3` | `Dp` |

**Kotlin identifier note:** `2xl` is not a legal Kotlin property name (cannot start with a digit). The Kotlin property is named `xxl` and MUST be treated as the same semantic token as `2xl` by any future design-generation tool targeting this contract — documented here once so the mapping is unambiguous.

### 4.2 Default values — design 2a "Ember / Dusk" (A26; `design/findly-design-system/2a-ember-dusk/HANDOFF.md`)

**A26 replaced this section's values** (previously "Findly — Family Location Design System", 2026-07-20, `design/findly-design-system/`, itself already a replacement for the initial placeholder — see git history for that table). Ember layout/type/spacing/shape repainted in the Dusk indigo/cyan palette; every text/essential-icon pairing meets WCAG 2.1 AA (ratios in HANDOFF.md). Fully swappable — these are values, not contract (§4.1's token *names* are unchanged).

Light:

| Token | Value | Token | Value |
|---|---|---|---|
| `primary` | `#3A46C8` | `danger` | `#B3261E` |
| `onPrimary` | `#FFFFFF` | `onDanger` | `#FFFFFF` |
| `secondary` | `#0E7C8F` | `success` | `#10714A` |
| `surface` | `#F2F4FB` | `warning` | `#8A5A00` |
| `onSurface` | `#10142A` | `outline` | `#A9B0CE` |
| `surfaceVariant` | `#E2E6F5` | | |

Dark:

| Token | Value | Token | Value |
|---|---|---|---|
| `primary` | `#7C8BFF` | `danger` | `#FF6B6B` |
| `onPrimary` | `#0A0F27` | `onDanger` | `#2A0708` |
| `secondary` | `#4FE3D0` | `success` | `#52E39B` |
| `surface` | `#0B0F1C` | `warning` | `#FFC44D` |
| `onSurface` | `#E8ECF7` | `outline` | `#3A4463` |
| `surfaceVariant` | `#161D33` | | |

`outline` in light is only 2.1:1 — legal for decorative hairlines/dividers only; any stroke that carries meaning (an unselected control border, a focus ring, an input outline) uses `#6B739A` (3.4:1) instead. In dark, `outline` itself clears 3:1 and serves both. The dot inside a `primary` `FindlyMapMarkerBubble`'s "NOW" pill is `#52E39B` in **both** themes — never light `success` there (1.2:1, disappears). Both rules are implemented as additive, non-contract fields on `FindlyColorTokens` (`outlineStrong`, `markerOnlineDot`/`markerOnlineDotOn`) rather than call-site literals — see `ui/designsystem/token/ColorTokens.kt`.

Typography (same in both themes — only color varies by theme): `displayLarge` 34/40sp bold (tracking −0.4sp), `titleLarge` 24/30sp bold (tracking −0.2sp), `titleMedium` 18/24sp semibold, `bodyLarge` 17/24sp regular, `bodyMedium` 15/20sp regular, `labelSmall` 12/16sp bold uppercase (tracking 0.4sp).

Spacing (dp): `xs`=4, `sm`=8, `md`=12, `lg`=20, `xl`=28, `2xl`(`xxl`)=40.
Corner (dp): `sm`=12, `md`=20, `lg`=28, `pill`=999.
Elevation (dp): `level0`=0, `level1`=1, `level2`=3, `level3`=8. Shadow opacity is neutral black, per level/theme (10%|30%, 14%|45%, 18%|60% for level1/2/3 light|dark) — also additive `FindlyColorTokens` fields (`shadowLevel1Alpha`/`2`/`3`), since it varies by theme and the elevation singleton doesn't.

### 4.3 Structure

- Tokens are plain `@Immutable data class`es (`FindlyColorTokens`, `FindlyTypographyTokens`, `FindlySpacingTokens`, `FindlyCornerTokens`, `FindlyElevationTokens`), one light and one dark **color** instance (`LightFindlyColors`, `DarkFindlyColors`); typography/spacing/corner/elevation are theme-invariant singletons.
- `FindlyTheme(darkTheme: Boolean = isSystemInDarkTheme(), content)` provides all five token sets via `staticCompositionLocalOf`, and additionally maps them onto a real Material3 `MaterialTheme` (`ColorScheme`, `Typography`, `Shapes`) so that any un-migrated Material3 primitive still themes correctly during the transition.
- `object FindlyTheme` exposes `FindlyTheme.colors`, `.typography`, `.spacing`, `.corner`, `.elevation` as `@Composable` accessors — the only sanctioned way components read style.
- **Stateless presentational components** in `ui/designsystem/components/`: `FindlyButton`, `FindlyCard`, `FindlyListRow`, `FindlyStatusChip`, `FindlyMapMarkerBubble`, `FindlyTopBar`, `FindlyEmptyState`, `FindlyLoadingState`, `FindlyErrorState` (A1); **A2 additively adds** `FindlyTextField` (labeled single-line input — geofence editor fields, invite code/display-name entry), `FindlySwitchRow` (a `FindlyListRow` with a trailing, `FindlyTheme`-recolored `Switch` — device pause/tracking toggles, geofence notify flags), and `FindlySectionHeader` (a titled group label — settings screen's "Devices"/"Members" grouping). Each takes plain data (strings, booleans, callbacks) and renders using only `FindlyTheme.*` — never a screen-specific dependency, never a ViewModel reference.
- Screens (`ui/home/HomeScreen.kt` in A1; `ui/map`, `ui/history`, `ui/geofences`, `ui/locate`, `ui/settings`, `ui/invites` in A2; `ui/groups` in A5) compose these components and are driven by state hoisted from a ViewModel. A `ComponentGalleryPreview.kt` renders every component in both themes side by side, as a visual regression aid for a future design swap. Three documented exceptions to "components only" exist, each a platform primitive with real behavior beyond styling — never a substitute for a missing design-system component. The two Material3 exceptions (1–2) theme correctly with zero extra work because `FindlyTheme` already maps every token onto a real Material3 `MaterialTheme` (previous bullet's "any un-migrated Material3 primitive still themes correctly"); the third (3) is an OS-level surface that needs no `FindlyTheme` styling at all:
  1. A2's history screen uses Material3's `DatePicker`/`DatePickerDialog` directly for the date-range inputs (a calendar widget, not a styling primitive).
  2. A5's `GroupDetailScreen` uses Material3's `AlertDialog` directly for owner-action confirmations (rename/extend/rotate/kick/delete, §12.2) — a modal-overlay primitive with its own dismiss/back-press handling, not a styling primitive; re-implementing a confirm dialog as a design-system component was judged not worth it for five call sites in one screen. **A8's `SettingsScreen` uses it on the same grounds** for the §12.4 delete-account / delete-family confirmations.
  3. A5's `GroupMapScreen`/`GroupDetailScreen` use a plain Android `Toast` for the `GROUP_EXPIRED` bounce-back notice (§12.2) — an OS-level surface outside the app's own UI entirely (unlike 1–2, it needs none of `FindlyTheme`'s styling), the simplest way to show a transient, unmissable notice immediately before navigating away.

## 5. Networking layer — endpoint → client mapping

Base URL is configured as `{scheme}://{host}/api/`; every Retrofit method path is `v1/...`, together forming the `/api/v1/...` routes of 001 §1.1. `FindlyApiService` is the raw Retrofit interface; `FindlyApiClient` implements six narrow port interfaces (one per 001 endpoint group) and is the only thing the rest of the app depends on — mirrors the backend's ports/adapters split so a future fake for ViewModel tests is trivial.

| 001 § | Method & path | Port interface · method | Request DTO | Response DTO |
|---|---|---|---|---|
| 3.1 | `POST v1/families` | `FamilyApi.createFamily` | `CreateFamilyRequestDto` | `CreateFamilyResponseDto` |
| 3.2 | `GET v1/families/me` | `FamilyApi.getMyFamily` | — | `FamilyMeResponseDto` |
| 3.3 | `POST v1/families/me/invites` | `FamilyApi.createInvite` | `CreateInviteRequestDto` | `CreateInviteResponseDto` |
| 3.4 | `POST v1/invites/accept` | `FamilyApi.acceptInvite` | `AcceptInviteRequestDto` | `AcceptInviteResponseDto` |
| 3.5 | `PATCH v1/families/me/members/{userId}` | `FamilyApi.updateMember` | `UpdateMemberRequestDto` | `MemberDto` |
| 3.6 | `DELETE v1/families/me/members/{userId}` | `FamilyApi.removeMember` | — | `Unit` (bare 204 — no `features`, see §6.3) |
| 4.1 | `POST v1/devices` | `DevicesApi.registerDevice` | `RegisterDeviceRequestDto` | `DeviceDto` |
| 4.2 | `GET v1/devices` | `DevicesApi.listDevices` | — | `ListDevicesResponseDto` |
| 4.3 | `PATCH v1/devices/{deviceId}` | `DevicesApi.updateDevice` | `UpdateDeviceRequestDto` | `DeviceDto` |
| 5.1 | `POST v1/locations` (+`X-Device-Id`) | `LocationsApi.reportLocations` | `ReportLocationsRequestDto` | `ReportLocationsResponseDto` |
| 5.2 | `GET v1/locations/latest` | `LocationsApi.getLatestLocations` | — | `LatestLocationsResponseDto` |
| 5.3 | `GET v1/locations/history` | `LocationsApi.getLocationHistory` | query params | `LocationHistoryResponseDto` |
| 6.1 | `POST v1/locate-requests` | `LocateApi.createLocateRequest` | `CreateLocateRequestRequestDto` | `LocateRequestDto` |
| 6.2 | `GET v1/locate-requests/{id}` | `LocateApi.getLocateRequest` | — | `LocateRequestStatusResponseDto` |
| 6.3 | `POST v1/locate-requests/{id}/fulfill` (+`X-Device-Id`) | `LocateApi.fulfillLocateRequest` | `FulfillLocateRequestRequestDto` | `FulfillResponseDto` |
| 7.1 | `GET v1/geofences` (+`If-None-Match`) | `GeofenceApi.getGeofences` | — | `ETagged<GeofenceConfigResponseDto>?` (`null` on 304, see §6.3) |
| 7.2 | `PUT v1/geofences` (+`If-Match`) | `GeofenceApi.replaceGeofences` | `ReplaceGeofencesRequestDto` | `ETagged<GeofenceConfigResponseDto>` |
| 7.3 | `POST v1/geofence-events` (+`X-Device-Id`) | `GeofenceApi.reportGeofenceEvents` | `ReportGeofenceEventsRequestDto` | `GeofenceEventsResponseDto` |
| 7.4 | `GET v1/geofence-events` | `GeofenceApi.getGeofenceEventHistory` | query params | `GeofenceEventHistoryResponseDto` |
| 12.1 | `POST v1/groups` | `GroupsApi.createGroup` | `CreateGroupRequestDto` | `GroupDto` |
| 12.2 | `GET v1/groups` | `GroupsApi.listGroups` | — | `ListGroupsResponseDto` |
| 12.3 | `GET v1/groups/{groupId}` | `GroupsApi.getGroup` | — | `GroupDetailDto` |
| 12.4 | `PATCH v1/groups/{groupId}` | `GroupsApi.updateGroup` | `UpdateGroupRequestDto` | `GroupDto` |
| 12.5 | `DELETE v1/groups/{groupId}` | `GroupsApi.deleteGroup` | — | `Unit` (bare 204, as §3.6) |
| 12.6 | `POST v1/groups/join` | `GroupsApi.joinGroup` | `JoinGroupRequestDto` | `GroupDto` |
| 12.7 | `POST v1/groups/{groupId}/code/rotate` | `GroupsApi.rotateGroupCode` | — | `RotateGroupCodeResponseDto` |
| 12.8 | `POST v1/groups/{groupId}/leave` | `GroupsApi.leaveGroup` | — | `Unit` (bare 204) |
| 12.9 | `DELETE v1/groups/{groupId}/members/{userId}` | `GroupsApi.removeGroupMember` | — | `Unit` (bare 204) |
| 12.10 | `GET v1/groups/{groupId}/locations/latest` | `GroupsApi.getGroupLatestLocations` | — | `GroupLatestLocationsResponseDto` |

DTOs are `kotlinx.serialization` `@Serializable data class`es whose field names match 001's JSON verbatim (no `@SerialName` needed anywhere). Fields the spec marks optional are nullable with `= null` defaults; fields the spec marks required are non-null. Where 001 documents a field as `null` in a specific state (e.g. 5.2's "no report yet" devices, or history points before any fix — see 5.2/5.3), the DTO makes the whole neighborhood of related fields (`accuracyM`, `batteryPct`, `source`, `receivedAt` alongside the explicitly-called-out `lat/lon/recordedAt/isStale`) nullable too, defensively, per 001 §1.1's forward-compatibility rule ("clients MUST ignore unknown response fields") extended to "clients MUST NOT crash on an absent-but-plausible field".

`X-Device-Id` is attached as an explicit Retrofit `@Header` parameter only on the three methods 001 §1.2 actually requires it on (`reportLocations`, `reportGeofenceEvents`, `fulfillLocateRequest`) — never globally, so the client can't accidentally leak it where the contract doesn't want it.

## 6. Error handling

### 6.1 `ApiError` sealed hierarchy

One subtype per 001 §10 catalog code, plus two client-local variants: `NetworkFailure(cause: Throwable)` (no HTTP response at all — timeout, DNS, offline) and `Unknown(code, message, details, requestId)` (a future/unrecognized code — defensive, should never trigger against a spec-conformant backend). Code-specific `details` are typed where 001 defines a shape: `TrackingPaused.deviceSettings`, `GeofenceVersionConflict.currentEtag`, `ValidationFailed.fields`/`.reason`, `LocationBatchTooLarge.max`, `LimitExceeded.limit`, `RateLimited.retryAfterSeconds`.

`ApiErrorMapper.fromCode(code, message, details, requestId): ApiError` is a pure function (`when (code) { "AUTH_MISSING_TOKEN" -> ...; ...; else -> Unknown(...) }`) covering all 27 catalog codes — the test checklist requires a test that asserts every single code maps to its named subtype (not `Unknown`). The six group-era codes (`PROFILE_NOT_FOUND`, `GROUP_NOT_FOUND`, `GROUP_EXPIRED`, `GROUP_CODE_INVALID`, `GROUP_ALREADY_MEMBER`, `GROUP_FULL` — with `GroupFull.max` typed) get user messages in `ApiErrorUserMessage.kt` like every other code.

### 6.2 `ApiResult<T>`

```kotlin
sealed class ApiResult<out T> {
    data class Success<T>(val data: T, val features: Features?) : ApiResult<T>()
    data class Failure(val error: ApiError) : ApiResult<Nothing>()
}
```

`features` is nullable **only** to represent 001's documented body-less successes: the bare `204`s (§3.6, §12.5, §12.8, §12.9) and §7.1's bare `304` (000 overview, "Subscription-ready" bullet). Every other endpoint always carries `Features`.

### 6.3 Envelope parsing & the 204/304 exceptions

- Normal path: Retrofit method returns `Response<Envelope<X>>`; on `isSuccessful`, `FindlyApiClient` unwraps `body.data` + `body.features` into `ApiResult.Success`. On non-2xx, `response.errorBody()` (raw, since Retrofit does not run the success converter on error responses) is decoded as `ErrorEnvelope` and mapped via `ApiErrorMapper`.
- `removeMember` (§3.6): Retrofit method returns `Response<okhttp3.ResponseBody>` (the built-in identity converter — no JSON parsing is attempted on an intentionally-empty 204 body). Success → `ApiResult.Success(Unit, features = null)`.
- `getGeofences` (§7.1): a `304` is not `isSuccessful` (only 200–299 counts) and is handled as a **first-class branch before generic error handling** — `response.code() == 304` → `ApiResult.Success(null, features = null)`; anything else 4xx/5xx still goes through the normal `ApiErrorMapper` path.

### 6.4 Auth-expiry retry

Per 001 §2.1 ("Clients MUST refresh tokens via the Firebase SDK and retry once on `AUTH_TOKEN_EXPIRED`"): every `FindlyApiClient` method, on receiving `ApiError.AuthTokenExpired`, calls `authProvider.currentIdToken(forceRefresh = true)` and retries the exact same call **once**; a second `AuthTokenExpired` is surfaced to the caller as a `Failure`. This is the ID-token concern — see §7 for why it's distinct from push-token refresh.

**A2 refactor:** this logic is a single private `withAuthRetry(attempt: suspend () -> ApiResult<T>): ApiResult<T>` helper in `FindlyApiClient` — calls `attempt()` once, and on an `AuthTokenExpired` failure, force-refreshes the token and calls `attempt()` exactly one more time. Every method funnels through it, including the three body-shape exceptions of §6.3 (`removeMember`'s bare 204, `getGeofences`'s bare 304, `replaceGeofences`'s ETag-header success) — these previously hand-duplicated the retry branch inline (an A1 review finding); now there is exactly one implementation, covered by `FindlyApiClientAuthRetryTest`'s tests for all four shapes (the generic envelope path plus the three exceptions).

## 7. Auth (`AuthProvider`) — phone-number sign-in (specs/006)

Sign-in is **phone-number-only** (SMS OTP): flow, state machine, E.164 normalization, and the error/message catalog are normative in [`specs/006-phone-auth.md`](006-phone-auth.md) §3–§5; this section owns the Android shapes. The former email/password path (`signIn(email, password)`, `AuthSignInException`, the email/password form) is **deleted** — no email/password code survives.

```kotlin
sealed interface AuthState {
    data object Loading : AuthState
    data object SignedOut : AuthState
    data class SignedIn(val uid: String) : AuthState
}

// Pure — the closed error set of 006 §4.2; messages in PhoneAuthUserMessage.kt
enum class PhoneAuthError {
    INVALID_PHONE_NUMBER, TOO_MANY_REQUESTS, SMS_QUOTA_EXCEEDED,
    APP_VERIFICATION_FAILED, INVALID_CODE, CODE_EXPIRED, NETWORK, UNKNOWN,
}
class PhoneAuthException(val error: PhoneAuthError) : Exception(error.name)

sealed interface PhoneVerificationEvent {
    data object CodeSent : PhoneVerificationEvent
    data object Completed : PhoneVerificationEvent            // instant verification / auto-retrieval: already signed in
    data class Failed(val error: PhoneAuthError) : PhoneVerificationEvent
}

interface AuthProvider {
    val authState: StateFlow<AuthState>
    suspend fun currentIdToken(forceRefresh: Boolean = false): String?
    suspend fun signOut()
    /** Starts SMS verification for [phoneNumberE164] (already normalized per 006 §3). Calling again
     *  with the same number while a verification is in flight = resend — the provider reuses its
     *  internal resend token; Firebase types never cross this interface. */
    fun startPhoneVerification(phoneNumberE164: String): Flow<PhoneVerificationEvent>
    /** Confirms the SMS code for the provider-tracked in-flight verification.
     *  On success `authState` flips to `SignedIn`. Throws [PhoneAuthException]. */
    suspend fun confirmCode(code: String)
}
```

The verification session (`verificationId`, `ForceResendingToken`) is **provider-internal state** — one sign-in at a time is the only real scenario, and keeping Firebase types out of the interface keeps every StateHolder pure JVM. `PhoneNumberNormalizer.kt` (pure, `auth/`) implements 006 §3; `PhoneAuthUserMessage.kt` (pure, mirrors `ApiErrorUserMessage.kt`) maps each `PhoneAuthError` to its fixed 006 §4.2 message — raw SDK text never reaches a screen.

`AuthInterceptor` (OkHttp) attaches `Authorization: Bearer <token>` from `authProvider.currentIdToken()` on every request (001 §1.2 — required on every endpoint, no anonymous routes).

**`DevAuthProvider`** (dev/stub, used when `BuildConfig.AUTH_MODE == "insecure-local"`): keeps an in-memory signed-in dev user and constructs an **unsigned** JWT-shaped bearer token at runtime — `base64url({"alg":"none"}) + "." + base64url({"iss":.., "aud":.., "sub":<uid>, "iat":.., "exp":..}) + "."` — matching 001 §2.3's "Firebase Auth emulator / hand-crafted JWTs" local-dev shape, so it can be pointed at a real backend running `AUTH_MODE=insecure-local` for manual integration testing. No literal token string is ever embedded in source, tests, or this spec — only the construction code — so nothing here can be mistaken for a real credential by the security-review secret scan. It implements the two-step phone shape per 006 §5: `startPhoneVerification` validates the normalized number and immediately emits `CodeSent`; `confirmCode` accepts any non-blank code and signs in with `uid = <normalized E.164 number>` (no SMS, no Firebase). `signInDev(uid)` stays for tests.

**`FirebaseAuthProvider`** (real implementation for `AUTH_MODE == "firebase"`): constructor-**injects** `FirebaseAuth` plus a `CurrentActivityProvider` rather than resolving either itself — `FirebaseAuth.getInstance()` needs an initialized `FirebaseApp`/Android `Context`, which doesn't exist in this project's plain-JVM unit tests (no Robolectric), so injection keeps the class a **thin, untested adapter** (same category as `AndroidDeviceInfoProvider`) while keeping `AuthProviderFactory` — and its test — pure-JVM. `authState` is backed by `FirebaseAuth.AuthStateListener` (mapped to `SignedOut`/`SignedIn(uid)`); `currentIdToken` calls `getIdToken(forceRefresh).await()`; `signOut` calls `firebaseAuth.signOut()`. Phone verification: `startPhoneVerification` wraps `PhoneAuthProvider.verifyPhoneNumber(PhoneAuthOptions)` in a `callbackFlow`, mapping `onCodeSent`/`onVerificationCompleted` (instant verification → `signInWithCredential` → `Completed`)/`onVerificationFailed` onto `PhoneVerificationEvent`s and the SDK's typed exceptions onto `PhoneAuthError` per the 006 §4.2 table; `confirmCode` calls `signInWithCredential(PhoneAuthProvider.getCredential(verificationId, code))`. Firebase requires an `Activity` for Play Integrity / reCAPTCHA app verification: `fun interface CurrentActivityProvider { fun current(): Activity? }` is a thin framework-touching type (same bucket as `AndroidDeviceInfoProvider`); `MainActivity` registers/clears itself via `AppContainer`, and **only** `FirebaseAuthProvider` consumes it — a `null` activity (not realistically reachable, the UI triggered the call) emits `Failed(APP_VERIFICATION_FAILED)`.

`AuthProviderFactory.create(mode, firebaseProjectId, firebaseAuthProvider: () -> AuthProvider)` keeps its lazy-supplier shape — the supplier is invoked only when `mode == AuthMode.Firebase`, letting `AuthProviderFactoryTest` exercise the Firebase branch with a plain fake (never touching the real SDK, still 100% pure-JVM) while `AppContainer` — the only real caller — supplies `{ FirebaseAuthProvider(FirebaseAuth.getInstance(), activityProvider) }`, so the real SDK is only ever reached on a device/emulator with Firebase initialized, never from a unit test or an `insecure-local` build.

**Sign-in UI** (phone-auth rework, specs/006): one screen, two steps — `ui/signin/SignInScreen.kt` stays a single stateless screen on `Destinations.SignIn` that renders either phone entry or code entry from the state (no second nav destination; WhatsApp-style). Existing components suffice: `FindlyTextField` (numeric keyboards; the phone field prefilled `+32`, the code field a plain 6-digit input) + `FindlyButton` + `FindlyErrorState`. It is driven by `SignInStateHolder` (pure; constructor-injected `AuthProvider` **and a `CoroutineScope`** for the resend-cooldown ticker — same shape as `MapStateHolder`) via the thin `SignInViewModel` wrapper. `SignInUiState` implements the 006 §4.1 state machine verbatim: `EnteringPhone(phone, error?)` / `SendingCode(phone)` / `EnteringCode(phone, resendSecondsLeft, error?)` / `ConfirmingCode(phone)`. There is deliberately no `Success` state: on sign-in, `authProvider.authState` flips to `SignedIn`, which `FindlyNavHost` observes directly (`LaunchedEffect` on `authState`, pops back to `Home`) — unchanged principle. `FindlyNavHost`'s former `DevAuthProvider` short-circuit (dev sign-in button bypassing the screen) is **removed**: dev builds also navigate to `SignIn`, so the phone UI is actually exercised locally against `AUTH_MODE=insecure-local`.

Firebase Auth ID-token refresh (tokens live ~1 h, 001 §2.1) is handled entirely by §6.4's retry-once path — it is **not** the same mechanism as §8's push-token refresh, a distinction worth stating explicitly since both are "some kind of token refresh" but trigger different client behavior (retry a call vs. re-register a device).

## 8. Device identity & registration

- `DeviceIdProvider.deviceIdFor(uid: String): String` returns a client-generated UUIDv4, persisted per `uid` via `DeviceIdStore` (real: `SharedPreferencesDeviceIdStore`; test: `InMemoryDeviceIdStore`). Per 001 §1.4, a fresh `deviceId` is generated the first time a given `uid` is seen (never reused across a different signed-in user on the same install).
- `DeviceInfoProvider` (interface: `platform`, `model`, `appVersion`; real `AndroidDeviceInfoProvider` reads `Build.MODEL` / `BuildConfig.VERSION_NAME`; fake supplies fixed values for tests) supplies the required §4.1 fields.
- `DeviceRegistrar.registerOrUpdate(pushToken=null, locationPushToken=null)` builds a `RegisterDeviceRequestDto` (omitting absent token fields entirely, matching 001 §4.1's "omitted token fields are left unchanged" pin) and calls `DevicesApi.registerDevice`. Called on: first sign-in, every push-token refresh (§9), and (later, A2) every app update.

## 9. Push-token lifecycle (`PushTokenProvider`)

```kotlin
fun interface PushTokenRefreshListener { fun onNewToken(token: String) }
interface PushTokenProvider {
    suspend fun currentToken(): String?
    fun addRefreshListener(listener: PushTokenRefreshListener)
}
```

**Runtime contract:** the real FCM implementation and the handling of all four push types are normative in **[009 §5](009-device-runtime.md)** (task A9).

`StubPushTokenProvider` is the A1 implementation (no real FCM SDK wired — `google-services.json` is absent per H1-waiver): it never emits a token, documented as a TODO(H1)/TODO(A2) wiring point for `FirebaseMessaging.getInstance()` + a `FirebaseMessagingService.onNewToken` override. The **contract** is fixed now: whatever the real implementation is, `AppContainer` wires its `addRefreshListener` to `deviceRegistrar::onPushTokenRefreshed`, which re-calls `POST /devices` with the new token — satisfying 001 §4.1 / 000 §O4 ("Clients MUST re-`POST /devices` on token refresh") without any future call-site change.

## 10. Offline fix-queue & `batchId` idempotency (001 §5.1)

### 10.1 Model

```kotlin
data class QueuedFix(val fixId: String, val recordedAt: String, val lat: Double, val lon: Double,
                      val accuracyM: Double, val altitudeM: Double?, val speedMps: Double?,
                      val bearingDeg: Double?, val batteryPct: Int, val source: FixSource)
enum class FixSource { PERIODIC, LOCATE, GEOFENCE, MANUAL }
data class FixBatch(val batchId: String, val fixes: List<QueuedFix>)
```

### 10.2 `FixQueueStore` contract

```kotlin
interface FixQueueStore {
    suspend fun enqueue(fix: QueuedFix)
    suspend fun pendingCount(): Int
    suspend fun nextBatch(maxSize: Int = 100): FixBatch?
    suspend fun markBatchAccepted(batchId: String)
    suspend fun markBatchFailedTransient(batchId: String)
    suspend fun markBatchRejected(batchId: String, offendingFixIds: Set<String>)
}
```

Rules encoded (and unit-tested — §14):

1. **Freeze-on-first-ask:** `nextBatch()` assigns a `batchId` to a slice of the oldest ≤`maxSize` pending fixes the first time it's called with nothing already in flight, then **returns the identical `batchId` + fix set** on every subsequent call until that batch is resolved — this is what makes a retried `POST /locations` after a transport failure resend byte-identical content under the same `batchId` (001 §5.1: "retries after transport failures or 5xx MUST resend identical content under the same `batchId`").
2. **Accept:** `markBatchAccepted(batchId)` removes exactly those fixes from the pending pool, permanently — used for any `2xx` response regardless of the `accepted`/`duplicates` split (a replayed-and-deduped batch is still a `200`, i.e. still "resolved" from the queue's point of view).
3. **Transient failure:** `markBatchFailedTransient(batchId)` is a no-op on the pending pool — the batch stays frozen for an identical retry (network error, 5xx).
4. **Definitive rejection:** `markBatchRejected(batchId, offendingFixIds)` drops only the named offenders (parsed from `details.fields` paths like `"fixes[3].recordedAt"`, §15) and un-freezes the rest, which get folded into a **new** batch (new `batchId`) on the next `nextBatch()` call — matching 001 §5.1: "no marker was written — the batch is dead... resubmit the remainder under a new `batchId`".
5. **New fixes never join an in-flight batch:** `enqueue()` while a batch is frozen appends to the pending pool but is excluded from the current `FixBatch.fixes` until the in-flight batch resolves.
6. **Size cap:** `nextBatch(maxSize = 100)` never returns more than `maxSize` fixes (001 §5.1: ">100 → `LOCATION_BATCH_TOO_LARGE`"), splitting a larger backlog across successive calls; an empty pool returns `null` (never an empty-array batch — 001: "empty → `VALIDATION_FAILED`").

### 10.3 `LocationSyncCoordinator`

Ties `FixQueueStore` + `LocationsApi` together: `syncOnce()` calls `nextBatch()`, maps `QueuedFix → LocationFixDto`, calls `reportLocations`, and on the result: `Success` → `markBatchAccepted`; `Failure(NetworkFailure | InternalError | ...5xx-shaped)` → `markBatchFailedTransient`; `Failure(ValidationFailed(fields))` → parses the `fixes[N]` index out of each field path, maps to `fixId`, calls `markBatchRejected`; `Failure(TrackingPaused(deviceSettings))` → returns a `Paused` outcome (caller stops the periodic worker per 001 §5.1, does not touch the queue — those fixes stay queued for after resume).

### 10.4 Persistence — explicit deferral

The task allows "Room or an abstraction." **A1 ships the abstraction (`FixQueueStore`) plus an in-memory implementation (`InMemoryFixQueueStore`)**, not a Room-backed one, for one concrete reason: this sandbox has no Android/Gradle toolchain to compile-check a Room + KSP annotation-processing setup (§13.4), and an unverifiable `@Entity`/`@Dao`/KSP-version pairing is a worse risk than an honestly-scoped in-memory placeholder behind the exact interface a persistent implementation will later satisfy with zero call-site changes. This is a deliberate, documented scope decision, not an oversight — flagged again in the final task report.

### 10.5 Periodic worker — scaffold only (real scheduling: [009 §3](009-device-runtime.md))

> The scheduling strategy this scaffold is waiting for — WorkManager for ≥15 min, a `FOREGROUND_SERVICE_LOCATION` service for 5/10 min, once-per-local-day for 1440, plus the durable Room-backed queue that replaces §10.4's in-memory store — is normative in **[009 §2–§3](009-device-runtime.md)** (tasks A10/A11).


`queue/worker/LocationSyncWorker` (a `CoroutineWorker` skeleton) and `LocationSyncScheduler` (holds the WorkManager periodic-request-building TODO) exist as untested Android-framework glue, per the task's explicit allowance ("the periodic worker may be scaffolded with clear runtime TODOs"). All actual sync decision logic lives in the tested `LocationSyncCoordinator` above; the worker's job is only to invoke it on a schedule once WorkManager enqueueing is wired (A2/H1-adjacent).

## 11. Permission & onboarding flow (000 §O2)

> Cross-platform permission rules (prominent disclosure before the OS prompt, denial banner, foreground re-check, revocation handling) are normative in **[009 §7](009-device-runtime.md)**; the Android staging below is the platform detail it references.

Normative for A2's implementation (no permission-request UI ships in A1 beyond declaring manifest permissions):

1. First app run after sign-in: request `ACCESS_FINE_LOCATION` (foreground) with a rationale screen shown first if the OS requests it.
2. If granted, and the device's configured `syncIntervalMinutes` requires background reporting, request `ACCESS_BACKGROUND_LOCATION` as a **separate, later** request (Android 11+ forbids bundling foreground+background in one dialog) — shown only after a dedicated rationale explaining family-tracking background use (Play policy prep, `mobile/android/README.md`).
3. `syncIntervalMinutes` ∈ {5, 10} (000 §O2) additionally requires the persistent-notification foreground service; ≥15 uses WorkManager periodic work — this determines which permission/consent path §2 above continues into, but the actual foreground-service implementation is A2.
4. `POST_NOTIFICATIONS` (API 33+) is requested independently, for geofence/locate push alerts.
5. **Denial handling:** `ACCESS_FINE_LOCATION` denied → app still shows the family map (open system, others' locations unaffected) but this device cannot report; `ACCESS_BACKGROUND_LOCATION` denied → falls back to foreground-only reporting (only while the app is open) with a persistent in-app banner; the rationale flow is re-enterable from device settings (A2 screen).

## 12. Navigation & proof screen

`Destinations` lists route string constants: `Home` (implemented in A1) and, as of A2, `Map`/`History`/`Geofences`/`Locate`/`Settings` (reserved in A1, wired to real screens now) plus a new additive `Invites` constant (§3.3/§3.4 — not reserved in A1, added the same way), `SignIn` (§7), and the groups destinations `Groups`/`GroupDetail`/`GroupJoin`/`GroupMap` (§12.2). `FindlyNavHost` wires a `NavController` + one `composable(...)` per destination; each feature screen's `ViewModel` is constructed from `AppContainer`'s single `FindlyApiClient` (it implements all six 001 §3–§12 port interfaces, so each `ViewModelFactory` just narrows it to the one port it needs — no per-screen networking wiring). `Locate` takes its target `userId`/`displayName` from a `FindlyNavHost`-local `remember`ed selection (set when a roster row is tapped in the map screen) rather than a nav-graph path argument — the app's only external deep link is the group-join one (`findly://group-join?code=…`, §12.2, whose payload is percent-safe Crockford base32 by construction), so a `{userId}` path template would only add percent-encoding risk (a `displayName` may contain spaces) for no benefit.

**Proof screen — Home:** shows `AuthState` (`Loading` / `SignedOut` with a dev sign-in `FindlyButton` / `SignedIn` with a `FindlyStatusChip` reflecting device-registration outcome) built entirely from `ui/designsystem` components, state hoisted from `HomeStateHolder` (pure, constructor-injected `AuthProvider`/`DeviceRegistrar`, exposes `StateFlow<HomeUiState>`) via the thin `HomeViewModel : ViewModel()` wrapper. `HomeScreenLightPreview`/`HomeScreenDarkPreview` render it under `FindlyTheme(darkTheme = false/true)`. **A2 addition:** once registered, Home also renders a short quick-nav list of `FindlyButton`s (one per feature destination) — there is no bottom-nav/drawer design-system component yet, so this is the minimal reachability wiring, replaceable by a future design pass without touching any screen beneath it.

### 12.1 A2 feature screens

Each screen is stateless Composables (`ui/<feature>/<Feature>Screen.kt`) driven by a pure `<Feature>StateHolder` (constructor-injected port interface + `CoroutineScope` where something is eagerly loaded, matching `HomeStateHolder`'s pattern) behind a thin `<Feature>ViewModel : ViewModel()` wrapper — identical shape to A1's Home screen, repeated six times:

- **`ui/map`** (§5.2): `MapStateHolder` loads `GET /locations/latest` into `RosterMemberUi`/`RosterDeviceUi`. The map-tile view itself is behind a `MapRenderer` interface (`@Composable fun Render(members, modifier)`); `PlaceholderMapRenderer` is the only implementation today (no Google Maps SDK/API key — H1-gated). A real Maps API key would be read from `AppConfig.mapsApiKey`, itself sourced from a `MAPS_API_KEY` Gradle project property (`app/build.gradle.kts`) — **never hardcoded, never committed**; blank by default, which is what ships now. Tapping a roster row navigates to `Locate` for that member.
- **`ui/history`** (§5.3): `HistoryStateHolder` (no eager load — a query needs `userId`+date range from the UI first) exposes `load`/`loadMore`; `loadMore` re-issues the same query with the previous page's `nextCursor` and appends. The screen's date pickers use Material3's `DatePickerDialog` directly (§4.3's documented exception).
- **`ui/geofences`** (§7.1/§7.2): `GeofencesStateHolder` loads the whole config, supports local add/edit/delete (`upsertGeofence`/`removeGeofence`) against a pending in-memory list, and `save()`s it as a full-document `PUT` with `If-Match`. On `409 GEOFENCE_VERSION_CONFLICT`, it re-`GET`s for the fresh `etag` and adopts it as the new baseline while **keeping the caller's pending edit** (never silently discarded/overwritten) — `GeofencesUiState.Content.conflict = true` until the next successful save.
- **`ui/locate`** (§6): `LocateStateHolder.requestLocate` calls `POST /locate-requests`, then polls `GET /locate-requests/{id}` every `pollIntervalMillis` (default 2000, per §6.2) until a terminal status (`fulfilled`/`expired`/`pushFailed`); a second `requestLocate` call cancels any in-flight poll loop first.
- **`ui/settings`** (§3.5/§3.6/§4.2/§4.3): `SettingsStateHolder` loads `GET /families/me` + `GET /devices` together; every mutation (`updateDeviceSettings`, `updateMember`, `removeMember`) is gated by `isParent` (`myRole == "parent"`) **client-side before any network call** — a non-parent gets a local `mutationError` and the server is never hit, though the server enforces the same rule regardless (defense in depth, not the only guard).
- **`ui/invites`** (§3.3/§3.4): `InvitesStateHolder` holds two independent, non-mutually-exclusive sub-flows (create-invite, accept-invite) in one plain `InvitesUiState` data class rather than a sealed hierarchy, since a screen can have both forms visible at once.
- **`ui/signin`** (§7, H1 addition): see §7 for the full design — `SignInStateHolder`/`SignInScreen`/`Destinations.SignIn`.

### 12.2 Groups screens (specs/005; wire shapes 001 §12)

Same StateHolder/ViewModel/stateless-screen shape as §12.1, under `ui/groups/`:

- **`GroupsListScreen`** — `GroupsListStateHolder` loads `GET /groups`; each group renders as a `FindlyCard` with name, member count, a `FindlyStatusChip` for `state` (`active`/`ended`/`archived`), and a countdown to `endsAt`; entry points to create and join. The list's empty state is also the **family-less home**: a signed-in user without a family (`FAMILY_NOT_FOUND`/`PROFILE_NOT_FOUND` on family calls, 001 §1.5) is no longer a dead end — Home offers family create/join *and* groups.
- **`CreateGroupSheet`** — name, end date+time picker bounded by `features.limits.maxGroupDurationDays` (min now+1 h, per 001 §12.1), and a 3-way `expiryPolicy` selector that shows each policy's plain-language privacy line from 005 §2.1 verbatim; `displayName` field shown only when the caller has no profile yet.
- **`GroupDetailScreen`** — roster (`FindlyListRow` per member), the join code with an OS share-sheet action (same pattern as invites); owner controls behind confirm dialogs (Material3 `AlertDialog`, §4.3's documented exception): rename, extend/end (date picker within limits), rotate code, kick member, delete group. Members get Leave. `state`-dependent rendering per the 005 §2.3 matrix (grace: members see meta only; archived: roster memento, no map entry point).
- **`GroupJoinScreen`** — code entry reusing the invite-code input/normalization pattern (001 §1.4), optional per-group display name; also the target of the **deep link** `findly://group-join?code=XXXXXXXX` — the app's first, via a new manifest intent filter on `MainActivity`; the code payload is percent-safe by construction (Crockford base32 only) and is validated by the same pure normalization logic before any network call. HTTPS universal links: §12.3 / [007](007-public-join-links.md).
- **`GroupMapScreen`** — `GroupMapStateHolder` polls `GET /groups/{id}/locations/latest` the same way `MapStateHolder` treats the family map (§12.1), rendered through the same `MapRenderer` seam; markers show display name + stale dimming via the `isStale` flag. **Position-only** (005 §3): no device chips, no battery — the roster/marker UI simply has no such fields (the DTO doesn't carry them).

Error rendering: the six group codes surface through `ApiErrorUserMessage` like every other code; `GROUP_EXPIRED` on the map/detail SHOULD bounce the user back to the groups list with a "this group has ended" notice — identically on both screens: an Android `Toast` (§4.3's documented exception) fires immediately before navigating away, since the state-driven `Expired` message alone renders for at most one composition frame and is otherwise imperceptible (the list re-load then reflects the true state).

### 12.3 Public join links & QR ([007](007-public-join-links.md))

- `BuildConfig`/`AppConfig` (§13) gains **`JOIN_LINK_HOST`** — the 007 §1 deployment constant (recorded at H4); debug MAY use the same host as release (the link surface has no dev mode).
- A second intent filter on `MainActivity`: `https` / `{JOIN_LINK_HOST}` / path `/g`, with `android:autoVerify="true"` (App Links; verification against the host's `assetlinks.json`, 007 §3 — the fingerprints are the same SHA-256s as the Firebase/App Check registration).
- The delivered URI's **fragment** carries the code (007 §1) and goes through the **same `GroupJoinCodeSanitizer` whitelist** as the `findly://` path; wrong host or path is ignored (never mis-routed); a valid link with no usable fragment opens `GroupJoinScreen` with an empty code field.
- Sharing: the detail screen's share-sheet text switches to the 007 §1 https link; a **QR code of that link is rendered on-device** (local generator only — a networked QR service would leak the capability, 007 §4). The `findly://` deep link stays supported.

### 12.4 Privacy: export & account deletion ([008](008-privacy-endpoints.md); wire shapes 001 §13)

Extends the §5 endpoint mapping with the three 001 §13 calls. New rules on top of the standard client stack:

- **Export** (settings entry, all users; parents additionally per family member from the member row): `GET /export` is the one **unenveloped** response in the API (001 §13.1) — the client saves the raw body via the OS share/save sheet (`ACTION_CREATE_DOCUMENT` or share intent), never parses it beyond size/error handling. `402 LIMIT_EXCEEDED` (`exportsPerDay`) maps to a friendly retry-tomorrow message in `ApiErrorUserMessage`.
- **Delete account** (settings entry, all users — MUST be reachable without contacting support, store requirement): two-step confirmation naming the consequences; when `GET /families/me` shows the caller as the only parent (or sole member), the confirmation MUST carry the 008 §4.2 cascade wording ("you are the only parent — this deletes the family for everyone"). On `204`: call `FirebaseAuth.currentUser.delete()` (008 §1.3); on its failure follow 008 §1.3's **sign out → sign in → re-run delete** recovery (a bare retry is a trap — `requires-recent-login` never clears by retrying), with the sign-out action reachable from the failure state itself; on success clear **all** local state — fix queue, `deviceId`, any cached config/ETags, **and the export artifacts of 008 §3.1** (a plaintext export must never outlive the account it belongs to).
- **Delete family** (settings entry, parents only): two-step confirmation naming the irreversible loss of the whole family's history for all members; recommended: require typing the family name (008 §5.4). On `204` the app returns to the family-less home (the account survives).
- Other members discover a deleted family via `FAMILY_NOT_FOUND` (008 §5.2) — the existing family-less handling (§12.2's home behavior) is the landing, no new screen.
- Test checklist additions (§16 applies): confirmation gating (no call before the second confirm), cascade wording trigger condition, Firebase-delete ordering after `204` and its failure/retry path, local-state wipe completeness, export share-sheet handoff with unparsed body, `exportsPerDay` message mapping.

### 12.5 Back affordance (normative)

The system back gesture always worked here — Navigation Compose pops the graph for free. What was missing was any **visible** way out: `FindlyTopBar` has accepted a `navigationIcon` since A1 and **not one of the 14 screens ever passed one**, so every screen past Home rendered a bare title. Users look for a back control; gesture-only navigation reads as a dead end, and the gesture is itself hidden on 3-button navigation. (iOS had the far worse version of this same gap — no back mechanism at all — see specs/004 §2.5.)

**Rule (MUST):** the decision is made **once**, in `FindlyNavHost`, and published through a `LocalNavBackAction` composition local:

- Non-null iff `navController.previousBackStackEntry != null`, read via `currentBackStackEntryAsState()` so it recomposes as the stack changes (a bare `previousBackStackEntry` read is evaluated once and then goes stale).
- `FindlyTopBar` renders a themed back control when `LocalNavBackAction` is non-null and no explicit `navigationIcon` was passed. Screens MUST NOT each thread their own `onBack` — that is precisely how all 14 ended up with none.
- The control carries `contentDescription = "Back"` for TalkBack.

This deliberately mirrors iOS's `navBarBackAction` environment value (specs/004 §2.5), so the two clients answer "can I go back from here?" the same way.

- `AppConfig` (typed wrapper over `BuildConfig` fields `BASE_URL`, `AUTH_MODE`, `FIREBASE_PROJECT_ID`, A2's `MAPS_API_KEY`, and A6's `JOIN_LINK_HOST` — 007 §1): debug build points `BASE_URL` at `http://10.0.2.2:7071/api/` (the Android emulator's documented loopback alias to the host machine, where `func start` listens locally — not a third-party URL) with `AUTH_MODE=insecure-local`; release build points at an obviously-fake placeholder (`https://CHANGE-ME.azurewebsites.net/api/`) with `AUTH_MODE=firebase`, both marked `TODO(H1)` for the real Function App URL / Firebase project ID. `MAPS_API_KEY` defaults to an empty string in both build types, read from a Gradle project property (`-PMAPS_API_KEY=...` or a gitignored local override) — never hardcoded, never committed (docs/security-review-checklist.md §5); `ui/map/PlaceholderMapRenderer` is used regardless of its value until H1 lands a real map-tile SDK.
- `google-services.json` is gitignored (`mobile/android/.gitignore`) and, as of H1, present locally (never committed) — the real Firebase project's file, downloaded by the user from the Firebase console per `docs/azure-setup.md` §3. The `com.google.gms.google-services` Gradle plugin (root `build.gradle.kts`) + `com.google.firebase:firebase-bom`/`firebase-auth` + `org.jetbrains.kotlinx:kotlinx-coroutines-play-services` (`app/build.gradle.kts`) are now applied; `FirebaseAuthProviderStub` (§7) is replaced by the real `FirebaseAuthProvider`. `StubPushTokenProvider` (§9) is unchanged — FCM wiring is a separate follow-up, not part of this H1 slice.
- No keystores, service-account keys, Maps API keys, or other secrets exist in this task's diff. `google-services.json` itself is not treated as a secret (its API key is client-embedded-by-design, restricted via Firebase project security rules, and appears in every shipped APK) but stays gitignored per convention/least-surprise.

## 14. Testing strategy

Plain JUnit4, JVM-only, no Robolectric, no emulator, no instrumented tests — everything under `app/src/test/`. Networking tests use `okhttp3.mockwebserver.MockWebServer` (a real local JVM socket server — exercises the actual Retrofit/OkHttp/kotlinx.serialization stack without any Android dependency, not a hand-mocked substitute). ViewModel logic is tested by constructing `HomeStateHolder` directly with a `TestScope`/`StandardTestDispatcher` and fakes — the thin `HomeViewModel` Android wrapper itself is not separately tested (nothing to test beyond delegation). Deliberately **not** tested in A1 (no toolchain to run them, and/or genuinely deferred): Compose UI rendering/screenshot tests, `LocationSyncWorker`'s real WorkManager scheduling, Room (not present — §10.4).

Every test in this task's diff was written and read for correctness but **not executed** — no Gradle/JDK/Android SDK toolchain exists in this sandbox. CI (`.github/workflows/android.yml`, still a structure-check stub) must run them for real before this is considered green.

**A2 addition:** `LocateStateHolderTest` drives the §6.2 poll loop with `kotlinx-coroutines-test`'s virtual time (`advanceTimeBy(2000) + runCurrent()` per cycle, not `advanceUntilIdle()`, which would race the whole sequence to completion in one shot and hide the intermediate `Polling` states under test) — the real 2 s interval never actually elapses. `GeofencesStateHolderTest` scripts the §7.2 409-conflict re-fetch by reassigning the fake's `getGeofencesResult` between the failing `save()` call and the conflict handler's own re-`GET`. Every new `<Feature>ViewModel` is unexercised directly, same convention as A1's `HomeViewModel` — all logic lives in, and is tested through, the corresponding `<Feature>StateHolder`.

**H1 addition:** a JDK + Android SDK were installed locally this session (`docs/implementation-handoff.md`'s H1 CI log), so `SignInStateHolderTest`/`AuthProviderFactoryTest`'s updates were written **and actually run** red-then-green locally via `./gradlew test`, not just written-and-read as A1/A2's tests were — the first task in this project to get that. `runCurrent()` (not `advanceUntilIdle()`) is used wherever a `backgroundScope`-launched coroutine needs draining, per the H1 CI log's `advanceUntilIdle()` finding.

## 15. Error cases

Client-side error handling per 001 §10, all driven through `ApiErrorMapper` (§6.1) — no code is invented, all 27 catalog codes are represented as named `ApiError` subtypes. `AUTH_TOKEN_EXPIRED` triggers the retry-once path (§6.4); all other errors surface to the caller as `ApiResult.Failure` for the ViewModel layer to render (rendering itself is A2). `VALIDATION_FAILED` on `POST /locations` additionally drives the fix-queue's rejection path (§10.3) by parsing `details.fields` entries of the shape `"fixes[<index>].<prop>"` to identify offending `fixId`s.

## 16. Test checklist

- Envelope: success unwraps `data`+`features`; `removeMember` yields `Success(Unit, features = null)`; `getGeofences` 304 yields `Success(null, features = null)`; error unwraps into the matching `ApiError` subtype with `requestId` preserved.
- Errors: **every** 001 §10 code (all 27) maps to its named `ApiError` subtype, not `Unknown`; code-specific `details` (fields/reason/limit/currentEtag/deviceSettings/retryAfterSeconds/max) decode correctly.
- Auth-retry: a call receiving `AUTH_TOKEN_EXPIRED` triggers exactly one `currentIdToken(forceRefresh = true)` and one retry; a second expiry surfaces as `Failure`.
- Device registration: request omits absent `pushToken`/`locationPushToken`; `deviceId` is a stable UUIDv4 per uid from `DeviceIdProvider`; a push-token refresh triggers exactly one `registerOrUpdate` call carrying the new token.
- Fix-queue: `nextBatch()` idempotent (same `batchId`+fixes) until resolved; `markBatchAccepted` removes exactly the acked fixes; `markBatchRejected` drops only named offenders and the remainder gets a fresh `batchId` on the next call; `markBatchFailedTransient` changes nothing (retry-safe); new `enqueue()` during an in-flight batch never joins it; `maxSize` cap is respected; empty pool → `null`, never an empty batch.
- `LocationSyncCoordinator`: success/transient-failure/rejection/paused outcomes each drive the correct `FixQueueStore` call.
- `HomeStateHolder`: `Loading → SignedOut` when unauthenticated; `Loading → SignedIn` + successful registration state; registration failure surfaces an error state without crashing the state machine.
- Groups (005 §7 client side): `GroupsApi` request-building per §5 row (routes, bare-204 handling on §12.5/12.8/12.9); the six group error codes map + render; `GroupsListStateHolder`/`GroupMapStateHolder`/create/join StateHolder logic against fakes (state chips from `state`, countdown from `endsAt`, policy copy per 005 §2.1, deep-link code prefill); no battery/device fields anywhere in group DTOs.
- Phone sign-in (006 §10, Android side): `PhoneNumberNormalizerTest` covers every 006 §3 rule; `SignInStateHolderTest` covers every 006 §4.1 transition against a fake `AuthProvider` — happy path, every `PhoneAuthError` landing in its specced state/message, instant verification from both `SendingCode` and `EnteringCode`, resend blocked until the virtual-time cooldown hits 0 then exactly one re-invocation, `INVALID_CODE` staying on code entry vs `CODE_EXPIRED` returning to phone entry; `DevAuthProvider` two-step shape + unsigned-JWT token; no unit test imports the Firebase SDK.
- Design system: every component file reads only `FindlyTheme.*` (reviewer spot-check — no automated enforcement in A1).

## Open questions

None — this spec resolves every Android-client concern needed to start A1; unresolved platform-delivery risk stays tracked in 000 §Open Items (O1–O4 as referenced above).
