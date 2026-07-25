# Findly — project instructions

Private family location-tracking app: Android (Kotlin) + iOS (Swift) + Azure Functions backend (TypeScript, Node 20, v4 model) + Table/Blob Storage (no database server) + FCM HTTP v1 push + Firebase Auth. Cost target: a few euros/month.

## Non-negotiable process

1. **Spec-driven.** No implementation code before a spec exists in `specs/`. `specs/001-api-contract.md` is the single source of truth for every wire shape (requests, responses, push payloads, error codes). `specs/002-storage-schema.md` owns all storage layouts. If code needs something the spec doesn't define, update the spec first (separate commit), then code.
2. **TDD, strictly.** Red → Green → Refactor. Write the failing test, run it, watch it fail, then implement. Never write implementation before its failing test exists.
3. **Mutation gate.** Backend: StrykerJS thresholds in `backend/stryker.config.json`. Thresholds may only be raised, never lowered.
4. **Review gate.** Every task's diff gets a **code review AND a security review** (`docs/security-review-checklist.md`) before it merges — no secrets in the codebase, ever; CI/CD stays OIDC + least-privilege. `/dev-loop` (`.claude/skills/dev-loop/`) automates the gate; manual sessions run it explicitly before committing.
5. **Parallel sessions.** Backend / Android / iOS sessions coordinate only via specs — never assume behavior that isn't written in a spec; if you find ambiguity, fix the spec first. `/dev-loop parallel N` runs up to N dependency-safe backlog tasks concurrently in isolated worktrees.

## Where things are

- Current status + your next task: `docs/implementation-handoff.md` (**read this first in a new session**)
- Azure/GitHub/Firebase provisioning (manual, one-time): `docs/azure-setup.md`
- Backend layout & conventions: `backend/README.md` (hexagonal: `src/domain` + `src/http` are pure and mutation-tested; `src/adapters` and `src/functions` are thin integration surface)

## Backend commands

```bash
cd backend
npm test            # vitest unit tests — must never require Azurite
npm run test:watch  # red-green loop
npm run mutation    # stryker (same gate as CI)
npm run build       # tsc
```

## Conventions

- Success envelope `{ "data": ..., "features": ... }`; error envelope `{ "error": { "code", "message", "details?", "requestId" } }`. Error codes come only from the catalog in specs/001 §10 — never invent new ones in code.
- All timestamps ISO 8601 UTC (`Z`). IDs: `fam_`/`lr_` + 20 chars `[A-Za-z0-9]`; device IDs are client-generated UUIDv4.
- Subscription-readiness: limits are always read from the `features` object (derived from `PLAN_MATRIX` in `backend/src/domain/plan.ts`), never hardcoded at call sites.
- No secrets in code or repo. Azure access = managed identity. `local.settings.json` is gitignored; `local.settings.json.example` is the template.
- Commit style: reference the spec in the message (e.g. `backend: family creation (specs/001 §3)`).
