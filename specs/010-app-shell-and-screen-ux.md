# 010 — App shell & screen UX (map-first navigation, map camera, devices, invites)

## Goal

Replace the "minimal reachability wiring" both clients ship today — a Home screen that is a vertical list of buttons, each feature screen a dead-simple push off it — with the app's first real shell: the **Family Map is the root screen**, a **navigation drawer** behind a ☰ button reaches everything else, the map is **full-bleed with the roster in a detent bottom sheet**, and the map camera finally has specified behavior (fit-all on load, tap-a-member to zoom). The same batch fixes the worst first-run defect in the field — a signed-in user without a profile gets a dead-end "We couldn't find your profile" error card with a Retry that can never succeed, on every feature screen — and revamps the two ugliest surfaces (Devices, Invite someone). This spec is cross-platform with per-platform subsections (the 009 pattern); it owns client **navigation, screen layout, and camera behavior** only. Wire shapes stay in [001](001-api-contract.md); the family-invite **link format, landing page, and share-message copy** live in [007](007-public-join-links.md) (amended alongside this spec); design tokens/components stay contracted in [003 §4](003-android-client.md) / [004 §2](004-ios-client.md).

RFC 2119 keywords (MUST/SHOULD/MAY) are used normatively. Supersedes the screen-layout halves of backlog tasks A27/I28 (design 2a wave 2); the Ember/Dusk handoff (`design/findly-design-system/2a-ember-dusk/HANDOFF.md`) remains the visual reference, with the corrections in §7.

## 1. App shell — map-first root + navigation drawer

**The problem this section exists to prevent.** `003 §12` and `004 §2.6` land every signed-in user on a hub screen that is nothing but a stack of nine `FindlyButton`s — self-described in 003 §12 as "minimal reachability wiring… replaceable by a future design pass". Opening the app to see where your family is — the product's whole point — takes a cold start, a hub screen, and a tap. This is that design pass.

### 1.1 Launch resolution (both platforms, normative)

On cold start, after auth restore (004 §2.6's mechanics are unchanged — splash route, resolve after the UI exists, never re-prompt SMS):

| Signed-in state | Root screen |
|---|---|
| Not signed in | Sign-in (unchanged, 006) |
| Signed in, **profile + family** | **Family Map** (§3) |
| Signed in, **no profile** | **Onboarding** (§2.2, profile-less variant) |
| Signed in, **profile, no family** (groups-only user) | **Onboarding** (§2.2, family-less variant) |

- The probe that decides between the last three rows is `GET /families/me`, exactly as A21/A24/I24 settled it: **probe before any device registration**, and an *inconclusive* probe (timeout, 5xx, transient 401) **fails open** to the Family Map — only a confirmed `PROFILE_NOT_FOUND` / `FAMILY_NOT_FOUND` routes to Onboarding. A blip MUST NOT strand a valid user in onboarding.
- Device registration (`POST /devices`) MUST still be attempted only after the probe confirms a profile exists, and MUST be re-triggered immediately after any §2.2 bootstrap path succeeds (not deferred to the next cold start) — A24/I24's rules, restated here because the code that implements them moves out of the deleted Home screen.
- **The Home hub screen is retired on both platforms.** Android: `Destinations.Home` and `ui/home/*` are deleted; the NavHost start destination becomes the Family Map. iOS: the coordinator's root route renders the Family Map; `showHome()`'s reset-the-stack semantics (004 §2.5) are retained verbatim with the map as the reset target (renaming it `showRoot()` is allowed; the stack-reset rule is what's normative). The launch-gate logic Home used to own (probe → register → route) moves to a pure, platform-agnostic launch component with the same tests.

### 1.2 The drawer

- The Family Map — and only the root screen — renders a **☰ menu button** as part of its floating top chrome (§3.1). Tapping it opens a **navigation drawer** (left edge; Android also opens it with the standard edge swipe, iOS with the button only — no leading-edge drag, per the I19 swipe-back deliberation, which this spec does not reopen).
- Drawer contents, top to bottom (normative order):
  1. Header: family name + the caller's display name (from `GET /families/me`, cached from the launch probe).
  2. **Family map** (current — selected state), **History**, **Geofences**, **Devices**, **Family**, **Invite someone** (rendered only for `myRole == "parent"`), **Groups**, **Privacy & data**.
- Selecting a destination closes the drawer and **pushes** that screen onto the existing stack; the existing back rules (`003 §12.5` / `004 §2.5`) stay authoritative and unchanged — pushed screens show the central back affordance, back lands on the map. The drawer itself is never on the back stack.
- Locate is deliberately **not** a drawer item: it is reached from map member selection (§3.5) — it needs a target.
- New design-system components this shell requires (names added to the 003 §4.3 / 004 §2.3 contracts in the same PR as this spec, per the Bucket-B rule): **`FindlyNavDrawer`**, **`FindlyBottomSheet`** (§3), **`FindlyDropdownField`** (§4). Each is stateless/presentational like every other component; platform-native mechanics underneath (Android: `ModalNavigationDrawer`-class behavior re-skinned through tokens; iOS: a coordinator-driven overlay — there is no UIKit drawer primitive, and that is an implementation detail behind the component).

## 2. Profile dead-ends → onboarding routing (the bug fix)

**The problem this section exists to prevent.** A signed-in user with no profile who reaches any feature screen — Geofences was the reported one, but Map, History, Devices, Family, Invites and Export all behave identically — gets the generic `PROFILE_NOT_FOUND` mapping ("We couldn't find your profile.") in an error card with a **Retry button that is guaranteed to fail forever**, because retrying a `GET` cannot create a profile (001 §1.5.3: only the four bootstrap endpoints can). Home and the groups list special-case this (A21/I17); the other ten screens never did. Reported in the field against Geofences, 2026-08-26.

### 2.1 Routing rule (both platforms, normative)

- **Rule (MUST):** a screen's *load* path receiving `404 PROFILE_NOT_FOUND` MUST NOT render a retryable error state. It routes to **Onboarding** (profile-less variant), resetting the stack (004 §2.5 root-replacement semantics / Android `popBackStack` to a fresh Onboarding root) — there is nothing behind it worth going back to, since every family screen would fail the same way.
- **Rule (MUST):** a *family-scoped* screen's load path receiving `404 FAMILY_NOT_FOUND` (a groups-only user — profile exists, `familyId` null, 001 §1.5.4) routes to **Onboarding** (family-less variant) the same way. Group screens are unaffected — they only need a profile.
- Mutation/action failures (a `PATCH` failing mid-session) keep their existing inline error rendering — this rule is about the load path, where the dead-end lives.
- The user-facing string for the residual fallback (e.g. an unexpected `PROFILE_NOT_FOUND` on a mutation) is unified across platforms as exactly **"We couldn't find your profile."** — Android drops its extra "Please try again." sentence (`ApiErrorUserMessage.kt`), which advised precisely the action that cannot work.

### 2.2 The Onboarding screen

One route, two variants, replacing the two places this UI lives today (iOS Home's `profileless`/`familyless` branches; Android's `GroupsListScreen` `ProfileNeeded` state — both retired in favor of this single screen; the A21/I17 behaviors move here unchanged):

- **Profile-less variant:** welcome copy, a display-name `FindlyTextField` (collected once, carried editable into whichever path is chosen — A21's shipped behavior), then the four bootstrap paths of 001 §1.5.3 as buttons: **Create a family**, **I have an invite code**, **Create a group**, **Join a group**; below, **Privacy & data**. Blank-name guard on all four paths (A21's review finding).
- **Family-less variant** (profile exists): **Create a family**, **I have an invite code**, then **Groups** (the user's live feature) and **Privacy & data**. No display-name field (they have one).
- On any bootstrap success: trigger device registration (§1.1), then reset the stack to the Family Map root.
- Onboarding is a **root** (no back affordance, no drawer).

## 3. Family Map screen

**The problem this section exists to prevent.** Camera behavior was never specified anywhere: Android grew a sensible fit-all policy in code (`MapCamera.kt`); iOS centers on *the first annotation* with a fixed 0.05° span, so a two-country family opens on one member. Both platforms re-run their camera logic on every data refresh, yanking the map out of the user's hands mid-pan. On Android the roster `LazyColumn` below the map has been laid out at zero height since A12 shipped (a `fillMaxSize()` child in an unweighted `Column` starves its sibling — `MapScreen.kt`, and `GroupMapScreen.kt` identically), so the roster is invisible. And tapping a member does nothing on iOS at all.

### 3.1 Layout

- The map is **full-bleed** (edge-to-edge behind system bars, per the existing inset handling) — never an aspect-ratio card (iOS's current 1.4 card is retired), never a `Column` sibling (Android's broken split is retired).
- Floating top chrome, per the Ember/Dusk handoff's Live map screen: the **☰ menu button** (48pt/dp circular, `surface` fill, `level2` shadow — replacing the handoff's "settings button", see §7) and the family pill (family name + "N members").
- The roster lives in a **`FindlyBottomSheet`** with three detents (handoff values, normative): **minimized 186pt/dp** (grabber, "Family" title, summary line, `Locate now` for the selected member when one is selected, avatar stack), **standard 440pt/dp** (header + member list), **expanded** (platform "large" detent; list scrolls). The map stays fully rendered and interactive behind the sheet at every detent — **"maximize the map" is the minimized detent**, not a separate mode. Dragging between detents MUST NOT unmount the list or re-create view models (the I16 `@StateObject` ownership rule; on iOS the detents map to `.presentationDetents`).
- Roster rows keep the existing per-device status chips (Live/Stale/Paused/No location) and the handoff's row states (no-devices row with an `Invite` affordance for parents); subtitles render **humanized relative times** ("24 min ago", recomputed on a 30 s ticker per the handoff — never per frame), replacing the raw ISO strings both platforms show today. The relative-time formatter is pure, shared-logic, and unit-tested.
- A **Refresh** affordance remains (both platforms — iOS currently has none); refresh updates markers and roster without moving the camera (§3.4).

### 3.2 Group map

`GroupMapScreen` adopts the same full-bleed + sheet layout and the same camera policy through the same renderer seam (it currently shares Android's zero-height-roster bug). Group rosters stay position-only (005 §3) — the sheet simply has fewer row fields. This SHOULD ship inside the same task as the family map (same components, same fix); shipping it one task later is acceptable, shipping the layout bug is not.

### 3.3 Marker rendering

Unchanged: one marker per located device, `FindlyMapMarkerBubble` initials, devices without a fix appear only in the roster. Additive: the **selected** member's marker renders in a visually distinct selected state (the component gains a `selected` flag — value-level styling, no new token names).

### 3.4 Camera policy (normative — promoted from `MapCamera.kt`, now contract on both platforms)

Pure, platform-agnostic logic (Android keeps `MapCamera.kt`; iOS gains an equivalent pure `MapCameraPolicy` in FindlyKit — its current first-annotation centering is retired):

| Located points | Camera target |
|---|---|
| 0 | Default: lat 51.0543, lon 3.7174, zoom 4 (calm zoomed-out default, never null island) |
| 1 distinct | Center on it, zoom 15 (`SINGLE_POINT_ZOOM`) |
| 2+ | Bounds-fit all points with **64 dp/pt** padding (density-aware — replaces Android's raw `128px`, which renders differently per device) |

**When the policy runs (MUST):**

1. On the **first successful load** that yields ≥1 located point (and, if the screen opened with zero points, on the first refresh that changes that).
2. On an explicit **fit-all** action: a small floating map button (⌖-class glyph) that re-runs the policy over current points.
3. On **member selection** (§3.5) — an explicit user action.

**Never otherwise.** A data refresh (manual, polling, or push-driven) MUST NOT move the camera — the current behavior on both platforms (re-fit on every marker-set change) is a spec violation once this ships. The user's manual pan/zoom is sacrosanct between explicit actions.

### 3.5 Member selection → zoom + Locate

- **Rule (MUST):** tapping a member's roster row (or their marker) selects that member and animates the camera to their **freshest located device** — the device with the newest `recordedAt` that has a fix — at `SINGLE_POINT_ZOOM`. Selection also: highlights the row and marker, and surfaces a **`Locate now`** action (in the sheet's minimized/standard header, per the handoff) that navigates to the existing **Locate** screen for that member — the push-to-locate flow (001 §6) is unchanged and remains the only thing that requests a fresh fix.
- A member whose devices have no fix can be selected (row highlight, "No location yet" state) but the camera MUST NOT move; `Locate now` remains available (locate is exactly what you want for them).
- Tapping the selected member again, or the map background, deselects.
- This replaces Android's current row-tap behavior (navigate straight to Locate) — Locate is now one deliberate tap further, behind the selection, on both platforms identically.

## 4. Devices screen

**The problem this section exists to prevent.** There is no Devices screen on Android at all — the sync interval renders as read-only text inside Settings and device rename is unreachable UI (the state-holder support has existed since A2, `SettingsStateHolder.updateDeviceSettings`, with no screen calling it). On iOS the interval is a horizontally-scrolling row of chip buttons and the rename field/Save button pair is visibly misaligned (a label-above-field stack jammed beside a bare button — `DeviceSettingsScreen.swift`).

### 4.1 Placement

- **Devices** is a first-class drawer destination on both platforms. Android decomposes its monolithic Settings screen into the same three routes iOS already has — **Devices**, **Family** (members), **Privacy & data** — and retires `ui/settings/SettingsScreen.kt` (which also carries the same off-screen-content layout bug as the map). iOS keeps its three screens.

### 4.2 Per-device card (both platforms, normative)

Top to bottom:

1. Header row: device name (`titleMedium`) + status chip (Active/Paused).
2. "Owner: {ownerDisplayName}" (muted).
3. Parent-only controls (non-parents see 1–2 only, read-only — the 003 §12.1 client-side `isParent` gate is unchanged):
   - **Tracking** `FindlyToggleRow` — commits immediately (unchanged).
   - **Sync interval — a `FindlyDropdownField`** (label "Sync interval", current value shown closed; open presents the 7 allowed values of 001 §1.4 — `5 min, 10 min, 15 min, 30 min, 1 hour, 2 hours, 1 day` — via the platform-native menu: exposed dropdown menu on Android, `Menu`/`Picker` presentation on iOS). Selecting a value **commits immediately** (`PATCH /devices/{id}`), no Save button. Values below `features.limits.minSyncIntervalMinutes` render disabled with the limit as the reason — read from `features`, never hardcoded (000 §Subscription-ready).
   - **Rename row (MUST be a single aligned row):** one horizontal row containing the device-name input and a **Save** button, both the same control height (52 pt/dp), vertically centered on each other. The input carries its label via placeholder + accessibility label, not a stacked label above the field (the stacked label is exactly what misaligns the pair today). Save is disabled while the trimmed draft is empty or unchanged.
4. Errors from this card's mutations render **on this card**, not pooled at the top of the list (iOS's current shared top-of-list `lastActionError` placement is retired).

Empty state unchanged ("No devices yet" / "Devices register automatically after sign-in.").

## 5. Invite someone

**The problem this section exists to prevent.** The created invite is nearly unusable: Android renders the code inside a status chip with no share, no copy, nothing — the inviter reads it off the screen and the invitee retypes it. iOS shares a plain sentence with no link, so the recipient — the one person guaranteed not to have the app — gets a code and no way to get the app; and the shared message can't be copied piecemeal in messengers, while the join screen is a bare text field with no paste help. Meanwhile *groups* have had the full treatment (https link + QR + share) since 007.

Wire shapes are untouched: `POST /families/me/invites` and `POST /invites/accept` (001 §3.3/§3.4) as-is. The **link format, landing page, and exact share text** are owned by 007 (§1/§2/§4 as amended); this section owns the screens.

### 5.1 Create screen (parent-only, both platforms — Android's combined Invites screen splits into create + accept to mirror iOS's two routes)

On success, the created-invite view shows, top to bottom:

1. The code, **large and copyable**: `titleLarge`-class size, tabular figures, letter-spaced, in hyphenated display form (`XXXX-XXXX`, 001 §1.4), with a **`Copy code`** button that copies the *bare code* (display form) to the clipboard and confirms ("Copied").
2. Expiry, computed from the response's `expiresAt` (which iOS currently decodes and drops): the handoff's caption pattern with **72-hour** copy — "It works once and expires in 72 hours." + "Expires {local date/time}". (Corrects the handoff's "24 hours" — the contract says 72 h, 001 §3.3; see §7.)
3. A **QR code of the 007 §1 family-invite link**, generated on-device (007 §4's rule — never a networked QR service; reuse the existing group QR components on both platforms).
4. A **`Share invite`** button → OS share sheet with the exact share text specified in 007 §4 (sentence + code + `https://{JOIN_LINK_HOST}/f#CODE` link).
5. The handoff's footnote, verbatim: "Anyone with this code can see your family's locations, so send it directly to the person joining."
6. A way to create another invite without leaving the screen ("Create another" resets the form).

### 5.2 Accept screen ("Join a family")

- **Smart code field (MUST):** auto-uppercases; accepts and strips hyphens/spaces; renders as `XXXX-XXXX` while typing; whitelist-filters to the Crockford-base32 charset (001 §1.4 — shared pure formatter logic, unit-tested; normalization before the network call is unchanged). Never submits more than the normalized 8 chars.
- **Paste affordance (MUST be explicit-action only):** when the clipboard plausibly holds a code or an invite link, offer a paste control (iOS: `UIPasteControl`-class; Android: a "Paste code" chip). The clipboard is read **only on the user's tap on that control** — never automatically on screen entry (Android 12+ surfaces clipboard reads as a system toast; ambient reading is a privacy smell either way). Pasting an invite *link* extracts the fragment code via the same 007 parsing.
- **Deep-link prefill:** an incoming 007 family-invite link (https or `findly://` form) opens this screen with the code prefilled — the exact mirror of the group-join flow; parsing rules in 007 §4.
- Display-name field: kept (the wire requires it, 001 §3.4), prefilled with the caller's existing profile `displayName` when one exists.
- The join button disables until both fields are non-blank (Android's existing guard becomes the rule on both platforms). Invalid/expired codes render the handoff's inline panel copy (error codes: 001's `INVITE_INVALID` / `INVITE_ALREADY_USED` / `INVITE_EXPIRED`).
- On success: reset to the Family Map root (§1.1's post-bootstrap rule) — iOS's current terminal "Welcome!" dead-end state is retired.

## 6. Screen inventory delta

| Change | Android | iOS |
|---|---|---|
| Root | `Destinations.Home` → Family Map; `ui/home/*` deleted | `.home` hub deleted; root route renders `LiveMapScreen` |
| New route: Onboarding (§2.2) | new destination + screen | new `AppRoute` case + screen |
| New route: Devices | new (extracted from Settings) | exists (`DeviceSettingsScreen`) |
| New route: Family (members) | new (extracted from Settings) | exists (`FamilyMembersScreen`) |
| Settings monolith | retired | n/a |
| Invites | combined screen splits into Create invite + Join a family | two routes already; Accept gains §5.2 |
| Drawer | `FindlyNavDrawer` on the map root | same |
| Retired states | `GroupsListScreen.ProfileNeeded` (→ Onboarding) | Home `profileless`/`familyless` branches (→ Onboarding) |

Everything not named here (History, Geofences, Locate, Groups screens, Privacy screens, Sign-in, permission flows) is reachable from the drawer or unchanged flows and is **not restyled by this spec**.

## 7. Corrections to the Ember/Dusk handoff (recorded, not silently diverged)

Per the A26/A30 convention, where this spec disagrees with `design/findly-design-system/2a-ember-dusk/HANDOFF.md`, this spec wins and the disagreement is recorded:

1. **Invite expiry copy:** the handoff's "expires in 24 hours" contradicts the contract's 72 h (001 §3.3). This spec's §5.1 copy is normative.
2. **Sync-interval control:** the handoff's "four segmented pills (1 min / 5 min / 15 min / 1 hr)" is doubly wrong — "1 min" is not in the 001 §1.4 allowed set, and four pills cannot present seven values. Product decision 2026-08-26: a dropdown (§4.2), not pills.
3. **Live-map top chrome:** the handoff's "48pt circular settings button" becomes the ☰ drawer button (§1.2) — the handoff predates the navigation decision.
4. The handoff's "Places" naming for geofences, and its map-based geofence editor, are **deferred** with the geofence UI revamp (000 §O20) — the menu says "Geofences" and the existing editor ships unchanged for now.

## 8. Non-goals & deferred (explicit)

- **Geofences UI revamp** (map-based place picker, radius-on-map, "Places" rename) — deferred to its own spec; tracked as 000 §O20. This batch only removes the dead-end routing (§2).
- **Bottom navigation / tab bar** — considered and rejected for v1 (drawer chosen, 000 §D18).
- **Merging Locate into the map** (auto-firing a fresh-fix request on selection) — deferred; the Locate screen stays.
- **iOS swipe-back** — still owned by I19's open deliberation; this spec neither adds nor forecloses it.
- **Store screenshot regeneration** — required after implementation (`design/store-assets/`, `docs/store-submission-pack.md`), tracked in the backlog batch note, not here.

## 9. Error cases

All codes from the 001 §10 catalog — none added:

- `PROFILE_NOT_FOUND` on a screen load → route to Onboarding (§2.1), never a retryable error card. Residual fallback string unified (§2.1).
- `FAMILY_NOT_FOUND` on a family-scoped screen load → Onboarding, family-less variant (§2.1).
- `VALIDATION_FAILED` / `402 LIMIT_EXCEEDED` on `PATCH /devices` (interval below plan floor) → rendered on the device card (§4.2); the dropdown pre-disables below-floor values but the server remains the source of truth (004 §3.4's rule).
- `INVITE_INVALID` / `INVITE_ALREADY_USED` / `410 INVITE_EXPIRED` on accept → inline panel (§5.2).
- Load failures that are *not* the two routed 404s keep the existing `FindlyErrorState`/`ErrorStateView` retry rendering — including on the map (the sheet shows the error state; the map surface stays).

## 10. Test checklist (conforming implementations — pure logic, no platform framework in unit tests)

- **Launch resolution:** each row of the §1.1 table; inconclusive probe fails open to the map; confirmed `PROFILE_NOT_FOUND` → Onboarding(profile-less); confirmed `FAMILY_NOT_FOUND` → Onboarding(family-less); device registration attempted only after a confirmed profile, and re-triggered after each of the four bootstrap successes.
- **Routing rule:** for every feature screen's load path, `PROFILE_NOT_FOUND` produces a route-to-onboarding outcome, not an error state (table-driven over the state holders / view models); mutation-path errors still render inline.
- **Camera policy (both platforms, identical pure tests):** 0/1/2+ point targets per the §3.4 table; padding is expressed density-aware; policy re-runs only on first-load, fit-all action, and selection — a refresh with changed points yields *no* camera command; selecting a member targets the freshest located device at `SINGLE_POINT_ZOOM`; selecting a member with no located device yields no camera command.
- **Freshest-device resolution:** newest `recordedAt` among located devices wins; devices without a fix are never chosen.
- **Relative-time formatter:** thresholds ("just now" / minutes / hours / date), stability against clock skew (never negative ages).
- **Sheet/detents:** detent changes never re-create view models (regression-tested where a harness exists — Android state-holder identity test; iOS per the I16/I18 status).
- **Invite code formatter:** uppercasing, hyphen/space stripping, display-form rendering, charset whitelist, 8-char cap; link-paste extraction reuses 007 parsing (tested there).
- **Share/copy:** `Copy code` copies the display-form code exactly; share text equals the 007 §4 template byte-for-byte (snapshot test against a fixed code + host).
- **Dropdown:** presents exactly the 001 §1.4 set; selection commits one `PATCH` with the chosen value; below-floor values disabled from `features.limits.minSyncIntervalMinutes`.
- **Drawer:** parent-gating of "Invite someone"; item list/order; selection pushes (never replaces the map root).
- Rename-row alignment and full-bleed layout are **review-gate items** (visual, per the design-seam convention), not unit tests; the Android `Column`-starvation bug's fix is pinned by a structure test where feasible (the `MainActivityInsetsStructureTest` precedent).

## Open questions

None — deferred matters are listed in §8 and tracked as 000 §O20 / D18.
