#!/usr/bin/env bash
# specs/007-public-join-links.md §2, §7 — static assertion that the join-link landing
# page (index.html) never makes a network call and never embeds an external resource.
# This is the closest thing this task has to a test: red (run against a deliberately
# broken draft) then green (run against the real page). Re-run after any edit to
# index.html.
#
# Usage: web/join/verify-static-security.sh [path/to/file.html] [flags...]
#
# Flags (all opt-IN, none change the default zero-tolerance behavior above):
#   --allow-external-prefix=<prefix>   May repeat. Whitelists exactly one external URL
#                                      prefix (e.g. a pinned CDN import) that would
#                                      otherwise fail check 1. Every other scheme:// URL
#                                      (other than findly://) still fails.
#   --allow-fetch                      Allows `fetch(` in check 3. XMLHttpRequest,
#                                      WebSocket, sendBeacon and EventSource remain
#                                      banned regardless — no page in this app needs them.
#
# specs/008-privacy-endpoints.md §6.1 — /delete-account is the one page in this app that
# is REQUIRED to load an external resource (the Firebase JS SDK) and REQUIRED to make a
# network call (the actual DELETE /users/me). That rule is the join page's no-oracle /
# capability-URL property (specs/007 §2) and does not apply to /delete-account at all
# (specs/008 §6.1 says so explicitly) — so rather than weakening this script's default
# behavior (which would silently loosen the guarantee for index.html/privacy.html/
# terms.html too), /delete-account is verified by a SEPARATE invocation of this same
# script that opts in, by name, to exactly the two external origins it legitimately needs
# (see web/join/verify-delete-account.sh). index.html/privacy.html/terms.html keep calling
# this script with zero flags, so their behavior is byte-for-byte unchanged from before
# /delete-account existed.
set -euo pipefail

FILE=""
declare -a ALLOWED_PREFIXES=()
ALLOW_FETCH=0

for arg in "$@"; do
  case "$arg" in
    --allow-external-prefix=*)
      ALLOWED_PREFIXES+=("${arg#--allow-external-prefix=}")
      ;;
    --allow-fetch)
      ALLOW_FETCH=1
      ;;
    -*)
      echo "verify-static-security: unknown flag: $arg" >&2
      exit 2
      ;;
    *)
      if [[ -n "$FILE" ]]; then
        echo "verify-static-security: unexpected extra argument: $arg" >&2
        exit 2
      fi
      FILE="$arg"
      ;;
  esac
done

FILE="${FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/index.html}"

if [[ ! -f "$FILE" ]]; then
  echo "verify-static-security: file not found: $FILE" >&2
  exit 2
fi

fail=0

echo "== checking $FILE =="

# 1. No URI-scheme reference other than the in-app findly:// deep link and any explicitly
#    allowlisted prefix (--allow-external-prefix, empty by default) — this is the single
#    allowed exception (specs/007 §2's "Open in the app" affordance, plus specs/008 §6.1's
#    named exception for /delete-account). Anything else with a "scheme://" shape (http,
#    https, ftp, protocol-relative-looking tokens, a CDN URL, etc.) is a spec violation.
external_urls=$(grep -oE '[A-Za-z][A-Za-z0-9+.-]*://[^"'"'"'[:space:]<>]*' "$FILE" | grep -vi '^findly://' || true)
if [[ -n "$external_urls" && ${#ALLOWED_PREFIXES[@]} -gt 0 ]]; then
  filtered=""
  while IFS= read -r url; do
    [[ -z "$url" ]] && continue
    allowed=0
    for prefix in "${ALLOWED_PREFIXES[@]}"; do
      if [[ "$url" == "$prefix"* ]]; then
        allowed=1
        break
      fi
    done
    if [[ "$allowed" -eq 0 ]]; then
      filtered="${filtered}${url}"$'\n'
    fi
  done <<< "$external_urls"
  external_urls="$(printf '%s' "$filtered" | sed '/^$/d')"
fi
if [[ -n "$external_urls" ]]; then
  echo "FAIL: external URL reference(s) found:" >&2
  echo "$external_urls" >&2
  fail=1
fi

# 2. No protocol-relative resource reference (e.g. src="//cdn.example.com/lib.js"). No
#    page — including /delete-account — has a legitimate reason to use one (explicit
#    https:// is always used instead), so this is never opt-outable.
protocol_relative=$(grep -noE '(src|href)[[:space:]]*=[[:space:]]*"//[^"]*"' "$FILE" || true)
if [[ -n "$protocol_relative" ]]; then
  echo "FAIL: protocol-relative resource reference(s) found:" >&2
  echo "$protocol_relative" >&2
  fail=1
fi

# 3, 4 & 5 scan only the executable <script>...</script> body, not prose (the security-
# invariant comment block in <head> legitimately *names* fetch/localStorage/getAnalytics/
# etc. while documenting that this file must never use them — matching the whole file
# would flag that documentation as if it were a violation). Matches both a bare <script>
# tag (index.html/privacy.html/terms.html) and one carrying attributes such as
# type="module" (delete-account.html). Whole-line `//` JS comments are then dropped too,
# for the same reason: a comment naming a banned primitive while documenting that the
# code deliberately does NOT call it (delete-account.html does this a lot, e.g. "NOT
# calling getAnalytics()") is not executable code and must not trip the check — only
# live code should. This does not weaken detection of a real violation: an actual
# fetch()/localStorage/etc. call is never itself a comment.
script_body=$(awk '/<script[ >]/{flag=1; next} /<\/script>/{flag=0} flag' "$FILE" | grep -vE '^[[:space:]]*//' || true)

# 3. No network-call primitive of any kind, except `fetch(` when --allow-fetch is passed
#    (delete-account.html's one legitimate call to DELETE /users/me). XMLHttpRequest,
#    WebSocket, sendBeacon and EventSource stay banned unconditionally — no page needs them.
if [[ "$ALLOW_FETCH" -eq 1 ]]; then
  network_pattern='\bXMLHttpRequest\b|\bnew[[:space:]]+WebSocket\b|\bsendBeacon\b|\bEventSource\b'
else
  network_pattern='\bfetch[[:space:]]*\(|\bXMLHttpRequest\b|\bnew[[:space:]]+WebSocket\b|\bsendBeacon\b|\bEventSource\b'
fi
network_calls=$(printf '%s\n' "$script_body" | grep -noE "$network_pattern" || true)
if [[ -n "$network_calls" ]]; then
  echo "FAIL: network-call primitive found in <script>:" >&2
  echo "$network_calls" >&2
  fail=1
fi

# 4. No cookies, no localStorage/sessionStorage — every page, including /delete-account,
#    must persist nothing of its own (specs/008 §6.1: "nothing persisted beyond the
#    Firebase SDK's own session handling" — the SDK's own storage happens inside the
#    imported library, never in this file's own code, so this check is never opt-outable).
storage_calls=$(printf '%s\n' "$script_body" | grep -noE 'document\.cookie|\blocalStorage\b|\bsessionStorage\b' || true)
if [[ -n "$storage_calls" ]]; then
  echo "FAIL: cookie/storage usage found in <script>:" >&2
  echo "$storage_calls" >&2
  fail=1
fi

# 5. No analytics/telemetry primitive of any kind, on ANY page, unconditionally (specs/008
#    §6.1 forbids analytics on /delete-account specifically; index.html/privacy.html/
#    terms.html never had any to begin with, so this is a no-op for them). Deliberately
#    also bans `measurementId` — the one Firebase config field this app must never set.
analytics_calls=$(printf '%s\n' "$script_body" | grep -noE '\bgetAnalytics[[:space:]]*\(|\blogEvent[[:space:]]*\(|\bmeasurementId[[:space:]]*:|\bgtag[[:space:]]*\(|google-analytics\.com|googletagmanager\.com|firebase-analytics' || true)
if [[ -n "$analytics_calls" ]]; then
  echo "FAIL: analytics/telemetry usage found in <script>:" >&2
  echo "$analytics_calls" >&2
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "== RESULT: FAIL — $FILE violates the static security invariants ==" >&2
  exit 1
fi

echo "== RESULT: OK — no unlisted external resources, no banned network calls, no cookies/storage, no analytics =="
