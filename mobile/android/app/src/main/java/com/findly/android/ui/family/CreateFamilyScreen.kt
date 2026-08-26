package com.findly.android.ui.family

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.findly.android.ui.designsystem.FindlyTheme
import com.findly.android.ui.designsystem.components.FindlyButton
import com.findly.android.ui.designsystem.components.FindlyStatusChip
import com.findly.android.ui.designsystem.components.FindlyStatusTone
import com.findly.android.ui.designsystem.components.FindlyTextField
import com.findly.android.ui.designsystem.components.FindlyTopBar

/**
 * The A21 create-family screen (001-api-contract.md §3.1): the client's only entry point for
 * `POST /families` — see [CreateFamilyStateHolder]'s doc for why this screen didn't exist before.
 * Same two-field-plus-submit shape as [com.findly.android.ui.groups.CreateGroupScreen]/
 * [com.findly.android.ui.groups.GroupJoinScreen].
 *
 * [prefillDisplayName] seeds the display-name field when this screen is reached from the
 * profile-less first-run flow ([com.findly.android.ui.onboarding.OnboardingScreen], specs/010-
 * app-shell-and-screen-ux.md §2.2), where the user already typed their name once — same "enter it
 * once" intent as [com.findly.android.ui.groups.GroupJoinScreen]'s `prefillCode`, just for a
 * different field.
 */
@Composable
fun CreateFamilyRoute(
    viewModel: CreateFamilyViewModel,
    modifier: Modifier = Modifier,
    prefillDisplayName: String = "",
    onCreated: () -> Unit = {},
) {
    val state by viewModel.state.collectAsState()
    CreateFamilyScreen(
        state = state,
        prefillDisplayName = prefillDisplayName,
        onCreate = viewModel::createFamily,
        onCreated = onCreated,
        modifier = modifier,
    )
}

@Composable
fun CreateFamilyScreen(
    state: CreateFamilyUiState,
    modifier: Modifier = Modifier,
    prefillDisplayName: String = "",
    onCreate: (familyName: String, displayName: String) -> Unit = { _, _ -> },
    onCreated: () -> Unit = {},
) {
    var familyName by remember { mutableStateOf("") }
    var displayName by remember { mutableStateOf(prefillDisplayName) }

    LaunchedEffect(state.created) {
        if (state.created != null) onCreated()
    }

    Column(modifier = modifier.fillMaxSize()) {
        FindlyTopBar(title = "Create a family")

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(FindlyTheme.spacing.md),
            verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
        ) {
            FindlyTextField(value = familyName, onValueChange = { familyName = it }, label = "Family name")
            FindlyTextField(value = displayName, onValueChange = { displayName = it }, label = "Your display name")

            state.validationError?.let { FindlyStatusChip(label = it, tone = FindlyStatusTone.Danger) }
            state.submitError?.let { FindlyStatusChip(label = it, tone = FindlyStatusTone.Danger) }

            FindlyButton(
                text = if (state.isCreating) "Creating…" else "Create family",
                enabled = !state.isCreating,
                onClick = { onCreate(familyName, displayName) },
            )
        }
    }
}

@Preview(name = "Create family — light", showBackground = true)
@Composable
private fun CreateFamilyScreenLightPreview() {
    FindlyTheme(darkTheme = false) {
        CreateFamilyScreen(state = CreateFamilyUiState())
    }
}

@Preview(name = "Create family — dark (error)", showBackground = true)
@Composable
private fun CreateFamilyScreenDarkPreview() {
    FindlyTheme(darkTheme = true) {
        CreateFamilyScreen(
            state = CreateFamilyUiState(submitError = "You're already part of a family."),
            prefillDisplayName = "Eric",
        )
    }
}
