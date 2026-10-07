package com.findly.android.applock

import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics

/** True while the lock screen is up (specs/010 section 1.4). App-owned dialogs and sheets are not
 * composed while it is true, because a window created after the lock Dialog would sit above it;
 * they appear after unlock if their state still says so. Provided by `MainActivity`. */
val LocalAppLocked = compositionLocalOf { false }

/** While [locked], removes this subtree from the accessibility tree so TalkBack reaches only the
 * lock screen (the opaque cover only swallows touches). */
fun Modifier.hiddenWhenLocked(locked: Boolean): Modifier =
    if (locked) clearAndSetSemantics { } else this

/** Composes [content] (an app-owned dialog or sheet) only while the app is not locked. */
@androidx.compose.runtime.Composable
fun UnlessLocked(content: @androidx.compose.runtime.Composable () -> Unit) {
    if (!LocalAppLocked.current) content()
}
