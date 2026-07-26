# Findly app icon — "Stepped F"

Delivered design handoff (2026-07-25). A soft location pin holding three shortening bars: read one way the letter **F**, read another a signal resolving, inside a dashed halo.

Integration tasks: **A13** (Android launcher + notification icons — done, see `docs/implementation-handoff.md`'s backlog row), **I9** (iOS asset catalogue, which is where the app target is created). Neither `specs/003` nor `specs/004` owns app-launcher-icon integration as a dedicated section — the backlog rows above are the authoritative task definitions; the one spec rule that does apply is the notification-icon rule in [`specs/009 §8`](../../specs/009-device-runtime.md) (status-bar icon must be the monochrome silhouette, since Android renders status icons as a mask).

## What was in the handoff, and what was already done

The delivered package contained both the **design token system** and the **icon**. The tokens (colors, type, spacing, corner, elevation) were **verified byte-identical** to the values already applied on 2026-07-20 (`design/findly-design-system/`) — `diff` of the full hex sets is clean — so **no token work was needed**; only the icon (§4 of the handoff) is new. The handoff's `WaldoColors.kt` / `ColorTokens.swift` keep their original type names deliberately, to match the existing code seam (only the product name changed, not the API).

## Contents

| Path | What |
|---|---|
| `assets/*.svg` | 1024 masters — `light`, `dark`, `tinted`; plus `small-40` (40 pt degradation master) and `mark-silhouette` (29 pt and below) |
| `assets/GEOMETRY.txt` | Canonical geometry on the 1024 grid — the authority if anything is ever regenerated |
| `android/*.xml` | Drop-in `VectorDrawable`s: adaptive-icon layers (`ic_launcher_background/foreground/monochrome`), the `anydpi-v26` wrapper (`ic_launcher.xml`), and the two status-bar icons (`ic_stat_findly`, `ic_stat_locating`) |
| `generated/*.png` | Rasterised 2026-07-25 with `rsvg-convert` — the handoff's "still to produce" list |
| `Findly Icon Proposal.dc.html` | Visual spec — open in a browser. Reference only, not production code |

## Generated PNGs

Produced from the SVG masters; **all verified alpha-free** (`sips -g hasAlpha` → `no`), which is the handoff's #1 "things that will bite": the App Store rejects a 1024 master carrying an alpha channel. The SVGs paint a full-bleed background rect, so flattening was inherent rather than composited.

| File | Use |
|---|---|
| `AppIcon-1024-{light,dark,tinted}.png` | iOS asset catalogue, three appearances |
| `play_store_512.png` | Play Console listing icon |
| `findly-icon-small-{40,80,120}px.png` | The 40 pt master at @1x/@2x/@3x |

To regenerate: `rsvg-convert -w <px> -h <px> assets/findly-icon-light.svg -o out.png`.

**Not provided by the handoff:** the intermediate 80–58 pt master (two bars, circle halo only) described in the degradation ladder. Only the full 1024, the 40 pt, and the silhouette masters exist as artwork. If the ladder's middle rung is wanted, it needs a design round — it is not derivable by scaling either neighbour.

## Rules that must survive integration

- **Android `VectorDrawable` has no `stroke-dasharray`** — the dashed halo in `ic_launcher_foreground.xml` is exported as 55 discrete arc paths on purpose. Regenerating it with a dashed stroke silently renders solid.
- The foreground group is scaled **0.738** about centre so the halo lands inside the 66 dp keyline; drawn to the 72 dp edge the circle mask shaves it on some devices.
- The halo lives in the **foreground** layer, never the background, so no mask can clip a partial ring.
- Splash screen and the monochrome layer both **drop the halo** (it flickers during the launch fade and survives Material You tinting badly).
- Never: gradient/bevel/inner shadow on the background · rotate the pin or change bar angle · recolour outside the three appearances · bars as live text · non-square canvas.
- Marketing/store clear space: ¼ of icon width all sides. Inside the OS, none — the platform owns spacing.
