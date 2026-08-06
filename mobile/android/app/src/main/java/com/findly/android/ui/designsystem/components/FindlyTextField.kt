package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.findly.android.ui.designsystem.FindlyTheme
import com.findly.android.ui.designsystem.token.TextFieldDisabledBorder
import com.findly.android.ui.designsystem.token.TextFieldDisabledFill
import com.findly.android.ui.designsystem.token.TextFieldDisabledText

private val FieldTextStyle = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Normal)
private val FieldLabelStyle = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Medium)
private val SupportingTextStyle = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Normal)

/**
 * A stateless, presentational single-line (by default) text input — added in A2 for the geofence
 * editor (name/lat/lon/radius), invite-code entry, and display-name fields; [visualTransformation]
 * was added at H1 for the (now-deleted, specs/006-phone-auth.md) email/password sign-in screen's
 * password field — kept as a general-purpose parameter, unused by the phone sign-in screen (A3).
 * Reads only [FindlyTheme] tokens (specs/003-android-client.md §4.3).
 *
 * Geometry/states from design 2a (design/findly-design-system/2a-ember-dusk/HANDOFF.md,
 * `FindlyTextField`): 52dp height, radius `md` (the handoff's own mock renders it closer to 16dp,
 * but the token is what's normative), `surfaceVariant` fill, text 16/400. The default (unfocused,
 * non-error) border uses [FindlyTheme.colors.outlineStrong] rather than the decorative `outline`
 * — HANDOFF.md's own contrast-trap callout names "an input outline" as exactly the kind of
 * meaning-carrying stroke that must use the stronger color, even though the `FindlyTextField`
 * prose elsewhere just says "outline". Focused swaps the border to `primary` plus a translucent
 * `primary` ring; error swaps it to `danger` with a `✕`-prefixed message below; disabled uses the
 * handoff's fixed (non-theme-resolved) disabled palette. HANDOFF.md doesn't describe a caption
 * label above the field (only the placeholder text and the 52dp field itself), so [label]'s
 * treatment here is a reasonable, unspecified-by-the-handoff extension of the existing API rather
 * than a value taken from HANDOFF.md.
 */
@Composable
fun FindlyTextField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    label: String? = null,
    placeholder: String? = null,
    isError: Boolean = false,
    supportingText: String? = null,
    singleLine: Boolean = true,
    enabled: Boolean = true,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    visualTransformation: VisualTransformation = VisualTransformation.None,
) {
    val colors = FindlyTheme.colors
    val shape = RoundedCornerShape(FindlyTheme.corner.md)
    val interactionSource = remember { MutableInteractionSource() }
    val isFocused by interactionSource.collectIsFocusedAsState()

    Column(modifier = modifier.fillMaxWidth()) {
        if (label != null) {
            Text(text = label, color = colors.subtleText, style = FieldLabelStyle)
        }

        val fill: androidx.compose.ui.graphics.Color
        val borderColor: androidx.compose.ui.graphics.Color
        val textColor: androidx.compose.ui.graphics.Color
        when {
            !enabled -> {
                fill = TextFieldDisabledFill
                borderColor = TextFieldDisabledBorder
                textColor = TextFieldDisabledText
            }
            isError -> {
                fill = colors.surfaceVariant
                borderColor = colors.danger
                textColor = colors.onSurface
            }
            isFocused -> {
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

        var fieldModifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 52.dp)
            .clip(shape)
            .background(fill)
            .border(width = 1.5.dp, color = borderColor, shape = shape)
        if (isFocused && enabled && !isError) {
            // Focused: border `primary` plus a 3px `rgba(primary,.18)` ring — the theme's own
            // `primary` token, alpha-derived so it is correct in both themes (HANDOFF.md gives
            // this as an overlay on the light primary hex only).
            fieldModifier = fieldModifier.border(width = 3.dp, color = colors.primary.copy(alpha = 0.18f), shape = shape)
        }

        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            enabled = enabled,
            singleLine = singleLine,
            interactionSource = interactionSource,
            keyboardOptions = keyboardOptions,
            visualTransformation = visualTransformation,
            textStyle = FieldTextStyle.copy(color = textColor),
            cursorBrush = SolidColor(colors.primary),
            modifier = fieldModifier.padding(horizontal = FindlyTheme.spacing.sm, vertical = FindlyTheme.spacing.sm),
            decorationBox = { innerTextField ->
                if (value.isEmpty() && placeholder != null) {
                    Text(text = placeholder, color = colors.subtleText, style = FieldTextStyle)
                }
                innerTextField()
            },
        )

        if (supportingText != null) {
            Text(
                text = if (isError) "✕ $supportingText" else supportingText,
                color = if (isError) colors.danger else colors.subtleText,
                style = SupportingTextStyle,
            )
        }
    }
}
