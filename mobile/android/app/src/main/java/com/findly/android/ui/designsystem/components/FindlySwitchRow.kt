package com.findly.android.ui.designsystem.components

import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.findly.android.ui.designsystem.FindlyTheme
import com.findly.android.ui.designsystem.token.SwitchThumbColor

/**
 * A [FindlyListRow] with a trailing toggle — added in A2 for device settings (pause/
 * `trackingEnabled`) and geofence notify-on-enter/exit flags. Composes only the existing
 * [FindlyListRow] plus a [Switch] explicitly recolored from [FindlyTheme] tokens (never a raw
 * `Color(...)` literal), so a device-settings/geofence screen never needs to reach for a bare
 * Material3 primitive with default (un-themed) colors (specs/003-android-client.md §4.3).
 *
 * Design 2a (design/findly-design-system/2a-ember-dusk/HANDOFF.md, `FindlySwitchRow`): 56dp
 * minimum height (smaller than `FindlyListRow`'s own 60dp default — passed explicitly below),
 * label 16/600 (inherited from `FindlyListRow`'s title style). **Uses the native M3 `Switch` on
 * Android** — the handoff's mock only draws a bespoke 52×32 track to communicate the on/off
 * colours (`primary` track when on, `outline` track when off, white thumb); it explicitly is not
 * a component to reproduce pixel-for-pixel ("the mock draws a … track … only to show the on/off
 * colours"), matching the handoff's platform-divergence rule (native switch/ripple on Android,
 * native `Toggle`/`UISwitch` on iOS — do not cross-port).
 */
@Composable
fun FindlySwitchRow(
    title: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    enabled: Boolean = true,
) {
    FindlyListRow(
        title = title,
        subtitle = subtitle,
        modifier = modifier,
        enabled = enabled,
        minHeight = 56.dp,
        trailing = {
            Switch(
                checked = checked,
                onCheckedChange = onCheckedChange,
                enabled = enabled,
                colors = SwitchDefaults.colors(
                    checkedThumbColor = SwitchThumbColor,
                    checkedTrackColor = FindlyTheme.colors.primary,
                    uncheckedThumbColor = SwitchThumbColor,
                    // Intentionally the decorative `outline` (not `outlineStrong`), matching
                    // HANDOFF.md exactly — flagged in A26 security review as a possible
                    // status-by-colour-alone risk and judged NOT one: the native M3 `Switch`
                    // conveys on/off primarily via thumb position (and its accessibility
                    // role/state for TalkBack), not track colour, so a low-contrast off-track
                    // doesn't hide any state a user depends on colour alone to read. Do not
                    // "fix" this to outlineStrong without re-checking that reasoning.
                    uncheckedTrackColor = FindlyTheme.colors.outline,
                ),
            )
        },
    )
}
