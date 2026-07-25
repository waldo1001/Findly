# Security review checklist

Run against **every task's diff before it merges** — `/dev-loop` spawns a dedicated security reviewer with this checklist; manual sessions run it themselves. The reviewer's verdict is either an explicit **"approve"** or a findings list (severity + file + line + fix); silence is not approval.

Scope of review: the task's full diff (`git diff <merge-base>..<branch>`), all **newly tracked files** (`git ls-files` delta), and any change under `.github/`.

## 1. Secrets — nothing sensitive may ever be committed

- Scan the diff and every newly tracked file for secret material:

  ```bash
  git diff $(git merge-base main <branch>)..<branch> | \
    grep -nEi 'BEGIN [A-Z ]*PRIVATE KEY|AccountKey=|SharedAccessSignature=|private_key_id|"private_key"|AIza[0-9A-Za-z_-]{30,}|client_secret|x-functions-key|eyJ[A-Za-z0-9_-]{20,}\.eyJ|(password|passwd|pwd)[[:space:]]*[:=][[:space:]]*['\''"][^'\''"]{4,}'
  ```

  (Key *files* — `.p8`/`.p12`/keystores/service-account JSON — are caught by the newly-tracked-files check below, not by content grep; don't flag prose that merely mentions them.)

  Treat hits as findings unless demonstrably a fake placeholder (e.g. `your-firebase-project-id`, `fcm-token…`). Placeholders MUST be obviously fake — never realistic-looking values.
- Secret-bearing files MUST remain untracked and ignored — verify none appear in `git ls-files` and `git check-ignore` still covers: `local.settings.json`, `.env*`, `*.p8`, `*.p12`, `*.jks`, `*.keystore`, `keystore.properties`, `google-services.json`, `GoogleService-Info.plist`, `serviceAccountKey*.json`.
- No secrets in test fixtures, code comments, spec examples, or committed logs/artifacts.
- Runtime secrets live only in Function App settings / GitHub Actions secrets (specs/000 §O6 tracks the single accepted stored key, `FCM_SERVICE_ACCOUNT_JSON`, server-side only).

## 2. CI/CD security (any change under `.github/`)

- **OIDC only.** Azure auth stays `azure/login` with `AZURE_CLIENT_ID/TENANT_ID/SUBSCRIPTION_ID` repo *variables* + federated credential. Findings: publish profiles, service-principal passwords, storage keys, or any long-lived cloud credential added as a secret.
- **Least privilege.** Every job keeps an explicit or default-minimal `permissions:` block; `id-token: write` appears **only** on the deploy job. New scopes (e.g. `contents: write`, `pull-requests: write`) need a stated reason.
- **No `pull_request_target`** (or `workflow_run` on untrusted artifacts) that checks out or executes PR-head code — fork PRs must never run with secrets/write tokens.
- **Script injection.** No untrusted context (`github.event.pull_request.title`, branch names, issue bodies, commit messages) interpolated with `${{ }}` directly into `run:` — route through `env:` and quote.
- **Action pinning.** First-party publishers (`actions/`, `Azure/`, `azure/`, `gradle/`) at least major-version-pinned; any other third-party action pinned to a full commit SHA.
- Secrets are never echoed, never written into build artifacts; artifact uploads exclude settings files.
- Deploy remains gated to pushes on `main` after test + mutation.

## 3. Backend code

- **Auth guard everywhere.** Every new HTTP function goes through the specs/001 §1.5 guard; the only endpoints allowed for users without a **profile** are §1.5.3's four bootstrap ones, and family-scoped endpoints reject family-less callers per §1.5.4. No route bypasses bearer verification. Timer functions have no caller — verify they take no input and log no location payloads.
- `AUTH_MODE=insecure-local` MUST refuse to run in Azure (`WEBSITE_INSTANCE_ID` check, specs/001 §2.3) — verify the check wasn't weakened, inverted, or made configurable.
- **Validation before use.** All bodies/query/path/header inputs go through zod (`src/http/validate.ts`); no unvalidated value reaches storage or push adapters.
- **Query injection.** Never string-concatenate user input into Table Storage OData `filter` expressions — use the SDK's escaping/`odata` template helper.
- **Role & ownership checks** per specs/001 §1.6: parent-only mutations, `X-Device-Id` ownership, locate-poll requester-only; group routes mask existence to non-members (`GROUP_NOT_FOUND`, specs/001 §12) and enforce owner-only controls.
- **Group privacy invariants** (specs/005): `GroupLastKnown` rows and every §12 response carry position-only fields (no `deviceId`/`batteryPct`/`source`); the §5.1 history append is gated on the caller having a family; expired-group paths stay unreadable (lazy checks) and sweeper deletion covers every group artifact.
- **No internal leakage.** Unhandled errors → generic `INTERNAL_ERROR`; no stack traces, storage errors, or dependency messages in response bodies.
- **Privacy in logs.** This app handles children's location data: log IDs and counts, never coordinates, push tokens, **or phone numbers**, at info level and above.
- **Write-only tokens.** `pushToken`/`locationPushToken` never appear in any response (specs/001 §4.1).

## 4. Dependencies

- `npm audit --omit=dev` → zero high/critical in production dependencies (dev-chain advisories: note, don't block).
- New dependencies: well-known packages only, exact-name check against typosquats, justified in the task report.

## 5. Mobile (once A1/I1 exist)

- Firebase config files (`google-services.json`, `GoogleService-Info.plist`) stay untracked; signing material (keystores, certs, provisioning profiles) only via CI secrets, base64-encoded, never in the repo.
- No hardcoded API base URLs pointing at third parties; TLS only; no cleartext-traffic exemptions.
- Intent/deep-link inputs validated before use (invite codes, `findly://group-join` codes, 007 https-link fragments — pure whitelist normalization before any network call; wrong host/path ignored, never mis-routed).
- **Phone auth (specs/006):** no Firebase test phone number + OTP pairs committed anywhere (docs/tests use obviously fictional `+3247000000x` placeholders); phone numbers are PII consumed only by the Firebase SDK — never logged, never sent to our backend; the SMS region policy (006 §6.3 modes) is not widened outside its normative ordering (open mode only after App Check is *enforced*) and App Check registration is not weakened without explicit sign-off.
- **Join links (specs/007):** the join code is a capability — it travels **only in the URL fragment** (never path/query, so never in server/CDN logs), is never logged client- or server-side, and QR codes are generated **on-device only** (no networked QR service). The landing page stays fully static: no API/storage calls, no analytics/third-party resources, no code validation (no existence oracle), no cookies/localStorage. The W1 deploy workflow keeps `contents: read` + `id-token: write` only, with the SWA token fetched at run time via OIDC — never stored.
