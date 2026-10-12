package com.findly.android.ui.groups

import com.findly.android.applock.LocalAppLocked
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import com.findly.android.ui.designsystem.components.FindlyStatusChip
import com.findly.android.ui.designsystem.components.FindlyStatusTone
import com.findly.android.ui.designsystem.components.FindlySwitchRow
import com.findly.android.ui.designsystem.components.FindlyWarningNote
import com.findly.android.ui.designsystem.components.FindlyTextField
import com.findly.android.ui.designsystem.components.FindlyTopBar
import java.time.Instant
import java.time.ZoneOffset

/**
 * The A5 create-group screen (001-api-contract.md §12.1, specs/003-android-client.md §12.2's
 * `CreateGroupSheet` — implemented as a full screen destination rather than a bottom sheet, since
 * that's this app's uniform per-feature-destination shape and there is no bottom-sheet component
 * in `ui/designsystem` to mirror; functionally the same modal-form UX). The end date+time picker
 * reuses the exact [DatePickerDialog]/[DatePicker] pattern
 * [com.findly.android.ui.history.HistoryScreen] already established (themed correctly via
 * `FindlyTheme`'s Material3 mapping, specs/003 §4.3) plus a plain hour/minute [FindlyTextField]
 * pair for the time-of-day component, since Material3's `TimePicker` has no precedent in this
 * codebase; the combined instant is bounded by [CreateGroupViewModel]'s `validate` (001 §12.1's
 * `now + 1h`..`now + maxGroupDurationDays`), not by constraining the picker itself.
 */
@Composable
fun CreateGroupRoute(
    viewModel: CreateGroupViewModel,
    modifier: Modifier = Modifier,
    prefillDisplayName: String = "",
    onCreated: () -> Unit = {},
) {
    val state by viewModel.state.collectAsState()
    CreateGroupScreen(
        state = state,
        needsDisplayName = viewModel.needsDisplayName,
        prefillDisplayName = prefillDisplayName,
        defaultEndsAtMillis = viewModel.defaultEndsAtMillis,
        onNoEndDateChange = viewModel::setNoEndDate,
        onCreate = viewModel::createGroup,
        onCreated = onCreated,
        modifier = modifier,
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateGroupScreen(
    state: CreateGroupUiState,
    modifier: Modifier = Modifier,
    needsDisplayName: Boolean = false,
    prefillDisplayName: String = "",
    /** Initial end date: now + 24 h (005 §2.5 item 1), from [CreateGroupStateHolder.defaultEndsAtMillis]. */
    defaultEndsAtMillis: Long? = null,
    onNoEndDateChange: (Boolean) -> Unit = {},
    onCreate: (name: String, endsAtMillis: Long?, expiryPolicy: String, displayName: String?) -> Unit =
        { _, _, _, _ -> },
    onCreated: () -> Unit = {},
) {
    var name by remember { mutableStateOf("") }
    // A21: seeded from the profile-less first-run screen's shared display-name entry
    // (GroupsListUiState.CreateJoinContext.prefillDisplayName) when reached from there — still
    // editable, same "enter it once" intent as GroupJoinScreen's prefillCode.
    var displayName by remember { mutableStateOf(prefillDisplayName) }
    var expiryPolicy by remember { mutableStateOf("delete") }
    // The picker date is a UTC-midnight millis; hour/minute are the UTC time-of-day fields.
    val defaultAt = remember(defaultEndsAtMillis) { defaultEndsAtMillis?.let { Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC) } }
    var dateMillis by remember { mutableStateOf(defaultAt?.toLocalDate()?.atStartOfDay(ZoneOffset.UTC)?.toInstant()?.toEpochMilli()) }
    var hour by remember { mutableStateOf(defaultAt?.hour?.toString() ?: "22") }
    var minute by remember { mutableStateOf(defaultAt?.minute?.toString()?.padStart(2, '0') ?: "00") }
    var showDatePicker by remember { mutableStateOf(false) }

    LaunchedEffect(state.created) {
        if (state.created != null) onCreated()
    }

    Column(modifier = modifier.fillMaxSize()) {
        FindlyTopBar(title = "Create group")

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(FindlyTheme.spacing.md),
            verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
        ) {
            FindlyTextField(value = name, onValueChange = { name = it }, label = "Group name")

            if (needsDisplayName) {
                FindlyTextField(value = displayName, onValueChange = { displayName = it }, label = "Your display name")
            }

            FindlyButton(
                text = dateMillis?.let { "End date: ${it.toIsoDate()}" } ?: "Pick end date",
                onClick = { showDatePicker = true },
                enabled = !state.noEndDate,
                style = FindlyButtonStyle.Secondary,
            )

            Row(horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm)) {
                FindlyTextField(
                    value = hour,
                    onValueChange = { if (it.length <= 2) hour = it.filter(Char::isDigit) },
                    label = "Hour (0-23, UTC)",
                    enabled = !state.noEndDate,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth(),
                )
                FindlyTextField(
                    value = minute,
                    onValueChange = { if (it.length <= 2) minute = it.filter(Char::isDigit) },
                    label = "Minute (0-59)",
                    enabled = !state.noEndDate,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            // 005 §2.5 items 1-2: an explicit choice next to the picker (never preselected), with
            // the warning directly under it while on.
            FindlySwitchRow(
                title = "No end date",
                checked = state.noEndDate,
                onCheckedChange = onNoEndDateChange,
                enabled = !state.isCreating,
            )
            if (state.noEndDate) {
                FindlyWarningNote(
                    lead = GroupPolicyCopy.NO_END_DATE_WARNING_LEAD,
                    body = GroupPolicyCopy.NO_END_DATE_WARNING_BODY,
                )
            }

            FindlyCard {
                Column(verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.xs)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm)) {
                        GroupPolicyCopy.ALL_POLICIES.forEach { policy ->
                            FindlyButton(
                                text = policy.replaceFirstChar(Char::uppercase),
                                onClick = { expiryPolicy = policy },
                                style = if (expiryPolicy == policy) FindlyButtonStyle.Primary else FindlyButtonStyle.Secondary,
                            )
                        }
                    }
                    FindlyStatusChip(label = GroupPolicyCopy.forPolicy(expiryPolicy), tone = FindlyStatusTone.Neutral)
                    // 005 §2.5 item 3: one-line note under the promise while "No end date" is on.
                    if (state.noEndDate) {
                        FindlyStatusChip(label = GroupPolicyCopy.NO_END_DATE_POLICY_NOTE, tone = FindlyStatusTone.Neutral)
                    }
                }
            }

            state.validationError?.let { FindlyStatusChip(label = it, tone = FindlyStatusTone.Danger) }
            state.submitError?.let { FindlyStatusChip(label = it, tone = FindlyStatusTone.Danger) }

            FindlyButton(
                text = if (state.isCreating) "Creating…" else "Create group",
                enabled = !state.isCreating,
                onClick = {
                    val endsAtMillis = if (state.noEndDate) null else dateMillis?.let { combineDateAndTime(it, hour.toIntOrNull() ?: 0, minute.toIntOrNull() ?: 0) }
                    onCreate(name, endsAtMillis, expiryPolicy, displayName.ifBlank { null })
                },
            )
        }
    }

    if (showDatePicker && !LocalAppLocked.current) {
        val pickerState = rememberDatePickerState()
        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                FindlyButton(
                    text = "OK",
                    onClick = {
                        pickerState.selectedDateMillis?.let { dateMillis = it }
                        showDatePicker = false
                    },
                )
            },
            dismissButton = { FindlyButton(text = "Cancel", onClick = { showDatePicker = false }, style = FindlyButtonStyle.Secondary) },
        ) { DatePicker(state = pickerState) }
    }
}

/** Combines a `DatePickerState.selectedDateMillis` (midnight UTC of the picked date, per Material3's
 * documented contract) with an hour/minute, both interpreted in UTC (out-of-range values are
 * clamped) — mirrors [com.findly.android.ui.history.HistoryScreen]'s `Long.toIsoDate()` UTC
 * convention. Pure; shared with [GroupDetailScreen]'s "Set an end date" picker and unit-tested in
 * `GroupEndsAtValidationTest`. */
internal fun combineDateAndTime(dateMillis: Long, hour: Int, minute: Int): Long =
    Instant.ofEpochMilli(dateMillis)
        .atZone(ZoneOffset.UTC)
        .withHour(hour.coerceIn(0, 23))
        .withMinute(minute.coerceIn(0, 59))
        .withSecond(0)
        .withNano(0)
        .toInstant()
        .toEpochMilli()

private fun Long.toIsoDate(): String = Instant.ofEpochMilli(this).atZone(ZoneOffset.UTC).toLocalDate().toString()

@Preview(name = "Create group — light", showBackground = true)
@Composable
private fun CreateGroupScreenLightPreview() {
    FindlyTheme(darkTheme = false) {
        CreateGroupScreen(state = CreateGroupUiState())
    }
}

@Preview(name = "Create group — dark (needs display name)", showBackground = true)
@Composable
private fun CreateGroupScreenDarkPreview() {
    FindlyTheme(darkTheme = true) {
        CreateGroupScreen(state = CreateGroupUiState(validationError = "Pick an end date and time", noEndDate = true), needsDisplayName = true)
    }
}
