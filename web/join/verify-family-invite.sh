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

# W4 (docs/implementation-handoff.md) — guard before any of the node invocations below (the
# hash/search scan, the route-registration check, the AASA check, plus whatever
# verify-static-security.sh itself needs). Without this, a missing `node` on PATH made
# `set -euo pipefail` kill the script with an unguarded "command not found" instead of a
# clean, guarded failure. Exit 2 (setup/environment problem), matching a missing file.
if ! command -v node >/dev/null 2>&1; then
  echo "verify-family-invite: node is required but was not found on PATH" >&2
  exit 2
fi

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
#    the no-oracle property this page exists to preserve (specs/007 §1, §2).
#
#    Round-2 finding: scanning only the executable <script> body has two bypasses (a
#    single-line <script> tag; an inline event-handler attribute entirely outside any
#    <script> tag) — fixed in round 2 by stripping HTML comments then scanning the WHOLE
#    file for the literal token.
#
#    Round-3 findings on that round-2 fix, both closed below:
#      - FIX 2: the comment stripper stopped only at "-->". A browser (WHATWG tokenizer
#        comment-end-bang state) also ends a comment at "--!>", so
#        `<!--x--!><body onload="...location.search...">y-->` was stripped as ONE
#        comment (the real terminator "-->" is only found at the trailing "y-->"),
#        deleting the live leak along with it. Now terminates at the first of "-->" or
#        "--!>", same fix as verify-static-security.sh, duplicated here deliberately (the
#        idiom is duplicated across the two scripts, so both copies needed the fix).
#      - FIX 5: the literal `location\.search` ban is trivially obfuscatable —
#        `location['search']` or `location[('sea'+'rch')]` never contain the literal
#        substring "location.search" but read exactly the same property at runtime. Since
#        this file has no <script>-body-only fallback protecting it the way
#        verify-static-security.sh's inline-handler check does, the literal-token check
#        was the ONLY backstop for /f — so it now also bans computed bracket access on
#        `location` (`location\s*\[`), which both obfuscation forms above always contain
#        regardless of what expression computes the key. This does not claim to catch
#        every possible obfuscation (a sufficiently indirect one always beats a static
#        grep) — the bar is "no bypass trivially reachable by pasting one alternative
#        property-access syntax", not "provably complete".
#    Moved into a real node script (not a `node -e` one-liner) so \s in the JS regexes
#    naturally covers newlines with no separate line-based patch needed.
NODE_HASH_CHECK="$(mktemp)"
cat > "$NODE_HASH_CHECK" <<'NODEEOF'
"use strict";
const fs = require("fs");
// invoked as `node "$NODE_HASH_CHECK" "$FILE"` — a real script file, so argv[2] is the
// target (argv[1] is this script's own path; see the matching note in
// verify-static-security.sh, same argv-shift pitfall, same fix).
const html = fs.readFileSync(process.argv[2], "utf8");

// FIX 2 — stop at the first of "-->" or "--!>" (WHATWG comment-end-bang state).
const stripped = html.replace(/<!--[\s\S]*?(?:-->|--!>)/g, "");

const hasHash = /location\s*\.\s*hash/.test(stripped);
const hasSearchLiteral = /location\s*\.\s*search/.test(stripped);
// FIX 5 — computed/bracket access on `location` (obfuscates the literal token away):
// catches location['search'], location["search"], location[k], location[('sea'+'rch')].
const hasBracketAccess = /location\s*\[/.test(stripped);

console.log("HASH=" + (hasHash ? "1" : "0"));
console.log("SEARCH=" + (hasSearchLiteral ? "1" : "0"));
console.log("BRACKET=" + (hasBracketAccess ? "1" : "0"));
NODEEOF
if [[ -f "$FILE" ]]; then
  hash_result=$(node "$NODE_HASH_CHECK" "$FILE")
  if ! printf '%s\n' "$hash_result" | grep -qF 'HASH=1'; then
    echo "FAIL: page never reads location.hash — cannot display the invite code (specs/007 §2)" >&2
    fail=1
  fi
  if printf '%s\n' "$hash_result" | grep -qF 'SEARCH=1'; then
    echo "FAIL: page reads location.search — the invite code MUST NOT travel in the query string (specs/007 §1)" >&2
    fail=1
  fi
  if printf '%s\n' "$hash_result" | grep -qF 'BRACKET=1'; then
    echo "FAIL: page uses computed bracket access on location (e.g. location['search']) — obfuscated equivalent of reading the query string (specs/007 §1)" >&2
    fail=1
  fi
fi
rm -f "$NODE_HASH_CHECK"

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
  # Code-review finding (2026-08-26): the original check only asserted that /f had SOME
  # non-empty string rewrite target, so { "route": "/f", "rewrite": "/index.html" } —
  # the exact family-to-group cross-routing hazard specs/007 §1/§7 forbids — passed
  # undetected. Now asserts the ACTUAL target is /family.html, and pins /g -> /index.html
  # too (the reverse cross-route the same invariant forbids).
  if ! node -e '
    const fs = require("fs");
    const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const routes = cfg.routes || [];
    const fRoute = routes.find((r) => r.route === "/f");
    const gRoute = routes.find((r) => r.route === "/g");
    if (!fRoute || fRoute.rewrite !== "/family.html") {
      process.exit(1);
    }
    if (!gRoute || gRoute.rewrite !== "/index.html") {
      process.exit(1);
    }
    process.exit(0);
  ' "$CONFIG_FILE"; then
    echo "FAIL: /f must rewrite to exactly /family.html and /g to exactly /index.html in $CONFIG_FILE (specs/007 §1, §2, §7 — no family/group cross-routing)" >&2
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
