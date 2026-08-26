package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.findly.android.ui.designsystem.FindlyTheme
import com.findly.android.ui.designsystem.token.TextFieldDisabledBorder
import com.findly.android.ui.designsystem.token.TextFieldDisabledFill
import com.findly.android.ui.designsystem.token.TextFieldDisabledText

/**
 * One presentable option in a [FindlyDropdownField]. [enabled]/[disabledReason] let a caller
 * pre-disable a value the current plan can't use — specs/010-app-shell-and-screen-ux.md §4.2:
 * "Values below `features.limits.minSyncIntervalMinutes` render disabled with the limit as the
 * reason" — while still *presenting* every allowed value (010 §9: the server remains the sole
 * source of truth for validation; this is presentation only, never the only guard).
 */
data class FindlyDropdownOption<T>(
    val value: T,
    val label: String,
    val enabled: Boolean = true,
    val disabledReason: String? = null,
)

/**
 * A labeled single-select exposed dropdown (specs/010-app-shell-and-screen-ux.md §1.2/§4.2, added
 * to the 003 §4.3 component contract in the same PR as that spec) — the device sync-interval
 * control over the 001 §1.4 value set. Stateless/presentational like every other design-system
 * component (003 §4.3): the caller supplies [selected]/[options] and reacts to a choice in
 * [onSelect] — this component never calls a network API or reads a ViewModel, and selecting an
 * option **commits immediately** (010 §4.2: "no Save button") — that is the caller's contract to
 * honor in [onSelect], not something this component enforces itself.
 *
 * Platform-native mechanics underneath — Android's exposed-dropdown-menu idiom
 * ([DropdownMenu]/[DropdownMenuItem], 010 §4.2's "exposed dropdown menu on Android") — are this
 * component's own implementation detail, the same category [FindlyNavDrawer]'s doc describes for
 * `ModalNavigationDrawer`-class behavior: not one of the 003 §4.3 "components only" screen-level
 * exceptions, because this *is* the design system's own implementation of the control, not a
 * screen reaching past it.
 *
 * Geometry/colors deliberately mirror [FindlyTextField] (52dp field, `md` corner,
 * `surfaceVariant` fill, `outlineStrong` border, `primary` when open) so a screen combining both —
 * the §4.2 device card does, sync-interval dropdown next to the rename text field — reads as one
 * visual language. Reads only [FindlyTheme] tokens: every piece of text uses a
 * [FindlyTheme.typography] role (never a literal `TextStyle`/font size), every color is a
 * [FindlyTheme.colors] field or one of the existing disabled-state token constants
 * ([TextFieldDisabledFill]/[TextFieldDisabledBorder]/[TextFieldDisabledText], already established
 * by [FindlyTextField] — reused here rather than adding new token names, per the 003 §4.1 rule
 * that the token vocabulary is not renamed/extended without a spec PR).
 */
@Composable
fun <T> FindlyDropdownField(
    label: String,
    selected: T,
    options: List<FindlyDropdownOption<T>>,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    var expanded by remember { mutableStateOf(false) }
    val colors = FindlyTheme.colors
    val shape = RoundedCornerShape(FindlyTheme.corner.md)
    val selectedLabel = options.firstOrNull { it.value == selected }?.label.orEmpty()

    val fill: Color
    val borderColor: Color
    val textColor: Color
    when {
        !enabled -> {
            fill = TextFieldDisabledFill
            borderColor = TextFieldDisabledBorder
            textColor = TextFieldDisabledText
        }
        expanded -> {
            fill = colors.surfaceVariant
            borderColor = colors.primary
            textColor = colors.onSurface
        }
        else -> {
            fill = colors.surfaceVariant
            borderColor = colors.outlineStrong
            textColor = colors.onSurface
        }
    }

    Column(modifier = modifier.fillMaxWidth()) {
        Text(text = label.uppercase(), color = colors.subtleText, style = FindlyTheme.typography.labelSmall)

        Box {
            var fieldModifier = Modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = 52.dp)
                .clip(shape)
                .background(fill)
                .border(width = 1.5.dp, color = borderColor, shape = shape)
            fieldModifier = if (enabled) {
                fieldModifier.clickable(onClickLabel = label) { expanded = true }
            } else {
                fieldModifier.semantics { disabled() }
            }

            Row(
                modifier = fieldModifier
                    .padding(horizontal = FindlyTheme.spacing.sm, vertical = FindlyTheme.spacing.sm)
                    .semantics { contentDescription = label },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(text = selectedLabel, color = textColor, style = FindlyTheme.typography.bodyLarge)
                Text(text = if (expanded) "▲" else "▼", color = textColor, style = FindlyTheme.typography.labelSmall)
            }

            DropdownMenu(
                expanded = expanded,
                onDismissRequest = { expanded = false },
                containerColor = colors.surface,
            ) {
                options.forEach { option ->
                    DropdownMenuItem(
                        text = {
                            Column {
                                Text(
                                    text = option.label,
                                    color = if (option.enabled) colors.onSurface else colors.subtleText,
                                    style = FindlyTheme.typography.bodyLarge,
                                )
                                if (!option.enabled && option.disabledReason != null) {
                                    Text(
                                        text = option.disabledReason,
                                        color = colors.subtleText,
                                        style = FindlyTheme.typography.labelSmall,
                                    )
                                }
                            }
                        },
                        enabled = option.enabled,
                        onClick = {
                            expanded = false
                            onSelect(option.value)
                        },
                    )
                }
            }
        }
    }
}
