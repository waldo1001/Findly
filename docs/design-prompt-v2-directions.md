# Design-generation prompt v2 — four competing directions (iOS + Android)

> **Why this exists.** `docs/design-prompt.md` (v1) asked for **one** cohesive system and got one: the calm teal `#00696E` set now shipping in `design/findly-design-system/` and applied in both apps. It is correct, accessible, and safe — and safe is exactly the complaint. v2 asks for **four visibly different directions to choose from**, judged on the same three hero screens, all still filling the identical token contract so the winner drops into the `DesignSystem/` seam with zero logic changes.
>
> **How to use.** Paste everything between the PROMPT markers into claude.ai/design (or any design-generation model). Then pick a direction; only then do the token swap (see "Applying the result" in `docs/design-prompt.md`).
>
> **One honest caveat before you paste.** Roughly 80% of what makes an app feel *appealing* — map style, motion, avatars, illustration, sheet choreography, the marker's shape — is **not** reachable by re-valuing the current 11 colors + 6 type roles + spacing/radius/elevation. The prompt therefore asks for each direction to be split into "fits the existing contract" vs. "needs new tokens/assets". The second bucket is real work: a spec PR to `specs/003-android-client.md` §4.1 and `specs/004-ios-client.md` §2.1 first, then code. Budget for it, or accept that a pure token swap will move the needle less than you want.

--- PROMPT START ---

You are a senior product designer. Produce **four distinct, fully-specified visual directions** for **Findly**, a private family location-tracking app for iOS (SwiftUI) and Android (Jetpack Compose / Material 3), so the client can pick one. Do not merge them into a compromise and do not declare one "the" design until the final recommendation section.

## 1. Product

Findly is a **private, family-only** location app: parents, partners and kids see each other on a live map, get geofence arrival/departure alerts ("Noor arrived at Home"), can trigger an on-demand "locate now", and browse location history. One small trusted circle — no feed, no ads, no strangers, no surveillance framing. Kids use it too. Indie project, no established brand, no licensed assets, no bundled custom fonts.

## 2. The brief: this needs to be *appealing*, not merely correct

A previous pass produced a competent, calm, accessible system built on teal `#00696E` with white-ish surfaces, 8/12/20 radii and flat Material-default components. It reads generic — like a settings screen with a map in it. **Do not reproduce it.** Every direction must be immediately distinguishable from that description, and from the other three, at thumbnail size.

Aim for: a design someone would screenshot. Confident color, real hierarchy, one memorable signature move per direction (a marker anatomy, a sheet treatment, a type moment, a status language). Still warm and trustworthy — a caring family utility, never a security console or a spy dashboard.

## 3. Make the four directions genuinely different

Each direction must differ from the others on **at least three** of these axes — state which axes it moves on:

- **Hue family & saturation** — cool/technical, warm/human, botanical, dusk/neon, near-monochrome + one accent, etc. (Red stays reserved for danger; don't use it as a brand hue.)
- **Surface strategy** — airy near-white and borderless; layered cards with real depth; dark-first/map-first with light chrome floating over tiles; tinted/duotone surfaces.
- **Type personality** — restrained system-neutral; large expressive display moments; tight editorial; heavier weights and tighter tracking. (System fonts only — SF Pro / Roboto — so personality comes from size, weight, tracking, and case, not from a typeface purchase.)
- **Shape language** — soft superellipse/pill-heavy; tight geometric small radii; mixed (pill actions + square-ish cards).
- **Map & marker anatomy** — the signature surface. Custom light and dark map style direction (land/water/road/label tinting), marker bubble shape, status ring, the "stale" and "no location yet" treatments, geofence circle fill/stroke.
- **Density & rhythm** — glanceable and spacious vs. information-dense.

Give each direction a **short evocative name** and a one-line pitch ("Dusk — dark-first, the map is the product; chrome floats").

## 4. Hard constraints — every direction, no exceptions

- **Same token contract, fixed names, values only.** Both platforms already expose these identical names; renaming any of them is out of scope.
  - **Colors (11 roles, hex, light + dark):** `primary`, `onPrimary`, `secondary`, `surface`, `onSurface`, `surfaceVariant`, `danger`, `onDanger`, `success`, `warning`, `outline`. Semantics: `primary` = brand / main actions / selected; `onPrimary` = content on primary; `secondary` = accent; `surface` = default background; `onSurface` = default text & icons; `surfaceVariant` = cards/rows/wells; `danger`/`onDanger` = destructive & error; `success` = arrival / healthy / online; `warning` = stale / attention (not error); `outline` = borders, dividers, unselected strokes.
  - **Typography (6 roles; pt on iOS = sp on Android):** `displayLarge`, `titleLarge`, `titleMedium`, `bodyLarge`, `bodyMedium`, `labelSmall` — size, weight, line-height, tracking each.
  - **Spacing (6 steps, pt/dp):** `xs, sm, md, lg, xl, xxl`.
  - **Corner radius (4 steps):** `sm, md, lg, pill` (`pill` = fully rounded).
  - **Elevation (4 levels):** `level0`–`level3`, expressed **both** as Android Material dp **and** as an iOS shadow spec `{blur, y-offset, opacity, color}`, kept visually equivalent.
- **Accessibility, non-negotiable.** WCAG 2.1 AA for every pairing carrying text or essential icons: 4.5:1 body, 3:1 large text (≥24pt, or ≥19pt bold) and UI/graphical objects. This app gets used **outdoors in bright sun while looking for a child** — bias high-contrast; no low-contrast grey for anything meaningful. **State the computed ratio** for `onPrimary`/`primary`, `onSurface`/`surface`, `onSurface`/`surfaceVariant`, `onDanger`/`danger`, and `success`/`warning`/`danger` as text on `surface`, in both themes. A direction that misses AA is disqualified — fix the value, don't waive the rule.
- **Light and dark both first-class**, both shipping day one, full value set for each.
- **Colorblind-safe status.** online / stale / paused / danger must be separable without hue: color **plus** distinct glyph or shape **plus** text label.
- **Touch targets ≥ 44×44 pt/dp**, one-handed, in a hurry. The map marker and "locate now" especially.
- **Legible over real map tiles**, light and dark.
- **Native, not cross-platform mush.** Shared semantic tokens, but per-platform component guidance: Material 3 elevation/ripple/shape families/M3 switch+slider anatomy on Android; HIG spacing, SF Symbols, grouped-inset lists, native detent sheets, dim-not-ripple presses on iOS.
- **No bundled custom font, no licensed imagery.** Any illustration must be describable as simple vector shapes built from the palette.

## 5. Split each direction into two buckets

- **A. Token-only** — everything achievable purely by re-valuing the tokens in §4. This is free to ship.
- **B. Beyond the contract** — the things that would actually make it sing but need new tokens, new components, assets, or motion work: gradient/duotone tokens, a map style JSON, avatar treatment, custom marker artwork, illustration set, blur/material backdrops, motion specs, haptics. **List each item with a one-line cost note** ("new `gradientPrimary` token pair + Compose Brush + SwiftUI LinearGradient — ~half a day, needs a token-contract spec change"). Be honest about which of your direction's appeal lives in bucket B — if a direction is 70% bucket B, say so.

## 6. Show, don't just tabulate — the comparison is the deliverable

For **each** of the four directions, render the **same three hero screens**, in **both light and dark**, at phone size, so they can be compared like-for-like:

1. **Live map (home)** — full-bleed map with member marker bubbles, a bottom sheet listing members/devices with status chips (online / stale / paused) and last-seen, and a prominent "Locate now". Include the awkward states: a device with no location yet, and a member with no devices.
2. **Family & devices (list-heavy)** — grouped rows: per-device sync interval, pause/tracking toggles, member roles, remove / leave-family. This is where a pretty palette usually falls apart — prove it doesn't.
3. **Locate-now in flight (the emotive one)** — last-known shown instantly with its age, then a live "updating…" state, then both terminal states: fresh fix (good news) and "couldn't reach the device — showing last known" (reassuring, never scary).

Then, per direction, a **component specimen sheet** in that direction's tokens, all states (default / pressed / disabled / focused / error):
`FindlyButton` (primary + secondary) · `FindlyCard` · `FindlyListRow` · `StatusChip` (online/stale/paused/danger) · `MapMarkerBubble` (normal / stale / no-location-yet) · `FindlyTopBar`/`NavBar` · `FindlyTextField` · `FindlySwitchRow`/`ToggleRow` · `FindlySectionHeader` · `EmptyState` / `LoadingState` / `ErrorState` (friendly copy tone — an error never shows raw server text).

Group the output so each direction is browsable on its own, and add one **side-by-side board** placing all four Live-map-dark thumbnails together for the pick.

## 7. Remaining screens — cover once, at the winner level of detail

Layout and hierarchy notes only (not four times over — do these for the direction you recommend, and note where another direction would diverge): sign-in / onboarding with the staged location-permission explainer (Android fine→background; iOS When-In-Use→Always); history (member/device picker, date range, paginated list and/or map trail, empty state); geofences (zone list + editor over a map preview with the live circle, radius slider, notify-on-enter/exit, save-conflict refresh banner); invites (create a shareable code + native share; accept via paste/deep-link, display name, join; friendly invalid/expired guidance).

## 8. Output format

1. **Comparison table** — four rows: name, one-line pitch, brand hex (light/dark), axes it moves on, best-for / worst-for, share of appeal in bucket B.
2. **Per direction:** palette rationale (2–4 sentences) → light + dark token tables (all 11 colors, contrast column) → type/spacing/radius/elevation tables → component notes → the three hero screens (light + dark) → bucket A / bucket B split.
3. **The side-by-side board.**
4. **Your recommendation** — one direction, with the actual reason, plus the single best idea worth stealing from each of the other three.
5. **Ready-to-paste code, all four:** Kotlin `LightFindlyColors` / `DarkFindlyColors` and Swift `ColorTokens.light` / `.dark`, using the exact token names above, so any direction can be tried in minutes.

Every value concrete — hex and numbers, no "TBD", no "designer's choice". Restraint within each direction (one brand hue + one accent + functional success/warning/danger + neutrals); boldness *between* directions.

--- PROMPT END ---

## After you pick

1. Drop the winning values into Android `mobile/android/app/src/main/java/com/findly/android/ui/designsystem/token/` and iOS `mobile/ios/FindlyKit/Sources/FindlyKit/DesignSystem/Tokens/`.
2. Re-run the design-seam greps — nothing outside the seam may hardcode a value:
   - Android: `grep -rn "Color(" mobile/android/app/src/main/java/com/findly/android/ui | grep -v designsystem`
   - iOS: `grep -rn "Color(\|\.font(\.system" mobile/ios/FindlyKit/Sources | grep -v DesignSystem`
3. Render `ComponentGalleryPreview.kt` and the iOS `#Preview`s in light + dark as the visual regression check.
4. Anything from bucket B gets a spec PR first (`specs/003` §4.1, `specs/004` §2.1), then code, then the normal review gate.
