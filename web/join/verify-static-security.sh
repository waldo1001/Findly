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
#                                      otherwise fail check 1 OR check 8 (an ES-module
#                                      import of that same prefix) — one list, read by
#                                      both checks, so there is exactly one allowlist to
#                                      review rather than two that can drift apart. Every
#                                      other scheme:// URL / module import (other than
#                                      findly://) still fails.
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

# W4 (docs/implementation-handoff.md): checks 3-7 below shell out to `node` (a real
# static-analysis pass, not shell grep, per the round-3 W3 hardening). Without this guard,
# a missing `node` on PATH made `set -euo pipefail` kill the script with an unguarded
# "command not found" and a bare non-zero exit — safe (still non-zero, CI still red) but
# ugly and confusing to read. Fail the same way a missing file does: one clean message,
# exit 2 (a setup/environment problem, distinct from exit 1's "the page violates the
# invariants").
if ! command -v node >/dev/null 2>&1; then
  echo "verify-static-security: node is required but was not found on PATH" >&2
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
#
# Code-review finding (2026-08-26): the previous extraction here was a line-based awk
# state machine (`/<script[ >]/{flag=1; next} /<\/script>/{flag=0} flag`) that mis-handles
# a single-line `<script>...</script>` tag — the line matches the open pattern, sets the
# flag, and immediately `next`s past that same line, so the closing pattern on it never
# fires; its content is skipped entirely rather than extracted, silently hiding whatever
# it contains from checks 3-5 below. Replaced with a regex-based extraction (dotall,
# global) that captures every <script>...</script> body correctly regardless of whether
# the tag is single- or multi-line, or how many such tags the file has.
script_body=$(node -e '
  const fs = require("fs");
  const html = fs.readFileSync(process.argv[1], "utf8");
  const re = /<script[^>]*>([\s\S]*?)<\/script>/gi;
  let m, out = [];
  while ((m = re.exec(html)) !== null) {
    out.push(m[1]);
  }
  process.stdout.write(out.join("\n"));
' "$FILE" | grep -vE '^[[:space:]]*//' || true)

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

# 6. No inline event-handler attribute (onload=, onclick=, onerror=, ...) anywhere, on ANY
#    page, unconditionally — never opt-outable, like check 2. An inline handler executes
#    JS entirely outside any <script> tag, so no script-body extraction — however correct
#    — can ever see a leak hidden behind one (e.g. `onload="window.__x = location.search"`
#    on <body>). No page in this app needs one: every page's interactivity is wired with
#    addEventListener from inside a real <script> block, which checks 3-5 already cover.
#
# Round-3 code-review findings on the round-2 version of this check, all fixed together
# below by moving the whole check into node instead of patching the shell grep further
# (a line-based grep cannot be made to handle all of these at once without becoming as
# complex as the node version, and less legible):
#   - FIX 1: the grep had no -i, so `<body ONLOAD=...>` / `OnLoad=` — fully live in every
#     browser — passed. This check now matches case-insensitively.
#   - FIX 2: comment-stripping here (and in verify-family-invite.sh, fixed there too)
#     stopped only at "-->". Per the WHATWG tokenizer's comment-end-bang state, a browser
#     also ends a comment at "--!>" — so `<!--x--!><body onload=...>y-->` was stripped as
#     ONE comment (the real terminator ">" is only found at the trailing "y-->"), deleting
#     the live onload attribute along with it and hiding it from this check entirely. The
#     stripper below now terminates at the first of "-->" or "--!>", matching the browser.
#   - FIX 3: the grep was line-based, so `onload\n="alert(1)"` (a newline between the
#     attribute name and "=", valid HTML) was invisible to it. The node scan below walks
#     the tag character-by-character and uses \s (which matches newlines), not a per-line
#     regex, so this no longer matters.
#   - FIX 4: the grep matched raw text position, not attribute-name boundaries, so
#     `<p data-example=" onload=triggered">` (the string "onload=" sitting inside an
#     unrelated attribute's quoted VALUE, not a live attribute name) tripped it. The scan
#     below tracks quote state per tag and only evaluates the "on...=" pattern when
#     genuinely outside any quoted value, at an actual attribute-name boundary.
#
# 7. (docs/implementation-handoff.md row W4; specs/007 §2/§7) No `<script src="...">` of
#    ANY kind, on ANY page, unconditionally — never opt-outable, like checks 2 and 6. The
#    gap this closes: check 1 only bans a `scheme://` URL, so a same-origin RELATIVE
#    `<script src="leak.js">` sailed through it, and the referenced sibling .js file was
#    then never read by checks 3-6 (which scan only inline <script> BODIES) — every
#    no-oracle / zero-external-resource guarantee this script enforces was therefore only
#    ever enforced for inline script. The decision (W4, made explicitly rather than
#    defaulting) is option (a) — ban the attribute outright — not option (b) — teach every
#    check to resolve and recursively scan same-origin `src` targets — because these pages
#    are deliberately zero-dependency, so the ban is cheap and total, and (b) would turn
#    four shell scripts into a small static-analysis tool. This bans the ATTRIBUTE on a
#    <script> tag specifically: an inline <script> with no src, the word "src" inside an
#    unrelated attribute's quoted value or inside comment prose (stripped above), and
#    `<img src=...>`/`<link href=...>` are all untouched. Reuses the same tag-boundary +
#    quote-tracking scan as findInlineHandlers (same idiom, same file, per the task's
#    instruction not to add a second, fragile shell grep for this).
#
# 8. (docs/implementation-handoff.md row W4, coordinator follow-up) Check 7 banned the
#    ATTRIBUTE (`<script src=...>`) but a sibling .js file that no gate ever reads can
#    also be pulled in as an ES module, which check 7 has no opinion on at all:
#    `import x from "./evil.js"`, a bare `import "./evil.js"`, or a dynamic
#    `import("./evil.js")` / `await import("./evil.js")` all load exactly the thing this
#    row exists to stop, via syntax with no `src` attribute anywhere. Banned the same way
#    as check 7 — unconditionally — with ONE exception routed through the SAME
#    --allow-external-prefix allowlist check 1 already uses (not a filename special-case,
#    not a blanket https:// exemption): delete-account.html's
#    `import { initializeApp } from "https://www.gstatic.com/firebasejs/.../firebase-app.js"`
#    is already let through check 1 by that exact mechanism, so this check reads the same
#    list rather than inventing a second allowlist with its own drift risk.
NODE_INLINE_CHECK="$(mktemp)"
cat > "$NODE_INLINE_CHECK" <<'NODEEOF'
"use strict";
const fs = require("fs");
// NOTE: this file is invoked as `node "$NODE_INLINE_CHECK" "$FILE"` (a real script file,
// not `node -e`), so argv[0]=node, argv[1]=this script's own path, argv[2]=the target
// file — unlike the `node -e '...' "$FILE"` calls elsewhere in this file, where argv[1]
// IS the target (no script-file slot to shift it). Using argv[1] here would silently
// read this checker's own source instead of the page under test, passing unconditionally.
const html = fs.readFileSync(process.argv[2], "utf8");
// Check 8's allowlist: same --allow-external-prefix values check 1 already validated
// against (argv[3] onward — see the bash invocation below). Empty when none were passed.
const allowedPrefixes = process.argv.slice(3);

// FIX 2 — stop at the first of "-->" or "--!>" (WHATWG comment-end-bang state), not only
// "-->". A comment OUTSIDE a <script> tag terminating early means the markup after it is
// live, not commented; treating only "-->" as terminal hid that markup from this check.
const stripped = html.replace(/<!--[\s\S]*?(?:-->|--!>)/g, "");

// Scans each raw "<...>" tag region (a lightweight tag boundary, not a full parser — good
// enough here: we only need to find attribute NAME occurrences, and even a mis-scoped
// region still gets scanned in full, so this stays fail-safe rather than fail-open).
// Tracks simple quote state character-by-character so text inside a quoted attribute
// VALUE is never mistaken for an attribute NAME (FIX 4), matches "on<letters>" followed
// by optional whitespace (: includes newlines, so a newline before "=" is covered — FIX 3)
// then "=", case-insensitively (FIX 1).
function findInlineHandlers(s) {
  const tagRe = /<[^<>]*>/g;
  const found = [];
  let m;
  while ((m = tagRe.exec(s)) !== null) {
    const tagText = m[0];
    let quote = null;
    for (let i = 1; i < tagText.length - 1; i++) {
      const ch = tagText[i];
      if (quote) {
        if (ch === quote) quote = null;
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        continue;
      }
      const prev = tagText[i - 1];
      const atBoundary = i === 1 || /\s/.test(prev);
      if (!atBoundary) continue;
      const attrMatch = /^on[a-zA-Z]+\s*=/i.exec(tagText.slice(i));
      if (attrMatch) {
        found.push(attrMatch[0].replace(/\s*=$/, ""));
      }
    }
  }
  return found;
}

// Check 7 — scans each raw "<script ...>" opening-tag region (same lightweight tag
// boundary as findInlineHandlers above, not a full parser) for a `src` attribute NAME,
// tracking quote state so "src" appearing inside a quoted attribute VALUE (e.g.
// `<script data-note="src=fake">`) is never mistaken for the attribute itself. Matches
// `<SCRIPT ...>` case-insensitively and tolerates a newline between the tag name and the
// attribute (`<script\n  src=...>`, valid HTML — \s covers it, same as findInlineHandlers).
// One report per offending tag is enough (`break` after the first match).
function findScriptSrc(s) {
  const tagRe = /<script\b[^<>]*>/gi;
  const found = [];
  let m;
  while ((m = tagRe.exec(s)) !== null) {
    const tagText = m[0];
    let quote = null;
    for (let i = 1; i < tagText.length - 1; i++) {
      const ch = tagText[i];
      if (quote) {
        if (ch === quote) quote = null;
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        continue;
      }
      const prev = tagText[i - 1];
      const atBoundary = /\s/.test(prev);
      if (!atBoundary) continue;
      const attrMatch = /^src\s*=/i.exec(tagText.slice(i));
      if (attrMatch) {
        found.push(tagText.replace(/\s+/g, " ").trim());
        break;
      }
    }
  }
  return found;
}

// Check 8 helpers. Restricting the scan to <script>...</script> BODY content (same
// extraction shape as the separate `script_body` node -e call above, redone here so this
// one node invocation is self-contained) is what keeps this false-positive-safe: the word
// "import" in ordinary page prose (outside any <script> tag) or inside an unrelated
// attribute's quoted value never enters this scan at all, because it is never inside a
// <script> body to begin with.
function extractScriptBodies(s) {
  const re = /<script[^>]*>([\s\S]*?)<\/script>/gi;
  const bodies = [];
  let m;
  while ((m = re.exec(s)) !== null) {
    bodies.push(m[1]);
  }
  return bodies.join("\n");
}

// Drops whole-line `//` JS comments, same rule and same reasoning as the `script_body`
// extraction above (checks 3-5): a comment that merely NAMES "import" while documenting
// that the code deliberately does not do one static-analysis this crude cannot reliably
// tell from an inline trailing `// comment`, so — like checks 3-5 — this is a known,
// deliberate scope limit (whole-line comments only), not a claim of full JS-comment
// awareness.
function stripLineComments(s) {
  return s
    .split("\n")
    .filter((line) => !/^\s*\/\//.test(line))
    .join("\n");
}

// Check 8 — bans every ES-module import of anything but an allowlisted prefix:
//   - static, named/default/namespace, with "from": import x from "./y.js";
//     import { a } from "y.js"; import * as ns from "../y.js";
//   - static, bare side-effect, no "from": import "./y.js";
//   - dynamic: import("./y.js")  /  await import("./y.js")  /  import("./y.js").then(...)
// All three regexes use \s (matches newlines too, so `import\n  from "..."` and
// `import\n("...")` are covered) and the /i flag (defense in depth, matching this file's
// existing convention of matching case-insensitively even where the real grammar is
// case-sensitive — see FIX 1 above). The "from" variant's `[^'"();]*?` gap deliberately
// excludes quotes/parens/semicolons between "import" and "from" so it can never bridge
// across an unrelated statement (a real import clause — identifiers, `{`, `}`, `,`, `*`,
// `as` — never itself contains any of those four characters).
function findModuleImports(s, allowed) {
  const scanText = stripLineComments(extractScriptBodies(s));
  const found = [];
  function isAllowed(spec) {
    return allowed.some((p) => p.length > 0 && spec.indexOf(p) === 0);
  }
  function scan(re) {
    let m;
    while ((m = re.exec(scanText)) !== null) {
      const spec = m[2];
      if (!isAllowed(spec)) {
        found.push(m[0].replace(/\s+/g, " ").trim());
      }
    }
  }
  scan(/\bimport\b[^'"();]*?\bfrom\s*(['"])((?:\\.|(?!\1)[^\\])*)\1/gi);
  scan(/\bimport\s*(['"])((?:\\.|(?!\1)[^\\])*)\1/gi);
  scan(/\bimport\s*\(\s*(['"])((?:\\.|(?!\1)[^\\])*)\1/gi);
  return found;
}

const handlers = findInlineHandlers(stripped);
handlers.forEach((h) => console.log("HANDLER:" + h));

const scriptSrcs = findScriptSrc(stripped);
scriptSrcs.forEach((t) => console.log("SCRIPTSRC:" + t));

const moduleImports = findModuleImports(stripped, allowedPrefixes);
moduleImports.forEach((t) => console.log("MODULEIMPORT:" + t));

process.exit(
  handlers.length > 0 || scriptSrcs.length > 0 || moduleImports.length > 0 ? 1 : 0
);
NODEEOF
# Check 8 reads the SAME --allow-external-prefix list check 1 uses (see the "8." comment
# above) — passed as extra argv entries. Guarded so an empty ALLOWED_PREFIXES array is
# never expanded via "${ALLOWED_PREFIXES[@]}" under `set -u`: older bash (macOS's stock
# 3.2, which this repo elsewhere goes out of its way to stay compatible with — see
# verify-delete-account.sh's plain-array comment) raises "unbound variable" for that
# expansion specifically when the array is empty, even though the array itself is declared.
if [[ ${#ALLOWED_PREFIXES[@]} -gt 0 ]]; then
  node_check_output=$(node "$NODE_INLINE_CHECK" "$FILE" "${ALLOWED_PREFIXES[@]}" || true)
else
  node_check_output=$(node "$NODE_INLINE_CHECK" "$FILE" || true)
fi
rm -f "$NODE_INLINE_CHECK"
inline_handlers=$(printf '%s\n' "$node_check_output" | grep '^HANDLER:' | sed 's/^HANDLER://' || true)
script_srcs=$(printf '%s\n' "$node_check_output" | grep '^SCRIPTSRC:' | sed 's/^SCRIPTSRC://' || true)
module_imports=$(printf '%s\n' "$node_check_output" | grep '^MODULEIMPORT:' | sed 's/^MODULEIMPORT://' || true)
if [[ -n "$inline_handlers" ]]; then
  echo "FAIL: inline event-handler attribute(s) found:" >&2
  echo "$inline_handlers" >&2
  fail=1
fi
if [[ -n "$script_srcs" ]]; then
  echo "FAIL: <script src=...> found — external/sibling .js files are banned on these pages (docs/implementation-handoff.md row W4; specs/007 §2/§7 — no gate reads the referenced file, so the attribute is banned outright rather than resolved and scanned):" >&2
  echo "$script_srcs" >&2
  fail=1
fi
if [[ -n "$module_imports" ]]; then
  echo "FAIL: ES-module import of a non-allowlisted specifier found — external/sibling .js files are banned on these pages the same way <script src> is (docs/implementation-handoff.md row W4 follow-up; specs/007 §2/§7). Use --allow-external-prefix if this import is a legitimate, reviewed exception (like /delete-account's Firebase SDK import):" >&2
  echo "$module_imports" >&2
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "== RESULT: FAIL — $FILE violates the static security invariants ==" >&2
  exit 1
fi

echo "== RESULT: OK — no unlisted external resources, no banned network calls, no cookies/storage, no analytics, no <script src>, no unlisted module import =="
