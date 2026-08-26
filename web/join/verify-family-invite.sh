#!/usr/bin/env bash
# specs/007-public-join-links.md §2 (as amended 2026-08-26), §7 — static checks for the
# family-invite landing page (`GET /f`), in the same red-then-green spirit as
# verify-static-security.sh / verify-delete-account.sh: this script is written and run
# BEFORE family.html exists (it must fail), then again after the page + config + AASA
# component are built (it must pass).
#
# Unlike /delete-account, /f is a no-oracle, zero-external-resource, capability-URL page
# — the SAME security class as /g, not the Firebase-calling exception class. So this
# script:
#   1. Re-invokes verify-static-security.sh against family.html with ZERO flags — the
#      exact same zero-tolerance defaults index.html/privacy.html/terms.html get. No
#      allowlisted external prefix, no --allow-fetch: a family invite code is a
#      single-use credential into a family's live locations, so this page has LESS
#      excuse for an external call than the group page, not more.
#   2. Content assertions specs/007 §1-§3/§7 need that the generic script can't express:
#      the page reads the code from location.hash only (never location.search — codes
#      MUST NOT travel as a query parameter, the no-oracle/never-logged-server-side
#      property depends on staying in the fragment); the findly://family-join?code=
#      open-in-app link form is present; family wording is present (so this isn't a
#      copy-paste of the group page with the label unchanged); the code pattern accepted
#      is the same 001 §1.4 Crockford base32 8-char format as the group page.
#   3. Routing: `/f` is registered in staticwebapp.config.json and rewrites to the family
#      page.
#   4. The AASA carries both the pre-existing `/g` component and the new `/f` component
#      (specs/007 §3, amended) — valid JSON, both present, neither clobbering the other.
#
# Usage: web/join/verify-family-invite.sh [path/to/family.html] [path/to/staticwebapp.config.json] [path/to/apple-app-site-association.json]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILE="${1:-$SCRIPT_DIR/family.html}"
CONFIG_FILE="${2:-$SCRIPT_DIR/staticwebapp.config.json}"
AASA_FILE="${3:-$SCRIPT_DIR/.well-known/apple-app-site-association.json}"

fail=0

echo "== checking $FILE (family-invite landing page, specs/007 §2/§7) =="

if [[ ! -f "$FILE" ]]; then
  echo "FAIL: family-invite landing page not found: $FILE" >&2
  fail=1
fi

# 1. Same zero-tolerance static-security scan as index.html — no flags, no exceptions.
#    A family invite code is MORE sensitive than a group code (single-use), so this page
#    gets the strictest defaults, not a relaxed variant.
if [[ -f "$FILE" ]]; then
  if ! "$SCRIPT_DIR/verify-static-security.sh" "$FILE"; then
    fail=1
  fi
fi

# 2. The code MUST be read from location.hash only, never location.search — a code in
#    the query string would be sent to the server/logs by construction, which is exactly
#    the no-oracle property this page exists to preserve (specs/007 §1, §2). Scans only
#    the executable <script> body (same extraction as verify-static-security.sh), not
#    prose — this file's own security-invariant comment legitimately *names*
#    location.search while documenting that the code must never call it, which is not
#    itself a violation.
if [[ -f "$FILE" ]]; then
  script_body=$(awk '/<script[ >]/{flag=1; next} /<\/script>/{flag=0} flag' "$FILE" | grep -vE '^[[:space:]]*//' || true)
  if ! printf '%s\n' "$script_body" | grep -qE 'location\.hash'; then
    echo "FAIL: page never reads location.hash — cannot display the invite code (specs/007 §2)" >&2
    fail=1
  fi
  if printf '%s\n' "$script_body" | grep -qE 'location\.search'; then
    echo "FAIL: page reads location.search — the invite code MUST NOT travel in the query string (specs/007 §1)" >&2
    fail=1
  fi
fi

# 3. The "Open in the app" affordance MUST use the family deep link form, not the group
#    one (specs/007 §1: findly://family-join?code={CODE}, distinct from
#    findly://group-join?code={CODE}). Presence of the group form here would mis-route a
#    family invite to the group-join screen — exactly what §1/§4 forbid.
if [[ -f "$FILE" ]]; then
  if ! grep -qF 'findly://family-join?code=' "$FILE"; then
    echo "FAIL: no findly://family-join?code= open-in-app link found (specs/007 §1)" >&2
    fail=1
  fi
  if grep -qF 'findly://group-join?code=' "$FILE"; then
    echo "FAIL: found findly://group-join?code= on the family-invite page — /f MUST NOT route to the group-join screen (specs/007 §1)" >&2
    fail=1
  fi
fi

# 4. Family wording present (this must be a family-worded page, not a re-skinned copy of
#    the group page with the deep link changed and nothing else).
if [[ -f "$FILE" ]]; then
  if ! grep -qi 'family' "$FILE"; then
    echo "FAIL: no family-invite wording found in $FILE (specs/007 §2 amendment)" >&2
    fail=1
  fi
fi

# 5. Same 001 §1.4 Crockford base32, 8-char code format as the group page (specs/007 §1:
#    "same code format" for the family-invite form).
if [[ -f "$FILE" ]]; then
  if ! grep -qE '0123456789ABCDEFGHJKMNPQRSTVWXYZ' "$FILE"; then
    echo "FAIL: expected the Crockford base32 alphabet (001 §1.4) in $FILE" >&2
    fail=1
  fi
fi

echo "== checking $CONFIG_FILE (/f route registration) =="

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "FAIL: config not found: $CONFIG_FILE" >&2
  fail=1
else
  if ! node -e '
    const fs = require("fs");
    const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const routes = cfg.routes || [];
    const route = routes.find((r) => r.route === "/f");
    if (!route || typeof route.rewrite !== "string" || !route.rewrite) {
      process.exit(1);
    }
    process.exit(0);
  ' "$CONFIG_FILE"; then
    echo "FAIL: /f route not registered (or malformed) in $CONFIG_FILE (specs/007 §2, §7)" >&2
    fail=1
  fi
fi

echo "== checking $AASA_FILE (AASA /f component, specs/007 §3 amendment) =="

if [[ ! -f "$AASA_FILE" ]]; then
  echo "FAIL: AASA file not found: $AASA_FILE" >&2
  fail=1
else
  if ! node -e '
    const fs = require("fs");
    const aasa = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const details = (aasa.applinks && aasa.applinks.details) || [];
    const ok = details.some((d) => {
      const comps = d.components || [];
      const hasG = comps.some((c) => c["/"] === "/g");
      const hasF = comps.some((c) => c["/"] === "/f");
      return hasG && hasF;
    });
    process.exit(ok ? 0 : 1);
  ' "$AASA_FILE"; then
    echo "FAIL: AASA does not carry BOTH the /g and /f components (specs/007 §3, amended 2026-08-26)" >&2
    fail=1
  fi
fi

if [[ "$fail" -ne 0 ]]; then
  echo "== RESULT: FAIL — family-invite landing page surface violates specs/007 §1-§3/§7 ==" >&2
  exit 1
fi

echo "== RESULT: OK — /f page exists, no-oracle/zero-external-resource, findly://family-join link present, /f routed, AASA carries /g + /f =="
