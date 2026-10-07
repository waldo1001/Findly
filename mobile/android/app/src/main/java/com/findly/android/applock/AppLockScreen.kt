package com.findly.android.applock

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.findly.android.ui.designsystem.FindlyTheme
import com.findly.android.ui.designsystem.components.FindlyButton
import kotlinx.coroutines.launch

/**
 * The lock screen host (specs/010 section 1.4). Two layers while locked: an opaque in-tree cover
 * (so nothing the UI renders is ever visible, from the first frame) and a full-screen [Dialog]
 * with the same content, because Compose dialogs and sheets are separate windows that an in-tree
 * overlay cannot cover - a window added later sits above every earlier one. Nothing here signs
 * the user out or wipes anything. [onBack] sends the task to the background (Back must not reveal
 * the app behind the lock).
 */
@Composable
fun AppLockHost(controller: AppLockController, onBack: () -> Unit) {
    val locked by controller.locked.collectAsState()
    if (!locked) return
    val scope = rememberCoroutineScope()
    val unlock: () -> Unit = { scope.launch { controller.unlock() } }

    // Auto-prompt once per appearance of the lock (the controller re-arms it when the lock engages).
    LaunchedEffect(Unit) {
        if (controller.consumeAutoPrompt()) controller.unlock()
    }

    AppLockContent(onUnlock = unlock, showButton = false)
    Dialog(
        onDismissRequest = onBack,
        properties = DialogProperties(usePlatformDefaultWidth = false, dismissOnClickOutside = false),
    ) {
        AppLockContent(onUnlock = unlock, showButton = true)
    }
}

@Composable
private fun AppLockContent(onUnlock: () -> Unit, showButton: Boolean) {
    val colors = FindlyTheme.colors
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.surface)
            .pointerInput(Unit) { detectTapGestures { } } // swallow touches: nothing beneath is reachable
            .systemBarsPadding(),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.md),
        ) {
            LockGlyph(tint = colors.primary)
            Text(
                text = "Findly is locked",
                style = FindlyTheme.typography.titleLarge,
                color = colors.onSurface,
            )
            if (showButton) FindlyButton(text = "Unlock", onClick = onUnlock)
        }
    }
}

/** A brand-tinted lock glyph (010 section 1.4 allows it in place of the app icon, which an
 * adaptive launcher icon cannot be drawn as at runtime). */
@Composable
private fun LockGlyph(tint: Color) {
    Canvas(modifier = Modifier.size(72.dp)) {
        val w = size.width
        val h = size.height
        val stroke = w * 0.09f
        val bodyTop = h * 0.45f
        drawRoundRect(
            color = tint,
            topLeft = Offset(w * 0.15f, bodyTop),
            size = Size(w * 0.7f, h * 0.48f),
            cornerRadius = CornerRadius(w * 0.1f),
        )
        drawArc(
            color = tint,
            startAngle = 180f,
            sweepAngle = 180f,
            useCenter = false,
            topLeft = Offset(w * 0.28f, h * 0.08f),
            size = Size(w * 0.44f, (bodyTop - h * 0.08f) * 2f),
            style = Stroke(width = stroke),
        )
    }
}
