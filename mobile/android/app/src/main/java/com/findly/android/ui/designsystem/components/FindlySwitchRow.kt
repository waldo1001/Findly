package com.findly.android.ui.designsystem.components

import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.findly.android.ui.designsystem.FindlyTheme

/**
 * A [FindlyListRow] with a trailing toggle — added in A2 for device settings (pause/
 * `trackingEnabled`) and geofence notify-on-enter/exit flags. Composes only the existing
 * [FindlyListRow] plus a [Switch] explicitly recolored from [FindlyTheme] tokens (never a raw
 * `Color(...)` literal), so a device-settings/geofence screen never needs to reach for a bare
 * Material3 primitive with default (un-themed) colors (specs/003-android-client.md §4.3).
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
        trailing = {
            Switch(
                checked = checked,
                onCheckedChange = onCheckedChange,
                enabled = enabled,
                colors = SwitchDefaults.colors(
                    checkedThumbColor = FindlyTheme.colors.onPrimary,
                    checkedTrackColor = FindlyTheme.colors.primary,
                    uncheckedThumbColor = FindlyTheme.colors.onSurface,
                    uncheckedTrackColor = FindlyTheme.colors.surfaceVariant,
                ),
            )
        },
    )
}
