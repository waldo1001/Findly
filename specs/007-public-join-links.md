# 007 — Public HTTPS join links, landing page & QR

## Goal

Make group joining work for people who **don't have the app yet** — the convention scenario (005 groups at real-world events, attendees worldwide): the owner shares/prints one QR code; scanning it either opens the app directly on the join screen (installed) or lands on a tiny static page showing the join code and store links (not installed). This spec owns the link format, the landing page and its security invariants, the `.well-known` association files, the hosting/deploy model, and the client integration contract. Product model of groups stays in [005](005-temporary-groups.md); wire shapes of the join API stay in [001 §12.6](001-api-contract.md) — this spec adds **no API endpoint and no storage**.

RFC 2119 keywords (MUST/SHOULD/MAY) are used normatively. Promoted from 000 §O16 (product-owner decision, 2026-07-22 — see 000 §D16).

## 1. Link format

```
https://{JOIN_LINK_HOST}/g#{CODE}
```

- `{CODE}` is the group join code (001 §1.4 format), accepted in canonical (`7F3K9QRZ`) or hyphenated display form (`7f3k-9qrz`) — consumers apply the same normalization as 001 §12.6 (uppercase, strip hyphens) before use.
- The code travels in the **URL fragment**, never in the path or query. Fragments are not sent by browsers to the server, so the capability **never appears in any server, CDN, or proxy log** by construction. This is the load-bearing privacy property of the whole design; a path- or query-carried code is a spec violation.
- `JOIN_LINK_HOST` is a **deployment constant** (like the API base URL): v1 value is the Static Web App's default hostname, recorded at provisioning (H4, `docs/azure-setup.md` §7) and baked into client build config (003 §13, 004 §8). A custom domain later is **additive** — the SWA serves both hosts, old printed QR codes keep working; new prints use the new host. Changing the host is a client-release event (intent filters / entitlements name it), acceptable pre-launch.
- The existing in-app deep link `findly://group-join?code={CODE}` (003/004) **remains valid** unchanged. Once this spec ships, the https form is the canonical one for sharing and QR; the `findly://` form remains as the landing page's "open the app" affordance and for backward compatibility.

## 2. Landing page — `GET /g`

A single static HTML page (inline CSS/JS, no framework), served for `/g` regardless of fragment. Behavior:

1. Client-side JS reads `location.hash`, normalizes it (§1), and if it parses as a plausible code, displays it in hyphenated display form with a copy-to-clipboard button.
2. Offers, in order: an **"Open in the app"** link (`findly://group-join?code={CODE}` — works when the app is installed but the OS didn't intercept, e.g. in-browser navigation); **store badges** (Play / App Store — hidden or "coming soon" until the listings exist, H5/H6); and the instruction to install, then re-scan the QR or type the displayed code.
3. No fragment / unparsable fragment → the same page without the code block ("scan the group's QR code or ask for the code").

**Security invariants (normative):**

- The page is **fully static**: it MUST NOT call any API, read any storage, or embed any analytics/telemetry/third-party resource. It renders identically whether the code exists, is expired, or is garbage — there is **no existence oracle**.
- The code MUST NOT be validated, resolved, or logged server-side (it can't be — the server never receives the fragment; keep it that way).
- The page MUST NOT persist the code anywhere (no cookies/localStorage).
- Join enforcement (`GROUP_CODE_INVALID`, `GROUP_EXPIRED`, `GROUP_FULL`, App-Check-gated sign-in…) happens exactly where it already lives: in the app against 001 §12.6. The link surface adds zero trust.

## 3. `.well-known` association files (same host)

| File | Consumer | Content requirements |
|---|---|---|
| `/.well-known/assetlinks.json` | Android App Links verifier | `relation: ["delegate_permission/common.handle_all_urls"]`, `android_app` target with the package name and the **debug + release SHA-256 signing fingerprints** (release added when the keystore exists — H5; same fingerprints as the Firebase/App Check registration, 006 §6.5) |
| `/.well-known/apple-app-site-association` | Apple's CDN (Universal Links) | `applinks.details[].appIDs: ["{TEAMID}.{bundleId}"]`, `components: [{ "/": "/g" }]`. **TeamID is enrollment-gated** (H6): the file ships with the structure in place and gains the real appID once the Apple Developer membership exists — a server-side file update, no app change |

**Implementation note, confirmed against the live H4 deployment (2026-07-22):** Azure Static Web Apps' route-level `headers` override for `Content-Type` does not reliably apply to extensionless files — a documented platform quirk (Azure/static-web-apps#402 and related reports), not a config mistake. The AASA file's actual content lives at `.well-known/apple-app-site-association.json` (so SWA's extension-based MIME detection serves it correctly as `application/json`), with a `staticwebapp.config.json` **`rewrite`** rule (not `redirect` — the client-visible URL and response never change, satisfying this section's no-redirect requirement) mapping the extensionless `/.well-known/apple-app-site-association` path Apple's CDN actually requests to that file. `assetlinks.json` needed no such workaround since it already carries a recognized extension.

Serving rules (normative): both files MUST be served over HTTPS with no redirect; the AASA MUST have `Content-Type: application/json`. Fragment is irrelevant to path matching on both platforms (it still arrives in the URL delivered to the app).

## 4. Client integration (contract here; platform detail in 003 §12.3 / 004 §3.5)

- **Android:** a second intent filter on the existing entry activity — `https` / `{JOIN_LINK_HOST}` / path `/g`, `android:autoVerify="true"`. The delivered URI's fragment goes through the **same whitelist sanitizer** as the `findly://` path (`GroupJoinCodeSanitizer`); wrong host or path is ignored, never mis-routed.
- **iOS:** Associated Domains entitlement `applinks:{JOIN_LINK_HOST}` — **requires a paid Apple Developer membership**; prepared now, activated at H6. SwiftUI delivers universal links through the existing `.onOpenURL`; `GroupCodeParsing` gains the https form (host + `/g` path + fragment) alongside the `findly://` form, same charset whitelist, wrong host/path rejected.
- **Share & QR:** the share-sheet text switches to the §1 https link (code in fragment). The group detail screen renders a **QR code of that link, generated on-device** — using a networked QR service would leak the capability and is a spec violation. Both platforms MUST generate locally (iOS: CoreImage `CIQRCodeGenerator`; Android: a local generator library, reviewed as a new dependency).
- A link with a valid host/path but no usable fragment opens the join screen with an empty code field (no error).

## 5. Hosting & deployment

- **Azure Static Web Apps, Free tier** — one resource (H4), also the future home of the web viz (000 §Architecture) and of the store-required legal pages (`/privacy`, `/terms` — authored in H7, hosted here). Free tier includes the default hostname with TLS and free managed certificates for a later custom domain.
- Repo artifact: **`web/join/`** — `index.html` is not required at root; the deploy maps `/g` and `/.well-known/*` (SWA `staticwebapp.config.json` for routes/headers, including the AASA content-type override).
- CI/CD: a new GitHub Actions workflow deploys `web/join/**` on push to `main`. Auth follows the repo's hard rule — **no long-lived secret stored**: `azure/login` via the existing OIDC federated credential, then the SWA deployment token is **fetched at run time** (`az staticwebapp secrets list`) and passed to the deploy step in-memory. The OIDC app registration needs a role on the SWA resource (H4).
- The workflow MUST NOT gain repo-wide permissions beyond `contents: read` + `id-token: write` (matching `backend.yml`'s posture).
- **Security headers (normative, site-wide).** Azure Static Web Apps sets **no** framing protection by default — `globalHeaders` is opt-in. Every page served from this host MUST therefore be delivered with `X-Frame-Options: DENY` **and** `Content-Security-Policy: frame-ancestors 'none'` (both: the CSP directive is the modern one, the header the fallback for older agents), declared once as `globalHeaders` in `staticwebapp.config.json` rather than per route. No page here is ever legitimately framed. This became load-bearing with the deletion page (008 §6): a clickjacked join flow is an annoyance, but a clickjacked deletion flow walks a signed-in user through disguised clicks into **irreversible, cascading** erasure — a documented multi-step technique that an SMS step raises the bar against but does not close.

## 6. Non-goals & deferred (explicit)

- **Deferred install attribution** (carrying the code through a store install — Play Install Referrer / clipboard heuristics): out of scope; the v1 answer is the landing page showing the code as text, and the person re-scans or types it after installing. Honest and zero-magic.
- **URL shorteners / per-event vanity links** — the QR carries the full link; nothing shorter is needed.
- **The web map/viz app** — remains future web-spec scope; this SWA merely reserves its home.
- **Custom domain** — additive later (SWA hostname binding + free managed cert); forces the 000 §O10 naming/trademark decision when it happens.

## 7. Test checklist (conforming implementations)

- **Link parsing (both clients):** accepts `https://{host}/g#7F3K9QRZ` and `#7f3k-9qrz` (normalized identically to 001 §12.6); rejects wrong host, wrong path, empty/garbage fragment (→ join screen without prefill, no error state); `findly://group-join?code=…` behavior unchanged; parsing is whitelist-based (no bypass via encoding tricks).
- **QR:** content is exactly the §1 link; generation is local (no network call in the QR path — assert no URL-loading in unit tests / dependency review).
- **Landing page:** contains zero `fetch`/XHR/external resource references (statically assertable); renders the code block only for a plausible fragment; renders identically for existing vs. nonexistent codes (no oracle).
- **Association files:** valid JSON, correct content types, no redirects (verified against the live host at H4/H5/H6 as fingerprints/TeamID land).
- **Capability hygiene:** repo grep — no real join code committed; sample codes in docs/tests use obviously fictional values (`7F3K9QRZ` class); no code ever logged client-side in the new paths.

## Open questions

None — deferred matters are listed in §6; the naming/domain decision is tracked as 000 §O10 (escalated, see docs/store-readiness.md).
