package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.input.VisualTransformation
import com.findly.android.ui.designsystem.FindlyTheme

/**
 * A stateless, presentational single-line (by default) text input — added in A2 for the geofence
 * editor (name/lat/lon/radius), invite-code entry, and display-name fields; [visualTransformation]
 * was added at H1 for the (now-deleted, specs/006-phone-auth.md) email/password sign-in screen's
 * password field — kept as a general-purpose parameter, unused by the phone sign-in screen (A3).
 * Reads only [FindlyTheme] tokens (specs/003-android-client.md §4.3); border width reuses
 * [FindlyTheme.elevation]'s `level1`, matching [FindlyMapMarkerBubble]'s existing convention for
 * hairline strokes so no raw `.dp` literal appears even inside this design-system file.
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
    Column(modifier = modifier.fillMaxWidth()) {
        if (label != null) {
            Text(
                text = label,
                color = FindlyTheme.colors.outline,
                style = FindlyTheme.typography.labelSmall,
            )
        }

        val borderColor = if (isError) FindlyTheme.colors.danger else FindlyTheme.colors.outline

        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            enabled = enabled,
            singleLine = singleLine,
            keyboardOptions = keyboardOptions,
            visualTransformation = visualTransformation,
            textStyle = FindlyTheme.typography.bodyLarge.copy(color = FindlyTheme.colors.onSurface),
            cursorBrush = SolidColor(FindlyTheme.colors.primary),
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(FindlyTheme.corner.sm))
                .background(FindlyTheme.colors.surfaceVariant)
                .border(
                    width = FindlyTheme.elevation.level1,
                    color = borderColor,
                    shape = RoundedCornerShape(FindlyTheme.corner.sm),
                )
                .padding(horizontal = FindlyTheme.spacing.sm, vertical = FindlyTheme.spacing.sm),
            decorationBox = { innerTextField ->
                if (value.isEmpty() && placeholder != null) {
                    Text(
                        text = placeholder,
                        color = FindlyTheme.colors.outline,
                        style = FindlyTheme.typography.bodyLarge,
                    )
                }
                innerTextField()
            },
        )

        if (supportingText != null) {
            Text(
                text = supportingText,
                color = if (isError) FindlyTheme.colors.danger else FindlyTheme.colors.outline,
                style = FindlyTheme.typography.labelSmall,
            )
        }
    }
}
