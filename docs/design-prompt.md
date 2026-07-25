# Design-generation prompt — Findly (iOS + Android)

> **How to use this file.** Paste everything under the `--- PROMPT START ---` line into your design tool (Claude, a design-generation model, or a designer brief). It produces **one** cohesive visual design, expressed as concrete values for the **exact design-token contract** both apps already ship. The output drops into each app's swappable `DesignSystem` layer with **zero logic changes** — that layer is the only place styling lives (Android: `mobile/android/app/.../ui/designsystem/`; iOS: `mobile/ios/FindlyKit/Sources/FindlyKit/DesignSystem/`).
>
> The two apps currently ship *placeholder* token values that even diverge slightly between platforms (e.g. Android `primary #2962FF` vs iOS `#2F6FED`). The whole point of this pass is to replace them with **one** designed, unified set. Token **names** are already identical across platforms and MUST NOT change (renaming needs a spec PR to `specs/003-android-client.md` §4.1 and `specs/004-ios-client.md` §2.1).

--- PROMPT START ---

You are a senior product designer. Design the complete visual system for **Findly**, a private family location-tracking app, and return it as concrete values for a fixed design-token contract plus component and screen guidance. The design must work **natively on both iOS (SwiftUI) and Android (Jetpack Compose / Material 3)** from a single shared token vocabulary.

## 1. Product & audience

Findly is a **private, family-only** location app: parents and their kids (and partners) see each other on a live map, get geofence arrival/departure alerts (e.g. "Noor arrived at Home"), can request an on-demand "locate now", and browse location history. It is explicitly **not** a surveillance product and not social — there is one small trusted circle, no feed, no ads, no strangers.

**Emotional tone: calm, warm, trustworthy, reassuring.** It should feel like a caring family utility, not a tracking dashboard or a security console. Avoid alarm-red-heavy, "command center", or spy aesthetics. Think approachable, legible-at-a-glance, and quietly premium. Kids may use it too, so it should be friendly without being childish.

**Cost/brand note:** this is an indie, few-euros-a-month project with **no established brand palette** — you have creative latitude to propose the brand color. Propose one primary brand hue with a rationale (calm/trust-forward — blues, teals, and warm greens all fit; avoid pure red as primary since red is reserved for danger/errors).

## 2. Hard constraints

- **Accessibility (non-negotiable):** every foreground/background token pairing that renders text or essential icons MUST meet **WCAG 2.1 AA** — 4.5:1 for body text, 3:1 for large text (≥24px/≥19px-bold) and UI/graphical objects. This is a safety app used **outdoors in bright sunlight** (finding a child), so favor high contrast and avoid low-contrast greys for anything meaningful. State the computed contrast ratio for each `on*`/background pairing you produce.
- **Light AND dark themes**, both first-class and both shipping day one. Provide a full value set for each.
- **Colorblind-safe status:** device/location status (online / stale / paused / danger) MUST be distinguishable without relying on hue alone — pair color with shape/label/icon in the guidance.
- **Native platform feel from shared tokens:** the semantic tokens are shared, but respect each platform's conventions in the *component* guidance — Material 3 elevation/ripple/rounded shapes on Android; iOS HIG spacing, SF Symbols, and depth-via-subtle-shadow on iOS. Type maps to Roboto/system on Android and SF Pro/system on iOS (don't specify a custom bundled font — use each platform's system font).
- **Touch targets ≥ 44×44 pt/dp.** Map markers and the "locate now" action must be easily tappable one-handed, possibly in a hurry.
- **Map-first:** the live map is the home surface. Map markers/pins, the "stale location" treatment, and geofence circles must be legible over real map tiles (both light and dark map styles).

## 3. The token contract you are filling in (fixed names — output values only)

Produce a value for **every** token below, for **both** light and dark, as **one** unified set used by both platforms (the code already exposes these identical names on each side).

**Colors** (11 semantic roles; hex): `primary`, `onPrimary`, `secondary`, `surface`, `onSurface`, `surfaceVariant`, `danger`, `onDanger`, `success`, `warning`, `outline`.
- Semantics: `primary` = brand / main actions & selected states; `onPrimary` = content on primary. `secondary` = accent / secondary actions. `surface` = default background; `onSurface` = default text/icons; `surfaceVariant` = cards/rows/wells raised off the surface. `danger`/`onDanger` = destructive & error. `success` = arrivals / healthy / online. `warning` = stale / attention (not error). `outline` = borders, dividers, unselected strokes.
- Give a contrast ratio for `onPrimary`/`primary`, `onSurface`/`surface`, `onSurface`/`surfaceVariant`, `onDanger`/`danger`, and `success`/`warning`/`danger` text-on-`surface`.

**Typography** (6 roles — sizes in pt for iOS; Android uses the same numbers in sp): `displayLarge`, `titleLarge`, `titleMedium`, `bodyLarge`, `bodyMedium`, `labelSmall`. For each give size, weight, and line-height. Use the platform **system** font. (Current placeholders: display ~34–36 / titleLarge 22 / titleMedium 16–17 / bodyLarge 16–17 / bodyMedium 14–15 / labelSmall 11–12 — unify these.)

**Spacing** scale (6 steps, pt/dp): `xs, sm, md, lg, xl, xxl` (note: the iOS/Android property is `xxl`; it is the same semantic token the design may call `2xl`). Provide one unified numeric scale.

**Corner radius** (4 steps, pt/dp): `sm, md, lg, pill` (`pill` = fully rounded).

**Elevation** (4 levels): `level0`–`level3`. On Android these are dp elevations (Material). On iOS there is no native elevation, so **also** express each level as a shadow spec `{ blur radius, y-offset, opacity }` (current iOS placeholders: level0 none, level1 {2,1,0.08}, level2 {4,2,0.12}, level3 {8,4,0.16}). Keep them consistent so a card looks the same on both platforms.

## 4. Components to style (already exist as stateless, token-only widgets)

Give visual guidance (fills, text roles, radius, elevation, states: default/pressed/disabled/focused) for each, in terms of the tokens above:

- **Button** (`FindlyButton`) — primary and secondary variants.
- **Card** (`FindlyCard`) — the standard raised container.
- **List row** (`FindlyListRow`) — a member/device/history/geofence row.
- **Status chip** (`FindlyStatusChip` / `StatusChip`) — states: **online**, **stale**, **paused**, **danger** (colorblind-safe: color + icon/shape + label).
- **Map marker bubble** (`FindlyMapMarkerBubble` / `MapMarkerBubble`) — a member's avatar/initial + status ring over map tiles; must read on light and dark maps; include the "stale" and "no location yet" treatments.
- **Top/nav bar** (`FindlyTopBar` / `FindlyNavBar`).
- **Empty / loading / error states** (`FindlyEmptyState`/`EmptyStateView`, `FindlyLoadingState`/`LoadingStateView`, `FindlyErrorState`/`ErrorStateView`) — friendly, reassuring copy tone; error state shows a friendly message (never raw server text).
- **Text field** (`FindlyTextField`) — labeled single-line input (geofence name/icon, invite code, display name).
- **Toggle row** (`FindlySwitchRow` / `FindlyToggleRow`) — label + optional subtitle + trailing switch (device pause / tracking, geofence notify-on-enter/exit).
- **Section header** (`FindlySectionHeader`, Android) — a titled group label.

## 5. Screens to design (layout + hierarchy, composed from the components above)

For each, describe layout, hierarchy, key states, and any screen-specific visual treatment. All are driven by view models that expose plain state — you are styling only.

1. **Sign-in / onboarding** — email/password + Google sign-in; calm first-run; staged location-permission explainer (Android: fine→background; iOS: When-In-Use→Always upgrade rationale).
2. **Live map (home)** — full-bleed map with member marker bubbles; a bottom sheet / card list of members & devices with status chips (online/stale/paused) and last-seen; a prominent "locate now" affordance. Must handle "device has no location yet" and "member has no devices".
3. **History** — a member/device picker + a date-range control + a scrollable, paginated list (and/or a map trail) of past points; empty state for no history.
4. **Geofences** — a list of zones (name, icon, radius) + an editor (name, icon, radius slider, notify-on-enter/exit toggles) shown over a small map preview with the circle; a save-conflict ("someone else changed the zones — refresh") treatment.
5. **Locate-to-request** — a "locate now" flow: instant last-known shown immediately, then a live "updating…" state polling until fulfilled / timed-out; clear terminal states (got a fresh fix / couldn't reach the device → last-known).
6. **Device & family settings** — device list with per-device sync-interval and pause/tracking toggles (parent-editable; owners can only update their own push token); member management (roles, remove, "step down" / "leave family"); friendly guardrails for the last-parent case.
7. **Invites** — create an invite (parent) with a shareable code + a native share affordance; accept an invite (paste/deep-link a code, enter display name, join).

## 6. What to return (output format)

1. **Palette rationale** (2–4 sentences): the brand hue and the mood.
2. **Two token tables** (Light, Dark) covering **all 11 colors**, with a contrast-ratio column for the key pairings in §3.
3. **Typography, spacing, corner, elevation** tables (unified values; elevation with both the Android dp and the iOS shadow-spec form).
4. **Per-component** styling notes (§4) in token terms.
5. **Per-screen** layout notes (§5).
6. **Two platform notes** — one paragraph each on how to keep the shared tokens feeling native on Android (Material 3) vs iOS (HIG).
7. Optionally, a ready-to-paste block per platform: Kotlin `LightFindlyColors`/`DarkFindlyColors` values and Swift `ColorTokens.light`/`.dark` values, using the exact token names above.

Keep every value concrete (hex, numbers) — no "TBD". Prefer a restrained, cohesive palette (one brand hue + one accent + functional success/warning/danger + neutrals) over a rainbow. Optimize for glanceable clarity outdoors and a calm, trustworthy family feel.

--- PROMPT END ---

## Applying the result

- Drop the generated color values into **Android** `ui/designsystem/token/` (`LightFindlyColors`, `DarkFindlyColors`, and the typography/spacing/corner/elevation singletons) and **iOS** `DesignSystem/Tokens/` (`ColorTokens.light`/`.dark`, `TypographyTokens.standard`, etc.). Nothing outside `DesignSystem/` should need to change — that is the design-swappable seam both apps were built around (specs/003 §4, specs/004 §2).
- Re-run each app's design-seam grep to confirm no screen introduced a hardcoded value: Android `grep -rn "Color(" app/src/main/.../ui | grep -v designsystem`; iOS `grep -rn "Color(\|\.font(\.system" FindlyKit/Sources | grep -v DesignSystem`.
- The Android `ComponentGalleryPreview.kt` (and iOS component `#Preview`s, once a full Xcode toolchain is present) render every component in light+dark — use them as the visual regression check after swapping tokens.
