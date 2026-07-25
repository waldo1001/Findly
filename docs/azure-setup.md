# Azure / GitHub / Firebase setup (one-time, manual)

Everything the cloud side needs before the first deploy. Run by a human with `az` CLI (Owner on the subscription) — nothing here lives in CI. Cost target: a few euros/month (consumption Function App + storage transactions).

## 1. Azure resources

```bash
# ---- adjust these ----
LOCATION=westeurope
RG=rg-findly
STORAGE=stfindly          # must be globally unique, 3-24 lowercase alphanumerics
FUNCAPP=func-findly       # must be globally unique
GITHUB_REPO=<owner>/Findly
FIREBASE_PROJECT_ID=<your-firebase-project-id>
# ----------------------

az group create -n $RG -l $LOCATION

az storage account create -n $STORAGE -g $RG -l $LOCATION \
  --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 \
  --allow-blob-public-access false

# Lifecycle policy (normative JSON in specs/002 §4)
# NB: append blobs support ONLY the delete action in lifecycle management (no tiering)
cat > /tmp/lifecycle.json <<'EOF'
{ "rules": [ {
    "name": "history-retention", "enabled": true, "type": "Lifecycle",
    "definition": {
      "filters": { "blobTypes": ["appendBlob"], "prefixMatch": ["history/", "events/"] },
      "actions": { "baseBlob": {
        "delete": { "daysAfterModificationGreaterThan": 400 } } } } } ] }
EOF
az storage account management-policy create --account-name $STORAGE -g $RG --policy @/tmp/lifecycle.json

# Consumption Function App, Node 20, system-assigned managed identity
az functionapp create -n $FUNCAPP -g $RG -s $STORAGE \
  --consumption-plan-location $LOCATION \
  --runtime node --runtime-version 20 --functions-version 4 \
  --assign-identity '[system]'

# Managed identity → data-plane roles on the storage account (specs/002 §1)
PRINCIPAL_ID=$(az functionapp identity show -n $FUNCAPP -g $RG --query principalId -o tsv)
STORAGE_ID=$(az storage account show -n $STORAGE -g $RG --query id -o tsv)
az role assignment create --assignee-object-id $PRINCIPAL_ID --assignee-principal-type ServicePrincipal \
  --role "Storage Table Data Contributor" --scope $STORAGE_ID
az role assignment create --assignee-object-id $PRINCIPAL_ID --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" --scope $STORAGE_ID

# App settings (FCM_SERVICE_ACCOUNT_JSON added in step 3)
az functionapp config appsettings set -n $FUNCAPP -g $RG --settings \
  FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID \
  TABLES_ENDPOINT="https://$STORAGE.table.core.windows.net" \
  BLOB_ENDPOINT="https://$STORAGE.blob.core.windows.net"
```

## 2. GitHub Actions → Azure via OIDC (no secrets)

```bash
# App registration used ONLY by GitHub Actions to deploy
APP_ID=$(az ad app create --display-name gh-findly-deploy --query appId -o tsv)
az ad sp create --id $APP_ID

# Federated credential: trust pushes to main of this repo
cat > /tmp/fedcred.json <<EOF
{ "name": "github-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:${GITHUB_REPO}:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"] }
EOF
az ad app federated-credential create --id $APP_ID --parameters @/tmp/fedcred.json

# Deploy permission, scoped to the Function App only
FUNCAPP_ID=$(az functionapp show -n $FUNCAPP -g $RG --query id -o tsv)
az role assignment create --assignee $APP_ID --role "Website Contributor" --scope $FUNCAPP_ID
```

Then set **repository variables** (Settings → Secrets and variables → Actions → *Variables* — these are identifiers, not secrets; `backend.yml`'s deploy job stays skipped until `AZURE_CLIENT_ID` exists):

| Variable | Value |
|---|---|
| `AZURE_CLIENT_ID` | `$APP_ID` |
| `AZURE_TENANT_ID` | `az account show --query tenantId -o tsv` |
| `AZURE_SUBSCRIPTION_ID` | `az account show --query id -o tsv` |
| `AZURE_FUNCTIONAPP_NAME` | `$FUNCAPP` |

## 3. Firebase (phone-only auth + push) — task H2's runnable checklist

Normative requirements in specs/006 §6; this is the click-path. Sign-in is **phone-number-only** (specs/006) — there is no email/password step anymore.

1. Create a Firebase project at console.firebase.google.com; note the **project ID** → `FIREBASE_PROJECT_ID`. *(Done 2026-07-20: `findly-REPLACEME`.)*
2. **Upgrade to the Blaze plan** (pay-as-you-go) — Phone Auth SMS sending requires it — and set a **Cloud Billing budget alert** (e.g. €5/month). Cost reality: SMS verifications bill per message (~US$0.01 US, ~US$0.06+ Belgium/EU); sign-ins are rare (Firebase refresh tokens keep a device signed in until sign-out/uninstall), so family-scale cost is cents/month — the "few euros/month" target is unaffected. The region allowlist (step 4) is the cost/abuse guardrail.
3. **Authentication → Sign-in method: enable Phone.** Email/Password and every other provider stay **disabled** (specs/006 §1).
4. **Authentication → Settings → SMS region policy** — two operating modes since 2026-07-22 (normative: specs/006 §6.3). **Family mode** (now): allow-list only the countries of real users (currently BE, NL); add a country only when a real user actually has a number there. **Open mode** (convention operation, task H8): all regions — allowed **only after** App Check (step 6) is *enforced* on both platforms, together with raising the budget alert (step 2) to €25/month. Never open regions while App Check is still in monitor mode; if the budget alert ever fires, re-narrow to family mode first and investigate (006 §7 runbook).
5. **Test phone numbers** (Authentication → Sign-in method → Phone → "Phone numbers for testing"): add fictional numbers with fixed OTPs for dev/E2E/store review. The enabled number+code pairs live **only in the console** — an enabled test pair is a working credential; never commit one (docs/tests use obviously fictional `+3247000000x` placeholders). CI is unaffected (unit tests never touch Firebase; the placeholder `google-services.json` stays as-is).
6. **App Check:** register both apps — Android: **Play Integrity** (requires the debug + release **SHA-256 fingerprints** on the Firebase Android app registration; re-download `google-services.json` afterwards); iOS: **App Attest** (DeviceCheck fallback). Leave enforcement for Authentication in **monitor** mode until both apps demonstrably sign in, then enforce (specs/006 §6.5).
7. **Android app:** register package id (e.g. `be.wauters.findly`) **including the step-6 SHA-256s**, download `google-services.json` → `mobile/android/app/` (gitignored).
8. **iOS app:** register bundle id, download `GoogleService-Info.plist` → gitignored; upload the **APNs auth key** (from the Apple Developer account) into Firebase Cloud Messaging settings. **The APNs key is a phone-auth prerequisite** (silent-push app verification, specs/006 §6.6), not just FCM routing — without it, on-device sign-in falls back to reCAPTCHA, which additionally needs the `REVERSED_CLIENT_ID` custom URL scheme in the app target's Info.plist. Simulator development uses test phone numbers (step 5) and needs neither.
9. **FCM sending credential** (the system's only stored key — specs/000 §O6): Project settings → Service accounts → *Generate new private key*, then:
   ```bash
   az functionapp config appsettings set -n $FUNCAPP -g $RG \
     --settings FCM_SERVICE_ACCOUNT_JSON="$(cat serviceAccountKey.json | tr -d '\n')"
   ```
   Delete the local copy afterwards. Hardening backlog: GCP Workload Identity Federation trust to the Function App's managed identity → no stored key at all.
10. **Account reset (one-time, pre-launch — specs/006 §8):** delete all users under Authentication → Users (they are email/password test accounts, unreachable once that provider is off), and wipe all test data in the storage account (all specs/002 §2 table rows and `history/`/`events/` blobs — deleting and recreating tables/containers is the fastest honest way).

## 4. Apple specifics (before iOS push-to-locate works properly)

- Apple Developer Program ($99/yr) — needed for APNs at all.
- The APNs auth key (§3.8) also gates **Firebase phone-auth app verification on device** (specs/006 §6.6) — simulator development works with test phone numbers instead.
- **Apply for the Location Push Service Extension entitlement** (`com.apple.developer.location.push`) via developer.apple.com — justification: family locator app, user-initiated locates. This takes time; apply early (specs/000 §O1).

## 5. Branch protection (the mutation gate's teeth)

GitHub → Settings → Branches → protect `main`: require the status checks **`test`** and **`mutation`** (contexts match the *job names* from `backend.yml`; the PR merge box displays them as "backend / test" etc.) — add **`android-build`** / **`ios-build`** once those apps have real builds. Note: `backend.yml` deliberately has **no path filter on `pull_request`** — a path-filtered required check never reports on non-matching PRs, which would leave every docs/specs/mobile PR stuck on "Expected — waiting for status". Alternatively manage all of this as a repository ruleset (JSON export can then live in `.github/`).

## 6. Verify

1. Push any `backend/**` change to main → `backend` workflow: test → mutation → deploy all green.
2. Sign in on a dev build with a **test phone number** (§3.5), then `curl https://$FUNCAPP.azurewebsites.net/api/v1/families/me -H "Authorization: Bearer <that-session's-id-token>"` → JSON envelope (`PROFILE_NOT_FOUND` for a fresh user is the expected happy sign — specs/001 §1.5).
3. Azure portal → Function App → confirm the **app's data-plane** settings are endpoint URLs only (`TABLES_ENDPOINT`/`BLOB_ENDPOINT`, no account keys) and storage reads succeed via managed identity. Expected and fine: `AzureWebJobsStorage` / `WEBSITE_CONTENT*` connection strings exist — those belong to the Functions *host* (created by `az functionapp create` on the consumption plan), not to the app's data access.

## 7. Join-link host (specs/007) — task H4's runnable checklist

One Azure Static Web App (Free tier) hosts the public join-link landing page, the `.well-known` App/Universal Links files (deployed by W1's workflow), and later the legal pages (H7). No secrets: deploys authenticate via the existing OIDC app registration.

*(Done 2026-07-22: `swa-findly` in resource group `Findly`, subscription "Visual Studio Enterprise Subscription". **`JOIN_LINK_HOST` = `kind-plant-0fb99b003.7.azurestaticapps.net`** — recorded in `mobile/android/app/build.gradle.kts`'s `joinLinkHost` val and `mobile/ios/FindlyKit/.../AppConfig.swift`'s `defaultJoinLinkHost`. RBAC granted to `gh-findly-deploy` (`722f3f16-…`) — Contributor on the SWA resource. Repo variables `AZURE_STATICWEBAPP_NAME`/`AZURE_STATICWEBAPP_RESOURCE_GROUP` (step 2b) both set.)*

```bash
az staticwebapp create -n swa-findly -g Findly -l westeurope --sku Free
az staticwebapp show   -n swa-findly -g Findly --query defaultHostname -o tsv
```

1. Record the returned hostname as **`JOIN_LINK_HOST`** (specs/007 §1) — it goes into both apps' build config (003 §13 / 004 §8) and is effectively permanent once QR codes are printed.
2. Grant the CI principal access so the workflow can fetch the deployment token **at run time** (no stored secret — specs/007 §5):
   ```bash
   az role assignment create --assignee $AZURE_CLIENT_ID --role Contributor \
     --scope $(az staticwebapp show -n swa-findly -g Findly --query id -o tsv)
   ```
   2b. **The W1 workflow (`.github/workflows/web-join.yml`) also needs two GitHub repo variables** (Settings → Secrets and variables → Actions → Variables) before its `deploy` job will run — it's a no-op until both exist:
   - `AZURE_STATICWEBAPP_NAME` = `swa-findly`
   - `AZURE_STATICWEBAPP_RESOURCE_GROUP` = `Findly`
3. After W1 merges and deploys: verify `https://$JOIN_LINK_HOST/g` renders the landing page, and both `/.well-known/assetlinks.json` and `/.well-known/apple-app-site-association` return JSON with `Content-Type: application/json` and **no redirect** (007 §3).
4. Custom domain (optional, later — after the O10 naming decision): `az staticwebapp hostname set` + DNS; free managed cert. Old printed QR codes on the default hostname keep working (007 §1).
