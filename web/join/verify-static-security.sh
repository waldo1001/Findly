#!/usr/bin/env bash
# specs/007-public-join-links.md §2, §7 — static assertion that the join-link landing
# page (index.html) never makes a network call and never embeds an external resource.
# This is the closest thing this task has to a test: red (run against a deliberately
# broken draft) then green (run against the real page). Re-run after any edit to
# index.html.
#
# Usage: web/join/verify-static-security.sh [path/to/index.html]
set -euo pipefail

FILE="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/index.html}"

if [[ ! -f "$FILE" ]]; then
  echo "verify-static-security: file not found: $FILE" >&2
  exit 2
fi

fail=0

echo "== checking $FILE =="

# 1. No URI-scheme reference other than the in-app findly:// deep link — this is the
#    single allowed exception (specs/007 §2's "Open in the app" affordance). Anything
#    else with a "scheme://" shape (http, https, ftp, protocol-relative-looking tokens,
#    a CDN URL, etc.) is a spec violation.
external_urls=$(grep -oE '[A-Za-z][A-Za-z0-9+.-]*://[^"'"'"'[:space:]<>]*' "$FILE" | grep -vi '^findly://' || true)
if [[ -n "$external_urls" ]]; then
  echo "FAIL: external URL reference(s) found:" >&2
  echo "$external_urls" >&2
  fail=1
fi

# 2. No protocol-relative resource reference (e.g. src="//cdn.example.com/lib.js").
protocol_relative=$(grep -noE '(src|href)[[:space:]]*=[[:space:]]*"//[^"]*"' "$FILE" || true)
if [[ -n "$protocol_relative" ]]; then
  echo "FAIL: protocol-relative resource reference(s) found:" >&2
  echo "$protocol_relative" >&2
  fail=1
fi

# 3 & 4 scan only the executable <script>...</script> body, not prose (the security-
# invariant comment block in <head> legitimately *names* fetch/localStorage/etc. while
# documenting that this file must never use them — matching the whole file would flag
# that documentation as if it were a violation).
script_body=$(awk '/<script>/{flag=1; next} /<\/script>/{flag=0} flag' "$FILE")

# 3. No network-call primitive of any kind.
network_calls=$(printf '%s\n' "$script_body" | grep -noE '\bfetch[[:space:]]*\(|\bXMLHttpRequest\b|\bnew[[:space:]]+WebSocket\b|\bsendBeacon\b|\bEventSource\b' || true)
if [[ -n "$network_calls" ]]; then
  echo "FAIL: network-call primitive found in <script>:" >&2
  echo "$network_calls" >&2
  fail=1
fi

# 4. No cookies, no localStorage/sessionStorage — the page must persist nothing.
storage_calls=$(printf '%s\n' "$script_body" | grep -noE 'document\.cookie|\blocalStorage\b|\bsessionStorage\b' || true)
if [[ -n "$storage_calls" ]]; then
  echo "FAIL: cookie/storage usage found in <script>:" >&2
  echo "$storage_calls" >&2
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "== RESULT: FAIL — $FILE violates specs/007 §2 security invariants ==" >&2
  exit 1
fi

echo "== RESULT: OK — no external resources, no network calls, no cookies/storage =="
