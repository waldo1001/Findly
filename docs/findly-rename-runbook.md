# Findly rename runbook (WhereIsWaldo → Findly)

The code rename (identifiers, packages, bundle ids, directories, docs) is **done in the
repo** on branch `rename/findly` and merged. This runbook covers the parts that live
outside the repo — Azure (recreate), Firebase (recreate), GitHub repo rename, and the
post-provision repo edits that depend on values only those steps produce.

**Decision (2026-07-25):** public name = **Findly**. Bundle ids `com.findly.ios` /
`com.findly.android`. Firebase project = **new** (old id `whereiswaldo-30e9c` is immutable).
Azure = **recreate** (resources can't be renamed in place). This resolves the naming half of
H7 / 000 §O10; the legal half (privacy policy + ToS) is still open.

## Order of operations (dependencies are real — don't reorder)

1. **Rename the GitHub repo** `waldo1001/WhereIsWaldo` → `waldo1001/Findly`
   (Settings → General → Repository name). Do this **first**: the OIDC federated
   credential recreated in step 3 pins `repo:waldo1001/Findly:...`, and it must match.
   - Update your local remote: `git remote set-url origin https://github.com/waldo1001/Findly`
     (GitHub keeps a redirect, but set it explicitly).
   - Optional: rename the local folder `.../Community/WhereIsWaldo` → `.../Community/Findly`
     (cosmetic; nothing in the repo depends on the folder name).
   - Re-point branch protection required checks if the repo rename dropped them (it usually
     keeps them): `test`, `mutation`, `android-build`, `ios-package`, `ios-build`.

2. **Recreate Azure** — run `bash scripts/rename-azure-recreate.sh` (as Owner, `az login`).
   It deletes the old `WhereIsWaldo` RG + `gh-whereiswaldo-deploy` app reg and creates
   `Findly` / `stfindly` / `func-findly` / `swa-findly` / `gh-findly-deploy`. It prints the
   new `AZURE_CLIENT_ID`, the new `JOIN_LINK_HOST`, and the GitHub variables to set.
   - The globally-unique names (`stfindly`, `func-findly`, `swa-findly`) may be taken — the
     script pre-checks storage and fails fast on the others. Pick a suffix and update both
     the script and the repo edits in step 4 if so.
   - **OIDC after a repo rename:** once a GitHub repo (or its owner) is renamed, GitHub emits
     an *immutable-ID* OIDC subject — `repo:<owner>@<ownerId>/<repo>@<repoId>:ref:refs/heads/main`
     — instead of the name-based one, as a resurrection-attack guard. The script now creates
     **both** federated credentials (name-based + immutable-ID, IDs fetched via `gh`). If a
     deploy fails with **`AADSTS700213`**, that mismatch is the cause; see Troubleshooting below.

3. **Recreate Firebase** (console — mostly not scriptable). This re-does task **H2** against
   a new project. Follow `docs/azure-setup.md` §3 verbatim; the essentials:
   - New project → note the **project ID** → this is the new `FIREBASE_PROJECT_ID`
     (put it in the Azure app setting; the script left a placeholder).
   - **Blaze** plan + **budget alert** (€5/mo family mode).
   - **Auth → Phone** enabled, all other providers off.
   - **SMS region allowlist** = BE, NL (family mode; open mode is H8, gated on App Check).
   - **Test phone numbers** (console only — never commit a working pair).
   - **App Check**: Android Play Integrity (needs debug+release SHA-256s), iOS App Attest —
     leave enforcement in **monitor** until both apps sign in.
   - **Register the apps with the NEW bundle ids**: `com.findly.android` (+ SHA-256s) and
     `com.findly.ios`. Download fresh **`google-services.json`** → `mobile/android/app/`
     and **`GoogleService-Info.plist`** → `mobile/ios/` (both gitignored; the old ones on
     disk still hold `whereiswaldo-30e9c` — replace them).
   - **APNs key** upload — gated on the Apple Developer enrollment (H6). Until then iOS
     on-device sign-in falls back to reCAPTCHA.
   - **FCM service account key** → set `FCM_SERVICE_ACCOUNT_JSON` on `func-findly`
     (command in azure-setup §3.9), then delete the local key file.

4. **Post-provision repo edits** (values only steps 2–3 produce):
   - **GitHub repo variables** (from the script's printout): `AZURE_CLIENT_ID`,
     `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_FUNCTIONAPP_NAME=func-findly`,
     `AZURE_STATICWEBAPP_NAME=swa-findly`, `AZURE_STATICWEBAPP_RESOURCE_GROUP=Findly`.
   - **API base URL**: the app's build config `BASE_URL` →
     `https://func-findly.azurewebsites.net/api/` (Android `build.gradle.kts`; iOS via its
     build config — source default stays the `.invalid` placeholder).
   - **New `JOIN_LINK_HOST`** (SWA hostnames are random and changed): update
     `mobile/android/app/build.gradle.kts` (`joinLinkHost`),
     `mobile/ios/FindlyKit/Sources/FindlyKit/Config/AppConfig.swift` (`defaultJoinLinkHost`),
     and later `mobile/ios/Findly/Findly.entitlements` (`applinks:<host>`).
   - Re-deploy `web-join` and re-verify `/g` + `/.well-known/assetlinks.json` +
     `/.well-known/apple-app-site-association` (200, no redirect, `application/json`) — 007 §3.

## Apple (H6, enrollment-gated — unchanged by the rename except the id)

Enrollment is active; **Team ID = `92A2K3Q7NH`**. Repo side **done 2026-07-25** (PR #3):
- `apple-app-site-association.json` → `92A2K3Q7NH.com.findly.ios` ✅ (verified live)
- `Findly.entitlements` → Associated Domains active, `applinks:kind-plant-0fb99b003.7.azurestaticapps.net` ✅

Remaining Apple-portal steps (yours):
- Enable **Associated Domains + Push + App Attest** capabilities on the `com.findly.ios` App ID
  (needed before a real signed build; the Xcode app target doesn't exist yet — specs/004 §1.1).
- Upload the **APNs `.p8` key** to Firebase → Cloud Messaging (lets iOS sign-in skip reCAPTCHA).
- Apply for the **Location Push Service Extension** entitlement (independent lead time, 000 §O1).
- Create the **App Store Connect** app as **Findly**, wire **TestFlight**.

## Troubleshooting

**CI deploy fails with `AADSTS700213: No matching federated identity record found`.**
The repo was renamed, so GitHub presents an immutable-ID OIDC subject
(`repo:<owner>@<ownerId>/<repo>@<repoId>:ref:refs/heads/main`) that the name-based federated
credential doesn't match. Fix — add the matching credential (the recreate script now does this
automatically; this is the manual form):
```bash
APPID=$(az ad app list --display-name gh-findly-deploy --query "[0].appId" -o tsv)
OWNER_ID=$(gh api users/waldo1001 --jq .id)      # 12088142
REPO_ID=$(gh api repos/waldo1001/Findly --jq .id) # 1305525936
cat > /tmp/fc.json <<EOF
{ "name": "github-main-immutable",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:waldo1001@${OWNER_ID}/Findly@${REPO_ID}:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"] }
EOF
az ad app federated-credential create --id "$APPID" --parameters @/tmp/fc.json
```

**CI deploy fails with an authorization / RBAC error (not 700213).** The OIDC service principal
is missing its role assignment (the propagation race — see the script's `assign_role`). Re-assign:
`Website Contributor` on `func-findly` for backend, `Contributor` on `swa-findly` for web-join.
