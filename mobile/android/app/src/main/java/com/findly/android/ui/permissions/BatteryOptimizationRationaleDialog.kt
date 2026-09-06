package com.findly.android.ui.permissions

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable

/**
 * specs/009-device-runtime.md §3.2 "Battery-optimisation exemption": "the client MUST, once per
 * install, explain and offer the `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` prompt." A short
 * rationale ahead of the system dialog, same spirit as [PermissionDisclosureScreen] but a
 * lightweight `AlertDialog` rather than a full screen — 010 §5.1's documented exception for a
 * confirm-style dialog applies here too, and this ask is a single yes/no with nothing to scroll.
 *
 * Stateless: [onContinue] launches the OS prompt and records the answer; [onNotNow] records the
 * decline without ever showing the OS dialog (declining is not fatal, §3.2: "the service still
 * runs"). Both are terminal — this dialog is never re-shown automatically once either fires
 * (`BatteryOptimizationPromptStore`, `BatteryOptimizationPromptPolicy`).
 */
@Composable
fun BatteryOptimizationRationaleDialog(
    onContinue: () -> Unit,
    onNotNow: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onNotNow,
        title = { Text("Keep location sharing reliable") },
        text = {
            Text(
                "Some phones aggressively stop background apps to save battery, which can make " +
                    "your family see you as offline more than they should. Letting Findly skip " +
                    "battery optimization keeps location sharing running smoothly. You can change " +
                    "this later from the Devices screen.",
            )
        },
        confirmButton = { TextButton(onClick = onContinue) { Text("Continue") } },
        dismissButton = { TextButton(onClick = onNotNow) { Text("Not now") } },
    )
}
