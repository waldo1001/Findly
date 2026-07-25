# Findly — backend

Azure Functions (consumption), TypeScript, Node 20, **v4 programming model**. The wire contract is [`specs/001-api-contract.md`](../specs/001-api-contract.md); storage layouts are [`specs/002-storage-schema.md`](../specs/002-storage-schema.md). Nothing here may diverge from those specs — fix the spec first.

## Layout (hexagonal)

```
src/
├── functions/     # v4 app.http() registrations ONLY — thin, no logic, excluded from mutation
├── http/          # envelope.ts, errors.ts (the 001 §10 catalog), authGuard.ts, validate.ts (zod)
├── domain/        # PURE business logic — zero Azure/Google imports. plan.ts holds PLAN_MATRIX.
│   ├── family/  device/  location/  locate/  geofence/
├── ports/         # interfaces the domain depends on:
│   │              #   repositories.ts (FamilyRepo, UserRepo, DeviceRepo, LastKnownRepo,
│   │              #   InviteRepo, EntitlementsRepo, LocateRequestRepo, IdempotencyRepo, UsageRepo)
│   │              #   historyStore.ts, pushSender.ts, tokenVerifier.ts, support.ts (Clock, IdGenerator —
│   │              #   IdGenerator.next(length) returns `length` chars of [A-Za-z0-9]; DOMAIN adds the
│   │              #   fam_/lr_ prefix; the SeqIdGenerator fake pads its sequence to `length`)
└── adapters/      # real implementations: tables/ + blobs/ (@azure/data-tables / @azure/storage-blob;
                   #   AzureNamedKeyCredential with the well-known devstoreaccount1 key when the endpoint
                   #   host is 127.0.0.1/localhost i.e. Azurite, DefaultAzureCredential otherwise — 002 §1),
                   #   push/fcmV1Sender.ts, auth/firebaseJoseVerifier.ts (jose)
test/
├── fakes/         # InMemory* repos, FixedClock, SeqIdGenerator, FakePushSender, StubTokenVerifier
├── unit/          # domain/ + http/ tests — MUST run without Azurite, network, or Azure SDKs
└── integration/   # storage-adapter tests against a real Azurite (specs/002 §6) — see below
```

**Rule:** `src/domain` + `src/http` are pure and mutation-tested. `src/adapters` + `src/functions` are thin integration surface (integration-tested against Azurite; excluded from mutation).

## Commands

| Command | What |
|---|---|
| `npm test` | Unit tests (Vitest). Never needs Azurite. |
| `npm run test:watch` | The red–green loop |
| `npm run test:integration` | Storage-adapter integration tests against Azurite (specs/002 §6) — see below |
| `npm run mutation` | StrykerJS — same gate as CI. Thresholds in `stryker.config.json` (`break: 60`, ratchet-up only). |
| `npm run build` | `tsc` type-check + emit |
| `npm run dev:storage` | Azurite (local Table/Blob emulator), state in `.azurite/` |
| `npm run dev` | Build + `func start` (requires [Azure Functions Core Tools](https://learn.microsoft.com/azure/azure-functions/functions-run-local) v4) |

## Integration tests (specs/002 §6)

`test/integration/**/*.test.ts` exercise the real adapters (`@azure/data-tables`/`@azure/storage-blob`) against a running Azurite — a separate Vitest project (`vitest.integration.config.ts`), deliberately excluded from the default `npm test` glob so unit tests stay Azurite-free per policy.

```bash
npm run dev:storage        # start Azurite in one terminal (state in .azurite/, gitignored)
npm run test:integration   # in another terminal
```

Tables/containers are created on demand by the tests themselves (Azurite doesn't auto-create them the way the one-time Azure provisioning in `docs/azure-setup.md` does); each test uses a fresh random `familyId`/`deviceId` so parallel test files never collide on shared state.

Current coverage of the 002 §6 checklist:

- ✅ Guarded-update races: `LastKnown` only-newer (`lastKnownRace.test.ts`), `Usage` increment retry (`usageIncrementRace.test.ts`).
- ✅ Append interleaving (two concurrent writers to one day blob both land; reader sorts), the UTC-midnight day-blob split, cursor round-trip across a day boundary with multi-device merge, and event dedupe/filtering (`historyBlobStore.test.ts`).
- ✅ Group sweeper (`groupSweeper.test.ts`, B12): bucket-walk + per-policy physical deletion (delete/grace/archive) against real `Groups`/`GroupCodes`/`GroupExpiry`/`GroupLastKnown`/`Users` rows, the grace two-phase transition end to end, crash-mid-hard-delete convergence (orphaned expiry row cleanup), and expiry-row re-bucket self-healing after a partial `PATCH endsAt` move.
- ✅ Account-deletion adapters (B18): `deleteUserPrefix`/`eraseUserFromEvents` against real append blobs (`historyBlobStore.test.ts`) — the events filtered rewrite erasing only the subject's lines, including a genuinely concurrent §3.2 append to the same day blob (no other member's line lost); `LastKnown`/`IdempotencyMarkers` partition wipes and `LocateRequests`' `requestedBy`-OR-`targetUserId` OData filter against real Table Storage, plus `Users.deleteProfile`'s idempotent not-found swallow (`accountDeletionAdapters.test.ts`).
- ⏸ **Deferred, not yet possible on this branch:** invite single-use race (owned by task B3's `InvitesTableRepo`) and the geofence ETag flow incl. `"0"` sentinel + 412→409 (owned by task B5's full config read/write — today's `BlobGeofenceConfigRepo` only reads the ETag for the §5.1 piggyback). Neither adapter exists yet at the time of writing; add their integration tests to this same suite when those tasks merge. Also still missing (owned by B9/B10/B11, not this task): group join membership-insert race, code-rotate crash sequence, and `GroupLastKnown` only-newer race.

## TDD workflow (non-negotiable)

1. Write the failing test in `test/unit/…` (start from the checklist in specs/001 §11).
2. Run it. **Watch it fail.**
3. Implement the minimum in `src/domain` / `src/http`.
4. Green → refactor → `npm run mutation` before pushing.

## Local settings

Copy `local.settings.json.example` → `local.settings.json` (gitignored). `AUTH_MODE=insecure-local` accepts unsigned JWTs for local testing (specs/001 §2.3) and must refuse to run in Azure.
