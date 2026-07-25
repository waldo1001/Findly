# Handoff: Findly — Family Location Design System

## Overview
Findly is a private, family-only location app (live map, geofence arrival/departure alerts, on-demand "locate now", location history). This package delivers the **complete visual system** as concrete values for a fixed, shared design-token contract that renders natively on **iOS (SwiftUI)** and **Android (Jetpack Compose / Material 3)** from one vocabulary. Emotional tone: **calm, warm, trustworthy, reassuring** — a caring family utility, not a surveillance dashboard.

## About the Design Files
The file in this bundle (`Findly Design System.dc.html`) is a **design reference created in HTML** — a living spec that shows the intended palette, type/spacing/elevation scales, component states, and screen layouts. **It is not production code to copy.** Your task is to drop the token *values* below into the two apps' existing `DesignSystem/` seams and let the already-built, token-only components re-skin themselves. Nothing outside `DesignSystem/` should change — that seam is the design-swappable boundary both apps were built around (specs/003 §4, specs/004 §2).

## Fidelity
**High-fidelity.** All colors, type, spacing, radius, elevation, and component states are final and concrete (exact hex/numbers, no TBD). Every token pairing that renders text or essential icons has a **verified WCAG 2.1 AA** contrast ratio (stated below). Implement these values exactly.

---

## How to apply (primary task)
1. **Android** — put the color values into `ui/designsystem/token/` (`LightFindlyColors`, `DarkFindlyColors`) and the typography/spacing/corner/elevation singletons. Use the ready-to-paste `FindlyColors.kt` in this bundle.
2. **iOS** — put the color values into `DesignSystem/Tokens/` (`ColorTokens.light` / `.dark`, `TypographyTokens.standard`, etc.). Use the ready-to-paste `ColorTokens.swift` in this bundle.
3. **Verify no leakage** — re-run each design-seam grep:
   - Android: `grep -rn "Color(" app/src/main/.../ui | grep -v designsystem`
   - iOS: `grep -rn "Color(\|\.font(\.system" FindlyKit/Sources | grep -v DesignSystem`
   Both should return nothing outside `DesignSystem/`.
4. **Visual regression** — render the Android `ComponentGalleryPreview.kt` and iOS component `#Preview`s in light + dark; compare against the component specimens in the HTML reference.

---

## Design Tokens

### Colors — Light (11 roles)
| Token | Hex | Role | Key contrast |
|---|---|---|---|
| primary | `#00696E` | Brand / main actions / selected | onPrimary·primary **6.47:1** ✓ |
| onPrimary | `#FFFFFF` | Content on primary | — |
| secondary | `#4C5FD5` | Accent / secondary actions | on surface **5.14:1** ✓ |
| surface | `#FAFAF7` | Default background | — |
| onSurface | `#1B1D1C` | Default text & icons | on surface **16.2:1** ✓ |
| surfaceVariant | `#EEEEE9` | Cards / rows / wells | onSurface·surfaceVariant **14.6:1** ✓ |
| danger | `#C0362C` | Destructive & error | on surface **5.28:1** ✓ |
| onDanger | `#FFFFFF` | Content on danger | onDanger·danger **5.52:1** ✓ |
| success | `#1E7D46` | Arrivals / healthy / online | on surface **4.93:1** ✓ |
| warning | `#8A5A00` | Stale / attention (not error) | on surface **5.67:1** ✓ |
| outline | `#C9C8C2` | Borders / dividers / strokes | decorative (1.6:1) — never sole carrier of meaning |

### Colors — Dark (11 roles)
| Token | Hex | Role | Key contrast |
|---|---|---|---|
| primary | `#4CD4D9` | Brand / main actions / selected | onPrimary·primary **7.92:1** ✓ |
| onPrimary | `#00312F` | Content on primary | — |
| secondary | `#A9B4FF` | Accent / secondary actions | on surface **9.02:1** ✓ |
| surface | `#17181A` | Default background | — |
| onSurface | `#ECECE6` | Default text & icons | on surface **15.0:1** ✓ |
| surfaceVariant | `#24262A` | Cards / rows / wells | onSurface·surfaceVariant **12.8:1** ✓ |
| danger | `#F2867B` | Destructive & error | on surface **7.17:1** ✓ |
| onDanger | `#490A05` | Content on danger | onDanger·danger **6.37:1** ✓ |
| success | `#5FD08A` | Arrivals / healthy / online | on surface **9.20:1** ✓ |
| warning | `#E4B44C` | Stale / attention (not error) | on surface **9.25:1** ✓ |
| outline | `#3A3D42` | Borders / dividers / strokes | decorative (1.6:1) |

> Contrast ratios computed with the WCAG 2.1 relative-luminance formula. All text/essential-icon pairings meet AA (4.5:1 body, 3:1 large/UI). `outline` is decorative only.

### Typography (6 roles — pt on iOS / sp on Android, same numbers; platform system font: SF Pro / Roboto)
| Token | Size | Weight | Line-height | Tracking | Use |
|---|---|---|---|---|---|
| displayLarge | 34 | Bold (700) | 40 | -0.02em | First-run headlines |
| titleLarge | 22 | Semibold (600) | 28 | -0.01em | Screen & nav titles |
| titleMedium | 17 | Semibold (600) | 22 | 0 | Row & card titles |
| bodyLarge | 17 | Regular (400) | 24 | 0 | Primary reading text |
| bodyMedium | 15 | Regular (400) | 20 | 0 | Secondary / subtitles |
| labelSmall | 12 | Medium (500) | 16 | 0.4px | Chips, captions, overlines |

### Spacing (pt / dp)
`xs 4` · `sm 8` · `md 12` · `lg 16` · `xl 24` · `xxl 32`
(The iOS/Android property name is `xxl`; the design may refer to it as `2xl` — same token.)

### Corner radius (pt / dp)
`sm 8` · `md 12` · `lg 20` · `pill 999` (fully rounded)

### Elevation (Android Material dp + iOS shadow spec `{blur, y-offset, opacity}`)
| Token | Android dp | iOS shadow |
|---|---|---|
| level0 | 0 | none |
| level1 | 1 | `{2, 1, 0.08}` |
| level2 | 3 | `{4, 2, 0.12}` |
| level3 | 6 | `{8, 4, 0.16}` |

Shadow color is a near-black warm neutral (`rgba(20,25,20,·)`). Keep both forms consistent so a card looks identical on both platforms.

---

## Components (token-only, stateless)
All components already exist as stateless widgets — you are re-skinning them via the tokens above.

- **FindlyButton** — Primary: `primary` fill + `onPrimary`, radius `md`, elevation `level1`; pressed darkens fill ~8% (Android adds ripple); disabled = `surfaceVariant` + `onSurface`@38%; focused = 2px `primary` ring. Secondary: transparent fill, 1.5px `primary` border, `primary` label. Min height 48 (≥44 target).
- **FindlyCard** — `surface` fill, radius `lg`, elevation `level2`, hairline `outline` border.
- **FindlyListRow** — 64pt min height, 44pt avatar, leading title `titleMedium`, subtitle `bodyMedium` / `onSurface`@70%, trailing StatusChip; pressed = `surfaceVariant` overlay; dividers `outline`.
- **StatusChip** — radius `pill`, no elevation. **Colorblind-safe: color + distinct glyph + label.** online = `success` + filled dot; stale = `warning` + up-triangle; paused = neutral `outline` + pause-bars; danger = `danger` + diamond. Text label always present.
- **MapMarkerBubble** — 44–48pt bubble, 3px ring in `surface` (reads on light & dark map tiles). Online = solid fill + `success` pointer tail; stale = desaturated + dashed ring; no-location-yet = neutral "?" chip, not falsely placed on the map.
- **FindlyTopBar / NavBar** — `surface`; iOS hairline, Android `level0`→`level2` on scroll. Title `titleLarge`; actions 44pt hit areas.
- **FindlyTextField** — `outline` border at rest → `primary` (1.5px) focused → `danger` on error with helper text. Label `labelSmall`-derived; value `bodyLarge`.
- **FindlySwitchRow / ToggleRow** — label + optional subtitle + trailing switch; ON track = `primary` (iOS pill / Android M3 thumb). Row min 60pt.
- **FindlySectionHeader** (Android) — group caption from `labelSmall`, uppercase, `onSurface`@60%.
- **EmptyState / LoadingState / ErrorState** — friendly, reassuring copy; error shows a friendly message (never raw server text) with a `primary` Retry. Loading = `primary` spinner over `surfaceVariant` icon well.

---

## Screens (layout + key states)
1. **Sign-in / onboarding** — calm centered stack (wordmark, email/password, primary Sign in, bordered Google). Staged permission explainer *before* the OS prompt (Android fine→background; iOS When-In-Use→Always upgrade rationale).
2. **Live map (home)** — full-bleed map; MapMarkerBubbles; draggable bottom sheet of members/devices with StatusChips + last-seen; prominent "Locate now". States: no location yet, no devices, sheet expanded.
3. **History** — member/device picker + date-range control; paginated point list and/or map trail; empty state for no history.
4. **Geofences** — zone list (icon/name/radius) + editor over a map preview with the live circle (name field, icon picker, radius slider, notify-on-enter/exit toggles); save-conflict refresh banner.
5. **Locate-to-request** — instant last-known (with age) → live "updating…" polling pill → terminal states: fresh fix (success) or "couldn't reach the device — showing last known" (warning, never a scary error).
6. **Device & family settings** — grouped lists via SectionHeaders; per-device sync-interval + pause/tracking toggles (parent-editable; owners update only their own push token); member management (roles, remove, step-down/leave); last-parent guardrail with a warm explanation.
7. **Invites** — parent creates a shareable code card + native share; accept flow pastes/deep-links a code, enters display name, joins; friendly invalid/expired guidance.

---

## Platform notes
- **Android (Material 3):** map tokens onto an M3 `ColorScheme` (`primary/onPrimary/surface/surfaceVariant/error`); real dp elevation with tonal overlay; ripple on press; M3 shape families keyed to the radius scale; Roboto `Typography`; genuine M3 list subheaders; M3 switch/slider/FAB anatomy.
- **iOS (HIG):** same tokens drive a SwiftUI theme, but depth comes from the shadow-spec form of each elevation level (no Material overlay). SF Symbols for status glyphs/chevrons, Dynamic Type from the SF Pro sizes, 16pt gutters, grouped-inset lists, native detent bottom sheet on the map, UISwitch-style pills, pressed = dim not ripple.

---

## Assets
No bundled fonts (platform system font only). No image assets — map tiles come from MapKit (iOS) / Maps SDK (Android); status glyphs use SF Symbols / Material Symbols. The HTML reference uses striped placeholders where real map tiles go.

## Files in this bundle
- `Findly Design System.dc.html` — the full visual spec / design reference (open in a browser).
- `FindlyColors.kt` — ready-to-paste Android `LightFindlyColors` / `DarkFindlyColors`.
- `ColorTokens.swift` — ready-to-paste iOS `ColorTokens.light` / `.dark`.
- `README.md` — this document (self-sufficient).
