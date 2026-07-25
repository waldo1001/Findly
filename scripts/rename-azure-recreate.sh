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

# ---------------------------------------------------------------------------
# 3. RECREATE — OIDC app registration for GitHub Actions (mirrors §2)
# ---------------------------------------------------------------------------
APP_ID=$(az ad app create --display-name "$APP_REG" --query appId -o tsv)
az ad sp create --id "$APP_ID"

cat > /tmp/fedcred.json <<EOF
{ "name": "github-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:${GITHUB_REPO}:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"] }
EOF
az ad app federated-credential create --id "$APP_ID" --parameters @/tmp/fedcred.json

FUNCAPP_ID=$(az functionapp show -n "$FUNCAPP" -g "$RG" --query id -o tsv)
az role assignment create --assignee "$APP_ID" --role "Website Contributor" --scope "$FUNCAPP_ID"

# ---------------------------------------------------------------------------
# 4. RECREATE — Static Web App for join links (mirrors §7)
# ---------------------------------------------------------------------------
az staticwebapp create -n "$SWA" -g "$RG" -l "$LOCATION" --sku Free
NEW_JOIN_HOST=$(az staticwebapp show -n "$SWA" -g "$RG" --query defaultHostname -o tsv)
SWA_ID=$(az staticwebapp show -n "$SWA" -g "$RG" --query id -o tsv)
az role assignment create --assignee "$APP_ID" --role Contributor --scope "$SWA_ID"

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
