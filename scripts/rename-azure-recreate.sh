#!/usr/bin/env bash
#
# Findly rename — Azure teardown + recreate (WhereIsWaldo → Findly).
#
# Azure resources CANNOT be renamed in place, so this deletes the old ones and
# recreates them with Findly names. It mirrors docs/azure-setup.md §1/§2/§7 exactly.
#
# ⚠️  DESTRUCTIVE. It deletes the old resource group (all storage data in it) and
#     the old OIDC app registration. Only safe pre-launch, when the only data is
#     test data (specs/006 §8 was going to wipe it at launch anyway).
#
# PREREQUISITES / ORDER (see docs/findly-rename-runbook.md):
#   1. Rename the GitHub repo FIRST (WhereIsWaldo → Findly) so the OIDC federated
#      credential subject created below matches the new repo path.
#   2. Run this script (you, manually — `az login` as Owner on the subscription).
#   3. Do the Firebase console steps (new project) — see the runbook.
#   4. Apply the post-provision repo edits the script prints at the end.
#
# Run with:  bash scripts/rename-azure-recreate.sh
# It pauses for confirmation before anything destructive.

set -euo pipefail

# ---- OLD (to delete) ----
OLD_RG=WhereIsWaldo
OLD_APP_REG=gh-whereiswaldo-deploy

# ---- NEW (to create) — storage/func/swa names are GLOBALLY unique; verify availability ----
LOCATION=westeurope
RG=Findly
STORAGE=stfindly            # 3-24 lowercase alphanumerics, globally unique
FUNCAPP=func-findly         # globally unique
SWA=swa-findly              # globally unique
APP_REG=gh-findly-deploy
GITHUB_REPO="waldo1001/Findly"   # AFTER the GitHub repo rename
FIREBASE_PROJECT_ID="<new-findly-firebase-project-id>"   # fill in from step 3

echo "About to DELETE resource group '$OLD_RG' (and everything in it) and app reg '$OLD_APP_REG',"
echo "then create RG '$RG' with $STORAGE / $FUNCAPP / $SWA and app reg '$APP_REG'."
read -r -p "Type 'recreate' to proceed: " confirm
[ "$confirm" = "recreate" ] || { echo "aborted."; exit 1; }

# ---------------------------------------------------------------------------
# 0. Availability pre-check for the globally-unique names (fail early, cheap)
# ---------------------------------------------------------------------------
echo "== checking global name availability =="
az storage account check-name --name "$STORAGE" --query nameAvailable -o tsv
echo "  (func/swa uniqueness is enforced at create time; if create fails on a name"
echo "   collision, pick another suffix and update this script + the repo edits below.)"

# ---------------------------------------------------------------------------
# 1. TEARDOWN
# ---------------------------------------------------------------------------
echo "== deleting old app registration =="
OLD_APP_ID=$(az ad app list --display-name "$OLD_APP_REG" --query "[0].appId" -o tsv || true)
if [ -n "${OLD_APP_ID:-}" ]; then az ad app delete --id "$OLD_APP_ID"; fi

echo "== deleting old resource group (this is the destructive step) =="
az group delete -n "$OLD_RG" --yes

# ---------------------------------------------------------------------------
# 2. RECREATE — resource group, storage (+ lifecycle), function app (+ MI roles)
#    Mirrors docs/azure-setup.md §1.  Node 24 (Azure refuses Node 20 for new apps).
# ---------------------------------------------------------------------------
az group create -n "$RG" -l "$LOCATION"

az storage account create -n "$STORAGE" -g "$RG" -l "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 \
  --allow-blob-public-access false

cat > /tmp/lifecycle.json <<'EOF'
{ "rules": [ {
    "name": "history-retention", "enabled": true, "type": "Lifecycle",
    "definition": {
      "filters": { "blobTypes": ["appendBlob"], "prefixMatch": ["history/", "events/"] },
      "actions": { "baseBlob": {
        "delete": { "daysAfterModificationGreaterThan": 400 } } } } } ] }
EOF
az storage account management-policy create --account-name "$STORAGE" -g "$RG" --policy @/tmp/lifecycle.json

az functionapp create -n "$FUNCAPP" -g "$RG" -s "$STORAGE" \
  --consumption-plan-location "$LOCATION" \
  --runtime node --runtime-version 24 --functions-version 4 \
  --assign-identity '[system]'

PRINCIPAL_ID=$(az functionapp identity show -n "$FUNCAPP" -g "$RG" --query principalId -o tsv)
STORAGE_ID=$(az storage account show -n "$STORAGE" -g "$RG" --query id -o tsv)
az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
  --role "Storage Table Data Contributor" --scope "$STORAGE_ID"
az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" --scope "$STORAGE_ID"

az functionapp config appsettings set -n "$FUNCAPP" -g "$RG" --settings \
  FIREBASE_PROJECT_ID="$FIREBASE_PROJECT_ID" \
  TABLES_ENDPOINT="https://$STORAGE.table.core.windows.net" \
  BLOB_ENDPOINT="https://$STORAGE.blob.core.windows.net"
# NB: FCM_SERVICE_ACCOUNT_JSON is set later from the new Firebase service-account key (runbook step 3).

# REQUIRED — a freshly recreated storage account has zero tables, and Azure Table Storage does
# NOT auto-create one on first write (docs/azure-setup.md has the full rationale). Missing here
# during the original Findly rename left `stfindly` with zero tables until fixed live 2026-07-25 —
# every write-path endpoint (starting with the most basic, POST /families) 500'd until this ran.
for t in Families Users Invites Devices LastKnown Entitlements LocateRequests \
         IdempotencyMarkers Usage Groups GroupCodes GroupLastKnown GroupExpiry; do
  az storage table create --name "$t" --account-name "$STORAGE" --auth-mode login
done

# REQUIRED — a freshly recreated storage account has zero blob containers either. Despite a
# stale claim that used to live here and in specs/002 §1 ("the blob containers self-heal via
# create-if-not-exists on append"), Azure Blob Storage does NOT auto-create a CONTAINER on
# first write — only the per-day BLOB *inside* an already-existing container self-heals that
# way (specs/002 §3.2). This script never created `config`/`history`/`events` during the
# original Findly rename, which left `stfindly` with zero containers until fixed live
# 2026-08-06: `POST /locations` and `PUT /geofences` 500'd `ContainerNotFound` for every family
# from first deploy until this ran (B25). `backend/src/adapters/blobs/blobClientFactory.ts`
# now also self-heals this at the code level (defense-in-depth) — provisioning still creates
# them explicitly so the account is correct from the first request, not just after the first
# 500.
for c in config history events; do
  az storage container create --name "$c" --account-name "$STORAGE" --auth-mode login \
    --public-access off
done

# ---------------------------------------------------------------------------
# 3. RECREATE — OIDC app registration for GitHub Actions (mirrors §2)
# ---------------------------------------------------------------------------
APP_ID=$(az ad app create --display-name "$APP_REG" --query appId -o tsv)
az ad sp create --id "$APP_ID"
SP_OID=$(az ad sp show --id "$APP_ID" --query id -o tsv)

# A brand-new service principal takes a bit to propagate through Entra; role assignments made
# too soon silently no-op (the assignee isn't found yet). Wait, then assign by object-id with a
# short retry. (Without this, the OIDC app ends up with NO role assignments and every CI deploy
# fails — exactly what happened on the first live run of this script.)
echo "waiting ~30s for the service principal to propagate before role assignments..."
sleep 30
assign_role() {  # assign_role <role> <scope>
  for attempt in 1 2 3 4 5; do
    if az role assignment create --assignee-object-id "$SP_OID" --assignee-principal-type ServicePrincipal \
         --role "$1" --scope "$2" >/dev/null 2>&1; then
      echo "  role '$1' assigned"; return 0
    fi
    echo "  role '$1' not applied yet (attempt $attempt) — retrying in 15s..."; sleep 15
  done
  echo "  WARN: role '$1' could not be assigned on $2 — assign it manually."
}

# GitHub Actions federated credentials. TWO are created:
#   1. the standard name-based subject (works for repos that were never renamed);
#   2. the immutable-ID subject GitHub emits AFTER an owner/repo rename (a resurrection-attack
#      protection): repo:<owner>@<ownerId>/<repo>@<repoId>:...  Since this script exists to
#      support a rename, #2 is the one that actually matches — creating both is harmless and
#      future-proof. (Missing #2 is why the first live deploy failed with AADSTS700213.)
OWNER="${GITHUB_REPO%%/*}"; REPO="${GITHUB_REPO##*/}"
cat > /tmp/fedcred-name.json <<EOF
{ "name": "github-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:${GITHUB_REPO}:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"] }
EOF
az ad app federated-credential create --id "$APP_ID" --parameters @/tmp/fedcred-name.json
if command -v gh >/dev/null 2>&1; then
  OWNER_ID=$(gh api "users/${OWNER}" --jq .id 2>/dev/null || true)
  REPO_ID=$(gh api "repos/${GITHUB_REPO}" --jq .id 2>/dev/null || true)
  if [ -n "${OWNER_ID:-}" ] && [ -n "${REPO_ID:-}" ]; then
    cat > /tmp/fedcred-immutable.json <<EOF
{ "name": "github-main-immutable",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:${OWNER}@${OWNER_ID}/${REPO}@${REPO_ID}:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"] }
EOF
    az ad app federated-credential create --id "$APP_ID" --parameters @/tmp/fedcred-immutable.json
  else
    echo "WARN: couldn't fetch GitHub numeric IDs; if a deploy fails with AADSTS700213, add a fed"
    echo "      cred with subject repo:${OWNER}@<ownerId>/${REPO}@<repoId>:ref:refs/heads/main"
  fi
else
  echo "WARN: gh CLI not found — skipped the immutable-ID fed cred. If a deploy fails with"
  echo "      AADSTS700213 (renamed repo), add repo:${OWNER}@<ownerId>/${REPO}@<repoId>:ref:refs/heads/main"
fi

FUNCAPP_ID=$(az functionapp show -n "$FUNCAPP" -g "$RG" --query id -o tsv)
assign_role "Website Contributor" "$FUNCAPP_ID"

# ---------------------------------------------------------------------------
# 4. RECREATE — Static Web App for join links (mirrors §7)
# ---------------------------------------------------------------------------
az staticwebapp create -n "$SWA" -g "$RG" -l "$LOCATION" --sku Free
NEW_JOIN_HOST=$(az staticwebapp show -n "$SWA" -g "$RG" --query defaultHostname -o tsv)
SWA_ID=$(az staticwebapp show -n "$SWA" -g "$RG" --query id -o tsv)
assign_role "Contributor" "$SWA_ID"

TENANT_ID=$(az account show --query tenantId -o tsv)
SUB_ID=$(az account show --query id -o tsv)

# ---------------------------------------------------------------------------
# 5. Print the manual follow-ups (repo edits + GitHub variables)
# ---------------------------------------------------------------------------
cat <<EOF

============================================================================
 DONE. Now apply these manually (see docs/findly-rename-runbook.md):

 GitHub → Settings → Secrets and variables → Actions → Variables:
   AZURE_CLIENT_ID                    = $APP_ID
   AZURE_TENANT_ID                    = $TENANT_ID
   AZURE_SUBSCRIPTION_ID             = $SUB_ID
   AZURE_FUNCTIONAPP_NAME           = $FUNCAPP
   AZURE_STATICWEBAPP_NAME          = $SWA
   AZURE_STATICWEBAPP_RESOURCE_GROUP = $RG
   BASE_URL / build config for the app  → https://$FUNCAPP.azurewebsites.net/api/

 New JOIN_LINK_HOST = $NEW_JOIN_HOST
   The SWA hostname CHANGED (it is random per SWA). Update all of:
     - mobile/android/app/build.gradle.kts   (val joinLinkHost)
     - mobile/ios/FindlyKit/Sources/FindlyKit/Config/AppConfig.swift (defaultJoinLinkHost)
     - mobile/ios/Findly/Findly.entitlements  (applinks:<host>, once H6/Team ID lands)
   Then re-deploy web-join and re-verify /g + both .well-known files (200, no redirect,
   correct Content-Type) per specs/007 §3.

 Still to do in the Firebase console (runbook step 3): new project, Blaze + budget,
 Phone provider, SMS region allowlist, test numbers, App Check, App Attest, APNs key,
 re-download google-services.json + GoogleService-Info.plist, then set
 FCM_SERVICE_ACCOUNT_JSON on $FUNCAPP from the new service-account key.
============================================================================
EOF
