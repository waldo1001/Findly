# Specs — process

This project is **spec-driven**: no implementation code is written before (a) a spec exists here and (b) failing tests exist. Backend, Android, and iOS are built by independent parallel sessions that coordinate **only via these specs** — a spec must therefore be exhaustive enough to build against with zero ambiguity.

## Numbering & naming

`NNN-topic.md`, three digits, ascending. Existing:

| Spec | Owns |
|---|---|
| [`000-overview.md`](000-overview.md) | Canonical product spec: features, roles, architecture, constraints, decisions log, open items |
| [`001-api-contract.md`](001-api-contract.md) | **Single source of truth for every wire shape**: endpoints, request/response JSON, push payloads, error codes, auth |
| [`002-storage-schema.md`](002-storage-schema.md) | Table/blob layouts, JSON schemas, concurrency rules, retention |
| [`003-android-client.md`](003-android-client.md) | Android client: networking, auth provider, design-swappable UX layer, screens |
| [`004-ios-client.md`](004-ios-client.md) | iOS client: `FindlyKit` SPM package, auth provider, design-swappable UX layer, screens |
| [`005-temporary-groups.md`](005-temporary-groups.md) | Temporary groups: concept, lifecycle/expiry policies, privacy guarantees, limits |
| [`006-phone-auth.md`](006-phone-auth.md) | Phone-number-only sign-in: flow, normalization, dev mode, Firebase requirements, abuse/cost posture |
| [`007-public-join-links.md`](007-public-join-links.md) | Public join links: `https://{JOIN_LINK_HOST}/g#CODE`, static landing page, `.well-known` files, on-device QR, SWA hosting |
| [`008-privacy-endpoints.md`](008-privacy-endpoints.md) | Privacy: per-member data export, account deletion (last-parent cascade), family deletion, self-service web deletion page |
| [`009-device-runtime.md`](009-device-runtime.md) | Device runtime: capture policy & accuracy tiers, durable fix queue, per-platform scheduling, pause, push handling, geofence registration lifecycle, permissions |
| [`010-app-shell-and-screen-ux.md`](010-app-shell-and-screen-ux.md) | App shell & screen UX: map-first root + navigation drawer, map camera policy + roster bottom sheet, profile-dead-end → onboarding routing, Devices screen, invite create/accept UX |

Future specs claim the next number (e.g. `011-web-viz.md`, `0xx-subscriptions.md`).

## Required sections in every spec

1. **Goal** — what and why, one paragraph.
2. **Normative content** — the actual contract. Use MUST/SHOULD/MAY deliberately.
3. **Error cases** — explicit, with codes from the 001 catalog (never invent codes elsewhere).
4. **Test checklist** — what a conforming implementation's tests must cover.
5. **Open questions** — MUST be empty before implementation starts. A spec with open questions is not buildable; move unresolved items to `000-overview.md` §Open Items with an owner.

## Rules

- **Wire shapes live in 001 only.** Other specs link to 001; they never redefine a request/response/payload shape.
- **Storage shapes live in 002 only.** Same rule.
- **Change control:** specs change via PR *before* the code that needs the change. A code PR that silently diverges from spec is a bug, even if the code is better — fix the spec first.
- **Every code PR references its spec** (e.g. `specs/001 §6`).
- **Mutation thresholds only ratchet up.** Current backend gate: `break: 60` (see `backend/stryker.config.json`); raise it as coverage matures, never lower it.
