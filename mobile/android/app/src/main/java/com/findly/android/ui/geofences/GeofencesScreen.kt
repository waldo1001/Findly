package com.findly.android.ui.geofences

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.tooling.preview.Preview
import com.findly.android.ui.designsystem.FindlyTheme
import com.findly.android.ui.designsystem.components.FindlyButton
import com.findly.android.ui.designsystem.components.FindlyButtonStyle
import com.findly.android.ui.designsystem.components.FindlyCard
import com.findly.android.ui.designsystem.components.FindlyEmptyState
import com.findly.android.ui.designsystem.components.FindlyErrorState
import com.findly.android.ui.designsystem.components.FindlyListRow
import com.findly.android.ui.designsystem.components.FindlyLoadingState
import com.findly.android.ui.designsystem.components.FindlyStatusChip
import com.findly.android.ui.designsystem.components.FindlyStatusTone
import com.findly.android.ui.designsystem.components.FindlySwitchRow
import com.findly.android.ui.designsystem.components.FindlyTextField
import com.findly.android.ui.designsystem.components.FindlyTopBar

/**
 * The A2 geofence editor (001-api-contract.md §7.1/§7.2, specs/003-android-client.md §12's
 * `Geofences` destination): list + add/edit/delete form, driven by
 * [GeofencesViewModel]/[GeofencesStateHolder]. Rendered entirely through `ui/designsystem`
 * components.
 */
@Composable
fun GeofencesRoute(viewModel: GeofencesViewModel, modifier: Modifier = Modifier) {
    val state by viewModel.state.collectAsState()
    GeofencesScreen(
        state = state,
        onValidate = viewModel::validate,
        onUpsert = viewModel::upsertGeofence,
        onRemove = viewModel::removeGeofence,
        onSave = viewModel::save,
        onRetry = viewModel::reload,
        modifier = modifier,
    )
}

@Composable
fun GeofencesScreen(
    state: GeofencesUiState,
    modifier: Modifier = Modifier,
    onValidate: (GeofenceUi) -> String? = { null },
    onUpsert: (GeofenceUi) -> Unit = {},
    onRemove: (String) -> Unit = {},
    onSave: () -> Unit = {},
    onRetry: () -> Unit = {},
) {
    var editingDraft by remember { mutableStateOf<GeofenceUi?>(null) }
    var validationError by remember { mutableStateOf<String?>(null) }

    Column(modifier = modifier.fillMaxSize()) {
        FindlyTopBar(
            title = "Geofences",
            actions = {
                FindlyButton(
                    text = "Add",
                    onClick = {
                        editingDraft = GeofenceUi(
                            geofenceId = "gf_${System.currentTimeMillis()}",
                            name = "",
                            lat = 0.0,
                            lon = 0.0,
                            radiusM = 150.0,
                            icon = "pin",
                            notifyOnEnter = true,
                            notifyOnExit = true,
                        )
                    },
                    style = FindlyButtonStyle.Secondary,
                )
            },
        )

        when (state) {
            is GeofencesUiState.Loading -> FindlyLoadingState(message = "Loading geofences…")

            is GeofencesUiState.Error -> FindlyErrorState(
                title = "Couldn't load geofences",
                message = state.message,
                onRetry = onRetry,
            )

            is GeofencesUiState.Content -> {
                val draft = editingDraft
                if (draft != null) {
                    GeofenceEditor(
                        draft = draft,
                        error = validationError,
                        onChange = { editingDraft = it },
                        onCancel = { editingDraft = null; validationError = null },
                        onSave = {
                            val problem = onValidate(draft)
                            if (problem != null) {
                                validationError = problem
                            } else {
                                onUpsert(draft)
                                editingDraft = null
                                validationError = null
                            }
                        },
                    )
                } else {
                    Column(modifier = Modifier.padding(FindlyTheme.spacing.md)) {
                        if (state.conflict) {
                            FindlyStatusChip(
                                label = "Someone else changed this — review, then save again",
                                tone = FindlyStatusTone.Warning,
                            )
                        }
                        if (state.saveError != null) {
                            FindlyStatusChip(label = state.saveError, tone = FindlyStatusTone.Danger)
                        }
                    }

                    if (state.geofences.isEmpty()) {
                        FindlyEmptyState(title = "No geofences yet", message = "Tap Add to create one.")
                    } else {
                        LazyColumn(
                            modifier = Modifier.padding(horizontal = FindlyTheme.spacing.md),
                            verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.xs),
                        ) {
                            items(state.geofences, key = { it.geofenceId }) { geofence ->
                                FindlyListRow(
                                    title = geofence.name,
                                    subtitle = "${geofence.radiusM.toInt()} m radius",
                                    trailing = {
                                        Row(horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.xs)) {
                                            FindlyButton(
                                                text = "Edit",
                                                onClick = { editingDraft = geofence },
                                                style = FindlyButtonStyle.Secondary,
                                            )
                                            FindlyButton(
                                                text = "Delete",
                                                onClick = { onRemove(geofence.geofenceId) },
                                                style = FindlyButtonStyle.Secondary,
                                            )
                                        }
                                    },
                                )
                            }
                        }
                    }

                    FindlyButton(
                        text = if (state.isSaving) "Saving…" else "Save changes",
                        enabled = !state.isSaving,
                        onClick = onSave,
                        modifier = Modifier.padding(FindlyTheme.spacing.md),
                    )
                }
            }
        }
    }
}

@Composable
private fun GeofenceEditor(
    draft: GeofenceUi,
    error: String?,
    onChange: (GeofenceUi) -> Unit,
    onCancel: () -> Unit,
    onSave: () -> Unit,
) {
    FindlyCard(modifier = Modifier.padding(FindlyTheme.spacing.md).fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm)) {
            FindlyTextField(value = draft.name, onValueChange = { onChange(draft.copy(name = it)) }, label = "Name")
            FindlyTextField(
                value = draft.lat.toString(),
                onValueChange = { it.toDoubleOrNull()?.let { lat -> onChange(draft.copy(lat = lat)) } },
                label = "Latitude",
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            )
            FindlyTextField(
                value = draft.lon.toString(),
                onValueChange = { it.toDoubleOrNull()?.let { lon -> onChange(draft.copy(lon = lon)) } },
                label = "Longitude",
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            )
            FindlyTextField(
                value = draft.radiusM.toString(),
                onValueChange = { it.toDoubleOrNull()?.let { radius -> onChange(draft.copy(radiusM = radius)) } },
                label = "Radius (m) — 100 to 5000",
                isError = error != null,
                supportingText = error,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            )
            FindlySwitchRow(
                title = "Notify on enter",
                checked = draft.notifyOnEnter,
                onCheckedChange = { onChange(draft.copy(notifyOnEnter = it)) },
            )
            FindlySwitchRow(
                title = "Notify on exit",
                checked = draft.notifyOnExit,
                onCheckedChange = { onChange(draft.copy(notifyOnExit = it)) },
            )
            Row(horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm)) {
                FindlyButton(text = "Save", onClick = onSave)
                FindlyButton(text = "Cancel", onClick = onCancel, style = FindlyButtonStyle.Secondary)
            }
        }
    }
}

@Preview(name = "Geofences — light", showBackground = true)
@Composable
private fun GeofencesScreenLightPreview() {
    FindlyTheme(darkTheme = false) {
        GeofencesScreen(
            state = GeofencesUiState.Content(
                geofences = listOf(
                    GeofenceUi("gf_home", "Home", 51.0543, 3.7174, 150.0, "home", true, true),
                ),
                etag = "\"4\"",
            ),
        )
    }
}

@Preview(name = "Geofences — dark", showBackground = true)
@Composable
private fun GeofencesScreenDarkPreview() {
    FindlyTheme(darkTheme = true) {
        GeofencesScreen(state = GeofencesUiState.Loading)
    }
}
