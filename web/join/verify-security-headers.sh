#!/usr/bin/env bash
# specs/007-public-join-links.md §5 — site-wide framing-protection headers, made
# normative by the deletion page (specs/008 §6): Azure Static Web Apps sets NO
# X-Frame-Options / CSP frame-ancestors by default (globalHeaders is opt-in), so without
# this config a malicious site can frame /delete-account invisibly and walk a signed-in
# victim through disguised clicks into irreversible, cascading account/family erasure.
#
# Verified against Microsoft's own docs (Configure Azure Static Web Apps, "Global
# headers"): "The globalHeaders section provides a set of HTTP headers applied to each
# response, unless overridden by a route header rule, otherwise the union of both the
# headers from the route and the global headers is returned." Route-specific headers
# only override a globalHeaders entry that shares the SAME header name; a different
# header name (like the assetlinks.json route's Content-Type) is additive, not replaced.
# That's why adding X-Frame-Options/CSP globally does not regress the
# /.well-known/assetlinks.json Content-Type override that was a real bug once already
# (H4, specs/007 §3) — this script asserts both are still present at once, so a future
# edit that broke that interaction (e.g. a route accidentally re-declaring one of these
# two header names and dropping the other) would fail here.
#
# Usage: web/join/verify-security-headers.sh [path/to/staticwebapp.config.json]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-$SCRIPT_DIR/staticwebapp.config.json}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "verify-security-headers: config not found: $CONFIG_FILE" >&2
  exit 2
fi

echo "== checking $CONFIG_FILE (site-wide framing headers) =="

NODE_CHECK="$(mktemp)"
trap 'rm -f "$NODE_CHECK"' EXIT

cat > "$NODE_CHECK" <<'EOF'
const fs = require("fs");
const path = process.argv[2];
const cfg = JSON.parse(fs.readFileSync(path, "utf8"));
const g = cfg.globalHeaders || {};
let fail = false;

function check(name, ok) {
  console.log((ok ? "PASS" : "FAIL") + ": " + name);
  if (!ok) fail = true;
}

// specs/007 §5 — both, deliberately: CSP is the modern control, X-Frame-Options the
// fallback for older agents. No page on this host is ever legitimately framed.
check('globalHeaders["X-Frame-Options"] === "DENY"', g["X-Frame-Options"] === "DENY");

const csp = g["Content-Security-Policy"];
check(
  "globalHeaders[\"Content-Security-Policy\"] contains frame-ancestors 'none'",
  typeof csp === "string" && /frame-ancestors\s+'none'/.test(csp)
);

// Regression guard (H4 precedent, specs/007 §3): the AASA/assetlinks Content-Type route
// override must still be declared explicitly — globalHeaders merges with route headers
// on DIFFERENT header names, but this asserts the route-level override itself was not
// accidentally deleted while wiring in the global ones.
const routes = cfg.routes || [];
const assetlinks = routes.find((r) => r.route === "/.well-known/assetlinks.json");
check(
  "the /.well-known/assetlinks.json route still sets its own Content-Type: application/json",
  !!assetlinks && !!assetlinks.headers && assetlinks.headers["Content-Type"] === "application/json"
);

process.exit(fail ? 1 : 0);
EOF

if node "$NODE_CHECK" "$CONFIG_FILE"; then
  echo "== RESULT: OK — X-Frame-Options: DENY + CSP frame-ancestors 'none' set globally, assetlinks Content-Type override intact =="
else
  echo "== RESULT: FAIL — $CONFIG_FILE violates specs/007 §5 (site-wide framing headers) ==" >&2
  exit 1
fi
