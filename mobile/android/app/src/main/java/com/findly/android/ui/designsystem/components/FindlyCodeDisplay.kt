package com.findly.android.ui.designsystem.components

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.sp
import com.findly.android.ui.designsystem.FindlyTheme

/**
 * Review-round addition (A36, specs/010-app-shell-and-screen-ux.md §5.1: "The code, large and
 * copyable: `titleLarge`-class size, tabular figures, letter-spaced, in hyphenated display
 * form"). `titleLarge` alone covers the size; tabular figures and extra letter-spacing need a
 * value the six §4.1 type roles don't carry, and 003 §4.3 forbids a screen from reaching for a
 * literal `TextStyle.copy(letterSpacing = …)` itself. This component is where that value-level
 * derivation belongs instead — the same precedent [FindlyMapMarkerBubble]'s `selected` flag and
 * its private `MarkerNameStyle`/`NowPillStyle`/`StaleAgeStyle` constants already set: a
 * presentational component MAY hold its own `TextStyle` literals (raw `.sp` included) as long as
 * every *color* still comes from [FindlyTheme], and no §4.1 type-role or §4.1/§4.2 color-token
 * *name* is added, renamed, or bypassed. [CodeDisplayLetterSpacing]/[CodeDisplayFontFeatureSettings]
 * are exactly that: a component-local rendering detail, not a new contract vocabulary entry —
 * `FindlyTheme.typography.titleLarge` (already bold, already carrying its own -0.2sp tracking,
 * 003 §4.2) is the base every property is derived from via `.copy()`, never replaced.
 *
 * Used by [com.findly.android.ui.invites.CreateInviteScreen] for the create-invite success
 * view's large invite-code display; [code] is expected to already be in hyphenated display form
 * (`XXXX-XXXX`, 001-api-contract.md §1.4) — this component does no formatting of its own.
 */
private val CodeDisplayLetterSpacing = 4.sp

/** `"tnum"` (OpenType tabular-figures feature) — every digit renders at the same advance width,
 * so the code doesn't visually jitter/re-flow as different digits appear (HANDOFF.md's own
 * "tabular figures" ask, 010 §5.1). Not a color, not a §4.1 type role, not a spacing/corner/
 * elevation token — a raster/typesetting detail with no equivalent in the §4.1 vocabulary. */
private const val CodeDisplayFontFeatureSettings = "tnum"

@Composable
fun FindlyCodeDisplay(code: String, modifier: Modifier = Modifier) {
    Text(
        text = code,
        modifier = modifier,
        color = FindlyTheme.colors.onSurface,
        style = FindlyTheme.typography.titleLarge.copy(
            letterSpacing = CodeDisplayLetterSpacing,
            fontFeatureSettings = CodeDisplayFontFeatureSettings,
        ),
    )
}
