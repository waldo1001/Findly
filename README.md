# Findly

A private, family-only location tracking app ("Find My Family" style) for Android and iOS phones/tablets. Every family member sees every other member on a live map, devices report their position on a battery-friendly configurable interval, anyone can request a live fix of anyone ("push-to-locate"), movements and geofence events are stored as replayable history, and geofence enter/exit events notify the rest of the family's devices.

Private family app. Cheap to run (target: a few euros per month on Azure). Battery efficiency is a hard requirement.

## Repo map

| Path | What |
|---|---|
| [`specs/`](specs/) | **Start here.** All specifications. [`001-api-contract.md`](specs/001-api-contract.md) is the single source of truth for every wire shape. |
| [`backend/`](backend/) | Azure Functions (TypeScript, Node 20, v4 programming model) |
| [`mobile/android/`](mobile/android/) | Native Android app (Kotlin) |
| [`mobile/ios/`](mobile/ios/) | Native iOS app (Swift) |
| [`web/`](web/) | Optional map/history visualization (Leaflet on Azure Static Web Apps) — later |
| [`docs/`](docs/) | Operational docs: Azure/GitHub/Firebase setup, implementation handoff |
| [`.github/workflows/`](.github/workflows/) | CI/CD (path-filtered per area) |

## Architecture

```
┌─────────────┐        ┌─────────────┐
│  Android    │        │    iOS      │
│  (Kotlin)   │        │  (Swift)    │
└──────┬──────┘        └──────┬──────┘
       │  Firebase Auth (ID tokens)
       │  HTTPS /api/v1/*            ▲ push wake
       ▼                             │
┌──────────────────────────┐   ┌─────┴─────────┐
│ Azure Functions          │──▶│ FCM HTTP v1   │
│ (consumption, Node 20)   │   │ (→ APNs for   │
│ managed identity ──┐     │   │    iOS)       │
└──────────┬─────────┼─────┘   └───────────────┘
           ▼         ▼
┌───────────────┐ ┌────────────────────┐
│ Table Storage │ │ Blob Storage       │
│ point lookups │ │ JSONL history/day  │
│ (last-known,  │ │  (append blobs)    │
│  roster, ...) │ │ geofence config    │
└───────────────┘ │  (block blob)      │
                  └────────────────────┘
```

- **No database server.** Azure Table Storage for point lookups, Blob Storage (JSON lines) for history.
- **Auth:** users sign in with Firebase Auth; the backend verifies Firebase ID tokens statelessly (JWKS). Azure resources are accessed with managed identity — no credentials in code.
- **Push:** FCM HTTP v1 as the single push API for both platforms (FCM routes to APNs for iOS).
- **Geofencing:** evaluated natively on-device (platform geofencing APIs); the backend stores events and fans out notifications.
- **Subscription-ready:** every family has an entitlements record (`subscriptionStatus: "free"`), every API response carries a `features` object. No billing code exists.

## Process rules (non-negotiable)

1. **Spec-driven.** Every feature starts as a spec in [`specs/`](specs/). No implementation before the spec exists. See [`specs/README.md`](specs/README.md).
2. **TDD.** Red → Green → Refactor. Failing tests first, always.
3. **Mutation testing.** StrykerJS gates the backend pipeline; thresholds only ratchet up.
4. **Review gate.** Every task's diff passes a code review **and** a security review ([checklist](docs/security-review-checklist.md)) before merging — no secrets in the repo, CI/CD stays OIDC/least-privilege.
5. **Parallel sessions.** Backend, Android, and iOS are built by independent sessions that coordinate **only via the specs**. The backlog is worked with `/dev-loop` (e.g. `/dev-loop parallel 3` — dependency-safe concurrent agents; see [docs/implementation-handoff.md](docs/implementation-handoff.md)).

## Quickstart (backend)

```bash
cd backend
npm ci
npm test            # unit tests (no Azurite needed)
npm run mutation    # StrykerJS mutation testing
npm run dev         # local Functions host (requires Azurite + Azure Functions Core Tools)
```

## Setup & status

- Azure / GitHub / Firebase provisioning (one-time, manual): [`docs/azure-setup.md`](docs/azure-setup.md)
- Current implementation status and next tasks: [`docs/implementation-handoff.md`](docs/implementation-handoff.md)

> Naming note: renamed from "Where's Waldo" to **Findly** (2026-07-25). "Where's Waldo/Wally" is the book franchise's registered trademark — unsafe for a public store listing, so the public name and all internal identifiers are now **Findly** (bundle ids `com.findly.ios` / `com.findly.android`). See 000 §O10.
