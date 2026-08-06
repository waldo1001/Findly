# Handoff: Findly — direction 2a ("Ember / Dusk")

## Overview

Findly is a private, family-only location app for iOS (SwiftUI) and Android (Jetpack Compose / Material 3). Four visual directions were explored; the client picked **2a**: the *Ember* layout, type, shape and rhythm repainted in the *Dusk* indigo/cyan palette.

This handoff covers the full screen set in 2a: live map (expanded and minimized sheet), family & devices, locate-now in four states, sign-in, staged location permissions, history, places (geofences) list and editor, invite create and accept, plus a component specimen sheet with all states.

Nothing here requires renaming a token. The design fills the existing contract — 11 colour roles, 6 type roles, 6 spacing steps, 4 radii, 4 elevation levels — with new values.

## About the design files

`Findly Directions.dc.html` in this bundle is a **design reference created in HTML**: a prototype showing intended look and behaviour, not production code to copy. The task is to recreate these designs in the existing Findly apps using their established patterns — SwiftUI + FindlyKit on iOS, Compose + Material 3 on Android. Do not port HTML or CSS.

The file is a browsable board. Turn 3 (top) is the full 2a screen set. Turn 2 is 2a's live map in light and dark plus its token tables and ready-to-paste code. Turn 1 is the four original directions, kept for reference only — **ignore 1a–1d when implementing**.

## Fidelity

**High-fidelity.** Colours, type sizes and weights, spacing, radii and copy are final and exact. Recreate them faithfully using each platform's native components. Two exceptions, both marked in the design:

- The map surfaces are abstract vector stand-ins. They communicate the intended *tint* of the basemap, not a real style. A basemap style JSON is a separate deliverable (see Bucket B).
- The two permission screens contain striped placeholder blocks labelled `phone + map illustration` and `closed phone + house shapes`. No artwork exists yet. Ship with the placeholder empty area or simple vector shapes from the palette until art lands.

---

## Design tokens

### Colours — light

| Role | Hex | Contrast |
|---|---|---|
| `primary` | `#3A46C8` | `onPrimary` on it: 7.3:1 |
| `onPrimary` | `#FFFFFF` | — |
| `secondary` | `#0E7C8F` | on `surface`: 4.6:1 |
| `surface` | `#F2F4FB` | — |
| `onSurface` | `#10142A` | on `surface` 16.4:1 · on `surfaceVariant` 14.2:1 |
| `surfaceVariant` | `#E2E6F5` | — |
| `danger` | `#B3261E` | `onDanger` 5.8:1 · as text on `surface` 5.7:1 |
| `onDanger` | `#FFFFFF` | — |
| `success` | `#10714A` | as text on `surface` 6.0:1 |
| `warning` | `#8A5A00` | as text on `surface` 5.4:1 |
| `outline` | `#A9B0CE` | 2.1:1 vs surface — **hairlines only** |

### Colours — dark

| Role | Hex | Contrast |
|---|---|---|
| `primary` | `#7C8BFF` | `onPrimary` on it: 7.9:1 |
| `onPrimary` | `#0A0F27` | — |
| `secondary` | `#4FE3D0` | on `surface` 12.4:1 |
| `surface` | `#0B0F1C` | — |
| `onSurface` | `#E8ECF7` | on `surface` 16.2:1 · on `surfaceVariant` 13.0:1 |
| `surfaceVariant` | `#161D33` | — |
| `danger` | `#FF6B6B` | `onDanger` 6.4:1 · as text on `surface` 6.4:1 |
| `onDanger` | `#2A0708` | — |
| `success` | `#52E39B` | as text on `surface` 11.9:1 |
| `warning` | `#FFC44D` | as text on `surface` 11.6:1 |
| `outline` | `#3A4463` | 3.1:1 vs surface |

Two rules that must survive review:

1. `outline` in **light** is 2.1:1 and is legal only for decorative hairlines and dividers. Any stroke that carries meaning (an unselected control border, a focus ring, an input outline) steps to `#6B739A` (3.4:1). In dark, `outline` itself clears 3:1 and may be used for both.
2. The green dot used inside a `primary` marker bubble is `#52E39B` in **both** themes (5.4:1 on `#3A46C8`). Do not use light-theme `success` `#10714A` there — it measures 1.2:1 and disappears.

### Typography (pt on iOS = sp on Android, system fonts only)

| Role | Size / weight | Line height | Tracking |
|---|---|---|---|
| `displayLarge` | 34 / 700 | 40 | −0.4 |
| `titleLarge` | 24 / 700 | 30 | −0.2 |
| `titleMedium` | 18 / 600 | 24 | 0 |
| `bodyLarge` | 17 / 400 | 24 | 0 |
| `bodyMedium` | 15 / 400 | 20 | 0 |
| `labelSmall` | 12 / 700, uppercase | 16 | +0.4 |

Any elapsed-time or code value is set with tabular figures: `.monospacedDigit()` on iOS, `fontFeatureSettings = "tnum"` on Android.

### Spacing, radius, elevation

- Spacing: `xs 4 · sm 8 · md 12 · lg 20 · xl 28 · xxl 40`
- Radius: `sm 12 · md 20 · lg 28 · pill 999`
- Elevation (Android dp / iOS `{blur, y, opacity light|dark, colour}`):
  - `level0` — 0dp / none
  - `level1` — 1dp / blur 8, y 2, 10% | 30%, `#000000`
  - `level2` — 3dp / blur 24, y 8, 14% | 45%, `#000000`
  - `level3` — 8dp / blur 48, y 16, 18% | 60%, `#000000`

Shadows are neutral black in both themes. Do not tint them.

---

## Components

All eleven contract components, with every state shown on the specimen sheet (3d in the HTML).

### FindlyButton — primary
Height 52 (48 when inline in a header row), radius `pill`, fill `primary`, label `onPrimary` at 16/600, `level2` shadow tinted `rgba(58,70,200,.35)` on light. Pressed: fill `#2C36A0` (iOS dims to 0.85 instead). Disabled: fill `surfaceVariant`, label `#8D93AB`, no shadow. Focused: 3px `surface` ring then 3px `rgba(58,70,200,.55)`.

### FindlyButton — secondary
Same geometry, transparent fill, 1.5px `outline` border, label `onSurface`. Pressed fills `surfaceVariant`. Destructive variant swaps border and label to `danger`; never a filled red button.

### FindlyCard
Radius `md` (20), fill `surfaceVariant`, no border, no shadow. Cards are containers for rows; rows inside are divided by a 1px `outline` line, not by gaps.

### FindlyListRow
Min height 60, padding 12/14, 12pt gap. Leading 40×40 avatar (circle, `primary` fill for self, `surfaceVariant` otherwise, initial at 15/700). Title 16/600, subtitle 13/400 in `onSurface` at 70% (use `#4E5675` light, `#98A1BD` dark). Optional trailing metadata, chip or 18pt chevron in `outline`. Pressed: light `#D8DDF0` overlay on iOS, standard ripple on Android. Disabled: 45% opacity.

### StatusChip
Height 24, radius `pill`, padding 0/9, label 10.5/700 with +0.3 tracking, always **glyph + word**:
- online — fill `success`, `onDanger`-white text, `● ONLINE`
- stale — fill `warning`, white text, `▲ STALE`
- paused — transparent, 1.5px `outline`, `onSurface` text, `▮▮ PAUSED`
- danger — fill `danger`, `onDanger` text, `✕ ALERT`

Status is never colour alone. Greyscale must remain readable.

### MapMarkerBubble
Pill, height 44 (a valid touch target on its own), padding 0/12/0/6, 8pt gap.
- **Normal**: `primary` fill, 32pt circular avatar in `onPrimary`, name 13/600, trailing `● NOW` pill (height 18, fill `#52E39B`, text `#062418` at 9/800). `level3` shadow. 7pt triangular tail below in `primary`.
- **Stale**: `surface` fill, 2px dashed `warning` border, name in `onSurface`, trailing `▲ 24m` in `warning` at 10/700, tail in `surface`.
- **No location yet**: 52pt circle, `surfaceVariant` fill, 2px dashed `outline`, `?` glyph. Not placed on the map — shown as the row's leading element only when a device has never checked in.
- Geofence circle: 2px `primary` stroke, `rgba(58,70,200,.10)` fill.

### FindlyTopBar / NavBar
Height 52 under the status bar. 44×44 back target with a 22pt chevron in `primary`, title 18/600 at −0.2 tracking, trailing text action 15/600 in `primary`.

### FindlyTextField
Height 52, radius `md` (16 in the mocks), fill `surfaceVariant`, 1.5px `outline` border, text 16/400, placeholder in muted. Focused: border `primary` plus a 3px `rgba(58,70,200,.18)` ring. Error: border `danger`, message below at 13/400 in `danger` prefixed `✕`. Disabled: fill `#E8EAF2`, border `#D3D7E6`, text `#8D93AB`.

### FindlySwitchRow
Min height 56, label 16/600, trailing platform switch. **Use the native M3 switch on Android and the native UISwitch/Toggle on iOS** — the mock draws a 52×32 track with a 26pt thumb only to show the on/off colours: on = `primary` track, off = `outline` track, white thumb.

### FindlySectionHeader
`labelSmall`, uppercase, muted, 4pt horizontal padding, 10pt below the previous block.

### EmptyState / LoadingState / ErrorState
Radius `lg`, fill `surfaceVariant`, padding 22. Title 18/600, body 15/400 at 1.5 line height in muted, single action. Loading shows a 6pt determinate or indeterminate bar in `primary` on a `surface` track. Error leads with a `▲` in `warning` (not red — an unreachable device is not an error state for the user), names the device, explains in plain words, offers the next action. **Raw server text never reaches the screen.**

---

## Screens

Copy is final. Use it verbatim.

### 1. Live map (home)
Full-bleed map. Floating top chrome at y=62: a `pill` bar (height 48, `surface` fill, `level2` shadow) with a 22pt `primary` dot, "The Haddads" at 15/600, and "4 members" right-aligned at 11/400 muted; plus a 48pt circular settings button.

Bottom sheet, three detents:
- **Minimized (186pt)** — grabber, "Family" at 22/700, "3 of 4 sharing · updated just now" at 12/400 muted, `Locate now` button, then an overlapped avatar stack (36pt circles, −12 overlap, 2pt `surface` ring) and "Drag up for details".
- **Standard (440pt)** — grabber, header row ("Family" + "Updated just now" + `Locate now`), then the member list: five `FindlyCard` rows at 9/12 padding with 8pt gaps.
- **Expanded (large)** — same list, scrollable.

Member rows, in order: Noor · "Home · just now" · online chip; Sam · "Oak Street · 24 min ago" · stale chip; Dad · "Sharing paused by Dad" · paused chip; **Lina's iPad** · "No location yet — waiting for first check-in" · dashed-border card, no chip; **Ivy** · "No devices added" · transparent card with `outline` border and an `Invite` pill.

Markers: Noor normal at the geofence circle, Sam stale, and a paused marker (52pt `surfaceVariant` circle, `▮▮`).

### 2. Family & devices
Nav bar "Family & devices" / "Edit". Sections:
- **Members** — four rows, each with role trailing ("You · Parent", "Parent", "Parent", "Child") and a chevron.
- **Devices** — three switch rows: "Noor's iPhone / Syncing every 5 min · battery 82%" (on), "Sam's Pixel / Syncing every 15 min" (on), "Lina's iPad / No location yet — waiting for first check-in" (off).
- **Sync interval · Sam's Pixel** — four segmented pills (1 min / 5 min / 15 min / 1 hr), selected fills `primary`.
- Destructive card — "Remove Lina's iPad" and "Leave family", both `danger` text on `surfaceVariant`, 52pt min height, each behind a confirmation.

### 3. Locate now — four states
Map plus a bottom card (radius `lg` top corners, 10/20/24 padding, grabber).

1. **Last known** — eyebrow `▲ LAST KNOWN LOCATION` in `warning`, "24 min ago" at 34/700, "Sam · Oak Street, near the library" at 16/400 muted, `Locate now`. Marker stale with a dashed `warning` accuracy circle.
2. **Updating** — eyebrow `◎ UPDATING` in `primary`, "Asking Sam's Pixel…", "Still showing the last known spot from 24 min ago", a 6pt progress bar, `Cancel`. Marker gets two concentric `primary` rings (the pulse).
3. **Fresh fix** — eyebrow `● UPDATED JUST NOW` in `success`, "Sam is at the library", "Oak Street · accurate to about 12 m", `Directions` + `Done` side by side. Marker switches to the normal `primary` bubble with the `● NOW` pill.
4. **Couldn't reach** — a `surfaceVariant` panel: `▲` in `warning`, "We couldn't reach Sam's Pixel", "It may be off or out of signal. You're seeing the last place it checked in from, 24 minutes ago.", then `Try again` and `Tell me when it checks in`. Never red, never an alert dialog.

State machine: `lastKnown → updating → (fresh | unreachable)`. `updating` times out to `unreachable` after 30s. The map never blanks between states — the last known position stays rendered throughout.

### 4. Sign-in
Logo mark (64pt, radius 22, `primary`), "Everyone home, / on one map" at 34/700, subtitle "Findly is just for your family. No feed, no ads, no strangers — only the people you invite." Email field, `Continue`, `I have an invite code`, and a 12pt muted footnote: "Your location is shared only with your family circle."

### 5. Staged permissions
Two screens with a two-segment progress bar at the top.
- **Stage 1** — "First, location while you're using Findly" / "This is what puts you on the map when you open the app. You can turn it off at any time in Settings." → `Allow while using the app`, `Not now`. iOS When-In-Use; Android `ACCESS_FINE_LOCATION`.
- **Stage 2** — "Then, keep sharing when the app is closed" / "Without this, your family sees you only while Findly is open — and arrival alerts stop working." plus a `surfaceVariant` note: "On the next screen, choose **Always**." → `Continue`, `Keep it to when I'm using the app`. iOS Always upgrade; Android `ACCESS_BACKGROUND_LOCATION`, which must be its own rationale screen. Stage 2 is only ever shown after stage 1 is granted.

### 6. History
Nav "History". Member and device pickers as chips (selected fills `primary`), a three-way segmented range (Today / 7 days / Custom), a 200pt map trail preview — five dots along a path with opacity ramping 0.35 → 1.0 and a 14pt current point with a 3pt `surface` ring, plus a "Trail · 5 points" pill. Then a list: time at 14/700 tabular in a 58pt column, place at 15/600, detail at 13/400 (geofence events use `success` and the `●` glyph). Footer row "Load earlier" in `primary`. Empty state: "No history for this range."

### 7. Places (geofences)
- **List** — zone rows with a 40pt rounded-square `◎` leading tile, name, "Everyone · 150 m · arrive & leave" subtitle, and a switch. Below, a dashed "Add a place" card: "Get a quiet notification when someone arrives at or leaves a place that matters — school, work, a friend's house." + `New place`.
- **Editor** — 300pt map with the live circle (190pt, 2px `primary`, 12% fill), a 22pt centre pin with a 4pt `surface` ring, and a floating hint "Drag the pin to move this place". Below: a save-conflict banner (`▲` + "Dad changed this place a moment ago. **Refresh** before saving."), the Name field, a radius slider (6pt track, `primary` fill, 24pt thumb with a 2px `primary` border) with the value shown in the label row, and two notify switch rows.

### 8. Invites
- **Create** — "Add someone to The Haddads" / "Share this code with them. It works once and expires in 24 hours." Code block: `surfaceVariant`, radius 24, code at 34/700 with 4pt letter-spacing and tabular figures, "Expires 21:14 today". `Share invite` (native share sheet) + `Copy code`. Footnote: "Anyone with this code can see your family's locations, so send it directly to the person joining."
- **Accept** — "You've been invited to The Haddads" / "Noor invited you. Once you join, everyone in the family can see where you are." Prefilled code field (from paste or deep link), display-name field, `Join family` / `Not now`. Invalid or expired shows the inline `▲` panel: "That code has expired. Ask Noor to send a new one — it only takes a moment."

---

## Interactions & behaviour

- Sheet detents: 186pt minimized, 440pt standard, large expanded. Dragging never unmounts the list.
- `Locate now` is the only element that animates on the map: the two-ring pulse runs while `updating`, 2s ease-out, and stops on a terminal state.
- Haptic on fresh fix only: `.success` / `HapticFeedbackConstants.CONFIRM`. Nothing on failure.
- Presses: opacity dim on iOS, ripple on Android. Do not cross-port.
- Sync-interval and range segments commit immediately, no Save.
- Destructive actions confirm; the confirmation names the thing being removed.
- Geofence save conflict: banner appears when the server version differs; Save stays enabled but Refresh is the emphasised path.

## State

`familyMembers[]` (id, name, role, isSelf), `devices[]` (id, memberId, name, syncIntervalMin, trackingEnabled, lastFixAt, lastPlace, battery), `locateRequest` (`idle | updating | fresh | unreachable`, targetDeviceId, startedAt), `sheetDetent`, `geofences[]` (id, name, centre, radiusM, notifyEnter, notifyExit, enabled, version), `historyQuery` (memberId, deviceId, range), `invite` (code, expiresAt).

`lastFixAt` drives the online / stale threshold — online under 5 min, stale beyond. Ages recompute on a 30s ticker, not per frame.

## Bucket A vs bucket B

**Bucket A — ships as a token swap, no spec change:** every colour, type, spacing, radius and elevation value above; all eleven components; every screen in this document.

**Bucket B — needs new tokens, assets or motion work, each behind a spec PR to `specs/003-android-client.md` §4.1 and `specs/004-ios-client.md` §2.1:**

| Item | Cost |
|---|---|
| Basemap style JSON, light + dark, tinted to `land #E9ECF7 / #0A0D18`, roads to `surface`, water `#CBD8EE / #0B1730`, parks `#DCE7DA / #0E1A22` | ~1.5 days, new asset, no token change |
| Custom marker annotation (pill + tail + status pill) as real map artwork | ~1 day, Compose `Canvas` / MapKit annotation view |
| Avatar treatment (photo in ring, initials fallback) | ~1 day, new `AvatarView` |
| Locate-now pulse animation | ~half a day, motion spec |
| Permission-screen illustrations as palette vector shapes | ~1 day, needs art direction |
| Haptic on fresh fix | ~2 hours |

## Assets

None bundled. No licensed imagery, no custom fonts — SF Pro on iOS, Roboto on Android. Icons are SF Symbols and Material Symbols; the glyphs in the mock (`◎ ▲ ▮▮ ● ✕ ‹ ›`) are stand-ins for `location.circle.fill`, `exclamationmark.triangle.fill`, `pause.fill`, a filled dot, `xmark`, and chevrons.

## Verification before review

1. Drop values into `mobile/android/.../ui/designsystem/token/` and `mobile/ios/FindlyKit/Sources/FindlyKit/DesignSystem/Tokens/`.
2. Re-run the design-seam greps — nothing outside the seam may hardcode a value:
   - `grep -rn "Color(" mobile/android/app/src/main/java/com/findly/android/ui | grep -v designsystem`
   - `grep -rn "Color(hex:\|Color(red:\|Color(\.s\|\.font(\.system" mobile/ios/FindlyKit/Sources | grep -v DesignSystem`
     (**Corrected post-review, 2026-08-06** — the original `"Color(\|..."` pattern matches the
     substring inside SwiftUI's own `.foregroundColor(`/`.backgroundColor(` modifiers, which every
     correctly-token-driven component and screen calls constantly. On this codebase it produced 34
     hits and zero signal. The corrected pattern anchors on the actual literal-construction forms —
     `Color(hex:` is the one this codebase's `ColorTokens.swift` actually defines and uses;
     `Color(red:`/`Color(.s...` cover other common literal forms SwiftUI supports, so the grep
     still catches them if introduced later — and ignores the modifier-name false positive.)
3. Render `ComponentGalleryPreview.kt` and the iOS `#Preview`s in light and dark.
4. Check the two contrast traps: light `outline` used only for hairlines, and `#52E39B` for the dot inside a `primary` marker.

## Files

- `Findly Directions.dc.html` — the design board. Turn 3 = the full 2a screen set; turn 2 = 2a live map, token tables and code; turn 1 = the four explored directions, reference only.
- `tokens/FindlyColors.kt` — ready-to-paste Kotlin.
- `tokens/ColorTokens.swift` — ready-to-paste Swift.
