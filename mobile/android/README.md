# Findly — Android app (Kotlin)

Native Android app, Kotlin + Jetpack Compose, single Gradle module (`app/`), min SDK 26 / compile+target SDK 36 / JDK 17. Wire contract: [`specs/001-api-contract.md`](../../specs/001-api-contract.md). Product context + open items: [`specs/000-overview.md`](../../specs/000-overview.md). **The normative spec for everything in this directory is [`specs/003-android-client.md`](../../specs/003-android-client.md)** — module architecture, the design-system token contract, the full endpoint→client mapping, auth/device/push-token/fix-queue models, and what's deliberately deferred. Read it before changing anything here.

## Status (A1 — foundation, done; A2 — feature screens, done)

**Done (A1):** Gradle project skeleton; a typed network client for the complete 001 API (§3–§7); the §10 error catalog as a sealed `ApiError` hierarchy; the design-system layer (tokens + `FindlyTheme` + nine stateless components, light+dark); `AuthProvider` (dev/stub + Firebase placeholder); `PushTokenProvider` (stub); device identity + registration; the offline fix-queue `batchId` idempotency model (in-memory store — see spec §10.4 for why persistence is deferred); a navigation scaffold + one proof screen ("Home"). All logic outside Compose UI and the thin Android-framework touch points (`FindlyApplication`, `MainActivity`, `SharedPreferencesDeviceIdStore`, `AndroidDeviceInfoProvider`, `LocationSyncWorker`) is pure Kotlin/JVM with JUnit tests — no Robolectric, no emulator.

**Done (A2):** live map (§5.2, behind a swappable `MapRenderer` — `PlaceholderMapRenderer` until H1 provisions a Maps API key), history replay with cursor pagination (§5.3), geofence editor with ETag-aware save + 409-conflict reconciliation (§7.1–7.2), locate-to-request UI polling every 2 s until terminal (§6), device/family settings with parent-vs-owner gating (§4.2–4.3/§3.5–3.6), invites — create + accept (§3.3–3.4). Three new design-system components (`FindlyTextField`, `FindlySwitchRow`, `FindlySectionHeader`, specs/003 §4.3). The A1 review's duplicated auth-retry logic across `FindlyApiClient` is now a single `withAuthRetry` helper (specs/003 §6.4). Same pattern as A1 throughout: pure `<Feature>StateHolder` + thin `<Feature>ViewModel`, JUnit-tested with fakes, no Robolectric/emulator. **Still not started:** real permission-request UI, real WorkManager/foreground-service scheduling, Room-backed queue persistence, real platform geofencing/foreground service (all explicitly deferred per specs/003 §2/§11).

**Waived (H1 — Azure/Firebase provisioning, still `human`/pending):** no real `google-services.json` (stays gitignored/absent — CI and local builds alike generate an obviously-fake placeholder at build time, `.github/workflows/android.yml`), no real backend base URL, no real Firebase project, no real Maps API key. Everything that needs these is stubbed behind an interface — `AuthProvider`, `MapRenderer`, `AppConfig`'s `BASE_URL`/`FIREBASE_PROJECT_ID`/`MAPS_API_KEY` — and documented in specs/003 §13. Wiring the real thing is a same-interface swap, not a redesign. `PushTokenProvider` is no longer one of these: A9 (specs/009-device-runtime.md §5) wired the real `RealPushTokenProvider`/`FindlyMessagingService` against the placeholder `google-services.json` — it compiles and runs against a real (if fake) Firebase project either way, the only thing H1 still gates is push actually reaching a real device.

## Design-swappable UX

`ui/designsystem/` is the only place a styling constant may exist (color/typography/spacing/corner/elevation tokens, `FindlyTheme`, twelve stateless presentational components as of A2). Screens compose those components and are driven by ViewModels; nothing outside `ui/designsystem/token/` hardcodes a `Color`, `.dp`, or `.sp`. Both light and dark token sets ship from day one. See specs/003 §4 for the full token vocabulary and default values, and `ui/designsystem/components/ComponentGalleryPreview.kt` for a side-by-side preview of every component in both themes.

## Build

```bash
cd mobile/android
./gradlew test    # JUnit unit tests (pure JVM — no emulator, no Robolectric)
./gradlew build    # full compile
```

Gradle (Kotlin DSL), AGP 9.2.0, Kotlin 2.3.0, Gradle 9.4.1, JDK 17. `gradlew`/`gradle-wrapper.jar` are committed as of A9 — the first task run against a real JDK/Gradle/Android-SDK toolchain generated them (`gradle wrapper --gradle-version 9.4.1 --distribution-type bin`) and `./gradlew` works directly from a checkout now. CI (`.github/workflows/android.yml`) still installs Gradle directly rather than relying on the wrapper, since that predates this change and is harmless either way.

## Shape (implemented — see specs/003 §3 for the full package tree)

- **`network/`** — DTOs matching every 001 §3–§7 wire shape, `ApiError`/`ApiErrorMapper` (the §10 catalog), `ApiResult`, five port interfaces (`FamilyApi`/`DevicesApi`/`LocationsApi`/`LocateApi`/`GeofenceApi`) implemented by `FindlyApiClient` on top of the raw `FindlyApiService` Retrofit interface (Retrofit + OkHttp + kotlinx.serialization).
- **`auth/`** — `AuthProvider` (Firebase Auth ID-token source), `DevAuthProvider` (unsigned-JWT dev stub), `FirebaseAuthProviderStub` (H1 placeholder).
- **`push/`** — `PushTokenProvider` (FCM registration-token source, distinct from the auth ID token), `RealPushTokenProvider` (A9), `FindlyMessagingService` (A9, the real `FirebaseMessagingService`).
- **`device/`** — `DeviceIdProvider`/`DeviceIdStore` (per-uid UUIDv4), `DeviceInfoProvider`, `DeviceRegistrar` (§4.1).
- **`queue/`** — `FixQueueStore`/`InMemoryFixQueueStore` (§5.1's `batchId` idempotency model), `LocationSyncCoordinator`, `worker/` (WorkManager scaffold, untested by design; `ScheduleRebuilder` seam added by A9).
- **`pushmessages/`** — FCM `data.type` discriminator parser (§8); A9 adds the four per-type handlers + `PushMessageDispatcher` (specs/009-device-runtime.md §5).
- **`location/`** — A9's `LocationCapturer` seam (specs/009-device-runtime.md §1) for one-shot fix capture, awaiting A10's real `FusedLocationProviderClient`-backed implementation.
- **`ui/designsystem/`, `ui/nav/`, `ui/home/`** — see above.
- **A2:** `ui/map/` (`MapStateHolder`/`MapViewModel`/`MapScreen`, `MapRenderer`/`PlaceholderMapRenderer`), `ui/history/`, `ui/geofences/`, `ui/locate/`, `ui/settings/`, `ui/invites/` — each following the same `StateHolder` (pure) + `ViewModel` (thin) + `Screen` (Compose) shape as `ui/home/`, specs/003 §12.1.

## Original planning notes (still accurate for A2's deferred items — real permission UI, WorkManager scheduling, native geofencing)

- **Location sync:** `FusedLocationProviderClient`; intervals ≥ 15 min via **WorkManager** periodic work; 5/10-min intervals require a **foreground service** with a persistent low-priority notification (Play-policy compliant for family tracking). "1 day" = first unlock/network of the device-local day (000 §O3).
- **Geofencing:** `GeofencingClient` (native, battery-efficient); re-register on `GEOFENCE_CONFIG_CHANGED` push or `geofenceEtag` change (001 §5.1 piggyback).
- **Push:** Firebase Cloud Messaging; handle the four data-message types of 001 §8. `LOCATE_REQUEST` → high-priority wake → single high-accuracy fix → `POST /locate-requests/{id}/fulfill`.
- **Permissions:** `ACCESS_FINE_LOCATION` → `ACCESS_BACKGROUND_LOCATION` staged request; Play Store background-location review prep (000 §O2; staged flow documented in specs/003 §11).
