#!/usr/bin/env bash
# specs/008-privacy-endpoints.md §6 — static checks for the self-service web deletion
# page, in the spirit of web/join/verify-static-security.sh (the closest thing this repo
# has to a test for a hand-authored static page): red (run against a deliberately broken
# copy) then green (run against the real page). Re-run after any edit to
# delete-account.html.
#
# This script does two things:
#   1. Re-invokes verify-static-security.sh with an EXPLICIT, narrow allowlist — exactly
#      the pinned Firebase CDN prefix and the backend API origin this page legitimately
#      needs, plus --allow-fetch for the one DELETE call it legitimately makes. Every
#      other page (index.html/privacy.html/terms.html) keeps calling that script with
#      zero flags (see .github/workflows/web-join.yml) — their zero-external-resource /
#      zero-network-call guarantee (specs/007 §2) is completely unaffected by this file.
#   2. Content assertions specs/008 §6.1 needs that a generic "no unexpected external
#      resource" check can't express: the Firebase config is present and matches the
#      registered web app exactly, measurementId is absent, the SDK version is pinned
#      (not "latest"), the page never reads location.hash/search (no capability in the
#      URL, unlike /g), and the /delete-account route is actually registered.
#
# Usage: web/join/verify-delete-account.sh [path/to/delete-account.html] [path/to/staticwebapp.config.json]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILE="${1:-$SCRIPT_DIR/delete-account.html}"
CONFIG_FILE="${2:-$SCRIPT_DIR/staticwebapp.config.json}"

if [[ ! -f "$FILE" ]]; then
  echo "verify-delete-account: file not found: $FILE" >&2
  exit 2
fi
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "verify-delete-account: config not found: $CONFIG_FILE" >&2
  exit 2
fi

# W4 (docs/implementation-handoff.md) — guard before any node invocation below (this
# script's own two `node -e` checks, plus whatever verify-static-security.sh itself
# needs). Without this, a missing `node` on PATH made `set -euo pipefail` kill the script
# with an unguarded "command not found" instead of a clean, guarded failure. Exit 2
# (setup/environment problem), matching a missing file.
if ! command -v node >/dev/null 2>&1; then
  echo "verify-delete-account: node is required but was not found on PATH" >&2
  exit 2
fi

FIREBASE_SDK_PREFIX="https://www.gstatic.com/firebasejs/12.16.0/"
BACKEND_ORIGIN="https://func-findly.azurewebsites.net/"

fail=0

echo "== checking $FILE (delete-account content rules) =="

# 1. The shared static-security script, scoped to exactly the two external origins this
#    page needs (see the header comment above and verify-static-security.sh's own header).
if ! "$SCRIPT_DIR/verify-static-security.sh" "$FILE" \
      "--allow-external-prefix=$FIREBASE_SDK_PREFIX" \
      "--allow-external-prefix=$BACKEND_ORIGIN" \
      --allow-fetch; then
  fail=1
fi

# 2. Firebase config present and matching the registered web app exactly (specs/008 —
#    task instructions, 2026-07-25 registration). A mismatch here means the page would
#    silently sign users in against the wrong Firebase project, or that someone edited
#    the config without updating this check. Plain indexed array of "key=value" pairs
#    (not `declare -A`) so this script also runs under bash 3.2 (macOS's default /bin/bash
#    has no associative arrays), not just CI's bash 4+.
expected_config=(
  "apiKey=AIzaSyDYipzX2K6LHMCEFG9MAXmD0rAHHPl8K1c"
  "authDomain=findly-71f7b.firebaseapp.com"
  "projectId=findly-71f7b"
  "storageBucket=findly-71f7b.firebasestorage.app"
  "messagingSenderId=781593481145"
  "appId=1:781593481145:web:ebfeadf36e5f17a220b068"
)
for pair in "${expected_config[@]}"; do
  key="${pair%%=*}"
  expected="${pair#*=}"
  if ! grep -qE "${key}:[[:space:]]*\"${expected}\"" "$FILE"; then
    echo "FAIL: Firebase config field '$key' missing or not equal to expected value '$expected'" >&2
    fail=1
  fi
done

# 3. measurementId MUST NOT be SET anywhere in the file (specs/008 §6.1 — deliberately
#    omitted; the console's generated snippet includes it, we never use it). Belt-and-braces
#    on top of check 1's analytics scan (which is scoped to <script>): this one scans the
#    whole file so a measurementId config key reintroduced anywhere (even outside
#    <script>, e.g. a second script block) is caught. Matches only "measurementId:" (an
#    actual object-literal key), not the bare word — this file's own documentation
#    legitimately says things like "measurementId is deliberately OMITTED" in prose, which
#    must not trip this check (same reasoning as verify-static-security.sh's comment
#    handling: only live config, not documentation about it, is a violation).
if grep -qE 'measurementId[[:space:]]*:' "$FILE"; then
  echo "FAIL: 'measurementId:' config key found in $FILE — specs/008 §6.1 forbids it" >&2
  fail=1
fi

# 4. The Firebase SDK import MUST be pinned to a specific version, never "latest" — an
#    unpinned CDN import is a supply-chain risk (silent behavior change with no review)
#    that the allowlist in check 1 would otherwise wave through unconditionally.
if grep -qE 'gstatic\.com/firebasejs/latest/' "$FILE"; then
  echo "FAIL: Firebase SDK import is unpinned (uses /latest/) in $FILE" >&2
  fail=1
fi
if ! grep -qE "gstatic\.com/firebasejs/[0-9]+\.[0-9]+\.[0-9]+/" "$FILE"; then
  echo "FAIL: no pinned-version Firebase SDK import found in $FILE" >&2
  fail=1
fi

# 5. No capability in the URL (specs/008 §6.1 — unlike /g, nothing secret lives in this
#    page's address, and it takes no parameters at all). The page's own script MUST NOT
#    read location.hash or location.search for anything.
url_reads=$(grep -noE 'location\.hash|location\.search' "$FILE" || true)
if [[ -n "$url_reads" ]]; then
  echo "FAIL: page reads location.hash/search — specs/008 §6.1 forbids any capability/param in this page's URL:" >&2
  echo "$url_reads" >&2
  fail=1
fi

# 6. The DELETE call target must be the real backend, not some other origin — a static
#    guard against a typo'd or swapped endpoint silently exfiltrating the ID token.
if ! grep -qF "\"${BACKEND_ORIGIN}api/v1\"" "$FILE"; then
  echo "FAIL: expected API_BASE literal \"${BACKEND_ORIGIN}api/v1\" — not found in $FILE" >&2
  fail=1
fi
if ! grep -qE 'method:[[:space:]]*"DELETE"' "$FILE"; then
  echo "FAIL: no DELETE method call found — expected the account-deletion request" >&2
  fail=1
fi
if ! grep -qE 'Authorization:[[:space:]]*"Bearer' "$FILE"; then
  echo "FAIL: no 'Authorization: Bearer' header construction found" >&2
  fail=1
fi

# 7. The /delete-account route must actually be registered in staticwebapp.config.json,
#    or the page 404s despite existing on disk (specs/008 §6.1 / Google Play requirement).
if ! node -e '
  const fs = require("fs");
  const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const routes = cfg.routes || [];
  const found = routes.some((r) => r.route === "/delete-account" && r.rewrite === "/delete-account.html");
  process.exit(found ? 0 : 1);
' "$CONFIG_FILE"; then
  echo "FAIL: /delete-account route not registered (or malformed) in $CONFIG_FILE" >&2
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "== RESULT: FAIL — delete-account.html violates specs/008 §6.1 ==" >&2
  exit 1
fi

echo "== RESULT: OK — Firebase config matches, no analytics/measurementId, no capability in URL, route registered =="
