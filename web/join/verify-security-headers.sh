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
# Strategy change (docs/implementation-handoff.md row W4, coordinator-directed pivot,
# specs/007 §2/§7): checks 7 and 8 in verify-static-security.sh ban specific banned
# SYNTAXES (<script src>, ES-module import) and, after three review rounds, kept missing a
# new one each time (export...from; <iframe srcdoc>; new Worker(); a computed import()
# specifier; document.write("<scr"+"ipt...")); the CSP verified here is deliberately NOT
# another entry in that list. It is a browser-ENFORCED control: with `default-src 'none'`
# plus the specific per-directive allowances below, none of those syntaxes can execute or
# reach the network AT ALL on the four zero-dependency pages, regardless of what shape the
# leak takes or whether any static scanner can see it (a scanner fundamentally cannot see
# `srcdoc`-injected markup or a runtime-computed specifier; a browser enforcing CSP does
# not need to). Checks 7/8 stay as defence-in-depth (a violation caught at CI time beats
# one caught by the browser at runtime) but are not extended further — this property
# subsumes them for anything they might still miss.
#
# The four zero-dependency pages (/g, /f, /privacy, /terms — index.html, family.html,
# privacy.html, terms.html) inherit ONE strict policy from `globalHeaders` (verified
# against the real files: all four use only an inline <style> block and, for index.html/
# family.html, one inline <script> with no `src`; none references an image, a font, or any
# network resource — confirmed by grepping the four files for <img>, <link>, `url(`,
# `data:`, and `<form`, all empty). `default-src 'none'` covers every fetch destination NOT
# named by a more specific directive (Workers, iframes, `<object>`/`<embed>`, XHR/fetch,
# etc. all fall through to it and are denied) — this is also why the four pages need no
# per-route override at all: leaving `globalHeaders` as the strict policy means it applies
# to literally every response on the host that doesn't explicitly override it, INCLUDING
# `navigationFallback`'s catch-all (any unmatched path silently serves index.html's
# content per the existing config — a route-only strict policy on `/g` specifically would
# have missed that path entirely).
#
# `/delete-account` is the one page that genuinely needs a wider policy (specs/008 §6.1):
# it loads the Firebase JS SDK from gstatic, uses `RecaptchaVerifier`/
# `signInWithPhoneNumber` (Firebase Phone Auth, which injects Google's reCAPTCHA widget/
# iframe and talks to Identity Toolkit directly), and calls DELETE against this app's own
# backend. Its route-level `Content-Security-Policy` override REPLACES (not merges with)
# the global one for that route per the platform doc quoted above — so it must and does
# restate every directive, widening only script-src/img-src/connect-src/frame-src to the
# specific origins that flow needs and no wider:
#   - script-src: the pinned gstatic firebasejs prefix (same one check 1/8's
#     --allow-external-prefix already allowlists) + the reCAPTCHA widget script origins.
#   - img-src: exactly https://www.gstatic.com/recaptcha/ (post-merge-review addition) —
#     the reCAPTCHA visual-challenge widget's images, per Google's own reference CSP
#     (github.com/google/recaptcha, examples/recaptcha-content-security-policy.php), which
#     sets img-src to precisely this origin on the embedding page. Cost-asymmetry call:
#     omitting it silently breaks account deletion for any user escalated to a visual
#     challenge, with no distinguishing Firebase error code to explain why — worse than
#     allowing images from one origin that this same route already trusts to run scripts.
#   - connect-src: this app's own backend origin (the DELETE call) + Identity
#     Toolkit/Secure Token (Firebase Auth's REST endpoints for phone verification/token
#     refresh) + reCAPTCHA's own verification origin.
#   - frame-src: the reCAPTCHA challenge iframe origins.
# Sourced from Firebase/reCAPTCHA's documented CSP requirements (see the task's commit
# message / PR description for citations) — NOT empirically verified against a live
# browser console in this sandboxed environment (no deployed preview exists yet and no
# headless browser is available here). Flagged as an explicit residual risk: a manual
# smoke test of /delete-account's phone-auth flow against a real deployment — forcing a
# visual challenge with Google's test keys and watching the console for CSP violations —
# is required before this ships; no amount of static verification substitutes for it.
#
# Usage: web/join/verify-security-headers.sh [path/to/staticwebapp.config.json]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-$SCRIPT_DIR/staticwebapp.config.json}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "verify-security-headers: config not found: $CONFIG_FILE" >&2
  exit 2
fi

# W4 (docs/implementation-handoff.md) — guard before the node invocation below. Without
# this, a missing `node` on PATH made `set -euo pipefail` kill the script with an
# unguarded "command not found" instead of a clean, guarded failure. Exit 2
# (setup/environment problem), matching a missing file.
if ! command -v node >/dev/null 2>&1; then
  echo "verify-security-headers: node is required but was not found on PATH" >&2
  exit 2
fi

echo "== checking $CONFIG_FILE (site-wide framing headers) =="

NODE_CHECK="$(mktemp)"
trap 'rm -f "$NODE_CHECK"' EXIT

cat > "$NODE_CHECK" <<'EOF'
"use strict";
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

// --- CSP directive-set verification (docs/implementation-handoff.md row W4 pivot) -------
// Parses a CSP header string into { directiveName: Set<sourceToken> } so the comparison
// below is a real SET comparison per directive (order of directives, and order of source
// tokens within a directive, never matters) rather than either a brittle exact-string
// match (broken by harmless reordering) or a substring grep (which is exactly the
// enumeration-of-syntaxes trap this pivot exists to get out of). An ADDED directive, a
// REMOVED directive, or one EXTRA/DIFFERENT source token inside an existing directive all
// change the resulting Set and therefore fail the comparison — nothing about this is a
// loose "contains" check.
function parseCsp(cspString) {
  const map = {};
  if (typeof cspString !== "string") return map;
  cspString
    .split(";")
    .map((part) => part.trim())
    .filter((part) => part.length > 0)
    .forEach((part) => {
      const tokens = part.split(/\s+/);
      const name = tokens[0];
      map[name] = new Set(tokens.slice(1));
    });
  return map;
}

// Deep-compares a parsed CSP against an expected { directiveName: [sourceToken, ...] }
// map: same directive names (nothing added, nothing missing) and, per directive, the
// exact same set of source tokens (nothing widened, nothing narrowed by accident).
function cspMatchesExactly(actualCspString, expected) {
  const actual = parseCsp(actualCspString);
  const actualNames = Object.keys(actual).sort();
  const expectedNames = Object.keys(expected).sort();
  if (actualNames.length !== expectedNames.length) return false;
  for (let i = 0; i < actualNames.length; i++) {
    if (actualNames[i] !== expectedNames[i]) return false;
  }
  for (const name of expectedNames) {
    const actualValues = actual[name];
    const expectedValues = expected[name];
    if (actualValues.size !== expectedValues.length) return false;
    for (const v of expectedValues) {
      if (!actualValues.has(v)) return false;
    }
  }
  return true;
}

// The ONE strict policy every response on this host gets by default (globalHeaders),
// derived from what /g, /f, /privacy, /terms genuinely use (see the file header comment):
// an inline <script> with no src on two of the four, an inline <style> on all four,
// nothing else. `default-src 'none'` is the backstop that denies every fetch destination
// (Workers, frames, <object>/<embed>, XHR/fetch, ...) not named by a more specific
// directive below — this is what makes the property non-enumerable: a NEW syntax for
// reaching the network or spawning an execution context doesn't need a new check here, it
// just has nowhere to go.
const STRICT_CSP = {
  "default-src": ["'none'"],
  "script-src": ["'unsafe-inline'"],
  "style-src": ["'unsafe-inline'"],
  "img-src": ["'none'"],
  "connect-src": ["'none'"],
  "frame-src": ["'none'"],
  "worker-src": ["'none'"],
  "object-src": ["'none'"],
  "base-uri": ["'none'"],
  "form-action": ["'none'"],
  "frame-ancestors": ["'none'"],
};

check(
  "globalHeaders[\"Content-Security-Policy\"] is exactly the strict zero-dependency policy (default-src 'none' + the specific directives /g,/f,/privacy,/terms need, nothing more)",
  cspMatchesExactly(csp, STRICT_CSP)
);

// /delete-account (specs/008 §6.1) is the one reviewed, scoped exception: it widens only
// script-src/connect-src/frame-src to exactly the origins its Firebase-JS-SDK-plus-
// reCAPTCHA-phone-auth flow needs (see the file header comment for the sourcing). Its
// route-level Content-Security-Policy REPLACES globalHeaders' for that route (same
// platform behavior the assetlinks Content-Type override already relies on), so this MUST
// restate every directive, not just the widened three — checked here as a full set,
// exactly like the strict policy above, so this exception can never quietly get wider or
// gain a directive without this check failing.
const DELETE_ACCOUNT_CSP = {
  "default-src": ["'none'"],
  "script-src": [
    "'unsafe-inline'",
    "https://www.gstatic.com/firebasejs/12.16.0/",
    "https://www.gstatic.com/recaptcha/",
    "https://www.google.com/recaptcha/",
  ],
  "style-src": ["'unsafe-inline'"],
  // img-src widened from 'none' (coordinator-directed, post-merge-review finding): the
  // reCAPTCHA visual challenge (triggered when Google's risk engine escalates a phone-auth
  // attempt) renders images from this exact origin. Google's own reference CSP
  // (github.com/google/recaptcha, examples/recaptcha-content-security-policy.php) sets
  // img-src to precisely this on the embedding page, so treat that as authoritative rather
  // than guess. Deliberately the narrowest possible allowance: the one gstatic path
  // reCAPTCHA needs, not a wildcard, not extended to any other image source — and only on
  // this route; the four zero-dependency pages keep img-src 'none' (none of them reference
  // an image at all).
  "img-src": ["https://www.gstatic.com/recaptcha/"],
  "connect-src": [
    "https://func-findly.azurewebsites.net",
    "https://identitytoolkit.googleapis.com",
    "https://securetoken.googleapis.com",
    "https://www.google.com/recaptcha/",
  ],
  "frame-src": ["https://www.google.com/recaptcha/", "https://recaptcha.google.com/recaptcha/"],
  "worker-src": ["'none'"],
  "object-src": ["'none'"],
  "base-uri": ["'none'"],
  "form-action": ["'none'"],
  "frame-ancestors": ["'none'"],
};

const deleteAccountRoute = routes.find((r) => r.route === "/delete-account");
const deleteAccountCsp =
  deleteAccountRoute && deleteAccountRoute.headers
    ? deleteAccountRoute.headers["Content-Security-Policy"]
    : undefined;
check(
  "/delete-account route sets exactly its scoped Firebase+reCAPTCHA CSP exception (nothing wider, nothing missing)",
  !!deleteAccountRoute && cspMatchesExactly(deleteAccountCsp, DELETE_ACCOUNT_CSP)
);

// Guard against the exception silently spreading: none of the four strict pages' own
// route entries may declare their own Content-Security-Policy override — if one did, it
// would replace (not add to) the strict globalHeaders policy for that route, and this
// check would otherwise have nothing else watching that route's actual CSP.
["/g", "/f", "/privacy", "/terms"].forEach((routePath) => {
  const r = routes.find((route) => route.route === routePath);
  const hasOwnCsp = !!r && !!r.headers && typeof r.headers["Content-Security-Policy"] === "string";
  check(
    routePath + " has no route-level Content-Security-Policy override (inherits the strict globalHeaders policy)",
    !hasOwnCsp
  );
});

process.exit(fail ? 1 : 0);
EOF

if node "$NODE_CHECK" "$CONFIG_FILE"; then
  echo "== RESULT: OK — X-Frame-Options: DENY + strict CSP set globally, /delete-account's scoped exception exact, assetlinks Content-Type override intact =="
else
  echo "== RESULT: FAIL — $CONFIG_FILE violates specs/007 §5 (site-wide framing headers / CSP) ==" >&2
  exit 1
fi
