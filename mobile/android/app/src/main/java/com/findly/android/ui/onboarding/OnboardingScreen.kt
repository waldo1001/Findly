package com.findly.android.ui.onboarding

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.findly.android.ui.designsystem.FindlyTheme
import com.findly.android.ui.designsystem.components.FindlyButton
import com.findly.android.ui.designsystem.components.FindlyButtonStyle
import com.findly.android.ui.designsystem.components.FindlyEmptyState
import com.findly.android.ui.designsystem.components.FindlyTextField
import com.findly.android.ui.designsystem.components.FindlyTopBar

/**
 * The 010-app-shell-and-screen-ux.md §2.2 Onboarding screen — one route, two variants, replacing
 * the two places this UI lived before this spec (iOS Home's `profileless`/`familyless` branches;
 * Android's `GroupsListScreen` `ProfileNeeded` state — both retired; the A21/I17 behaviors move
 * here unchanged, including the blank-name guard on all four bootstrap paths, which already lives
 * in [com.findly.android.ui.family.CreateFamilyStateHolder.validate] /
 * [com.findly.android.ui.invites.InvitesStateHolder.acceptInvite] /
 * [com.findly.android.ui.groups.CreateGroupStateHolder.validate] /
 * [com.findly.android.ui.groups.GroupJoinStateHolder.validate] and needs no duplicate here).
 *
 * Onboarding is a **root** (010 §2.2: "no back affordance, no drawer") — reached only via a full
 * stack reset (either the 010 §1.1 launch gate, or the 010 §2.1 dead-end routing rule), so there
 * is deliberately nothing behind it to go back to; [FindlyTopBar] renders no back control here
 * simply because [com.findly.android.ui.designsystem.components.LocalNavBackAction] is `null` at
 * this point in the stack, the same mechanism every other screen relies on (specs/003 §12.5) —
 * this screen does not special-case it.
 *
 * No dedicated `StateHolder`/`ViewModel`: this screen holds only the once-typed display-name text
 * (profile-less variant), carried into whichever bootstrap destination the user picks — the exact
 * "enter it once" behavior [com.findly.android.ui.groups.GroupsListScreen]'s retired `ProfileNeeded`
 * branch had.
 */
@Composable
fun OnboardingScreen(
    variant: OnboardingVariant,
    modifier: Modifier = Modifier,
    onCreateFamily: (displayName: String) -> Unit = {},
    onAcceptInvite: (displayName: String) -> Unit = {},
    onCreateGroup: (displayName: String) -> Unit = {},
    onJoinGroup: (displayName: String) -> Unit = {},
    onOpenGroups: () -> Unit = {},
    onOpenPrivacy: () -> Unit = {},
) {
    var displayName by remember { mutableStateOf("") }

    Column(modifier = modifier.fillMaxSize()) {
        FindlyTopBar(title = "Welcome to Findly")

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(FindlyTheme.spacing.md),
            verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
        ) {
            when (variant) {
                OnboardingVariant.ProfileLess -> {
                    FindlyEmptyState(
                        title = "Welcome to Findly",
                        message = "Create or join a family, or start a temporary group — pick how you'd like to get started.",
                    )
                    FindlyTextField(value = displayName, onValueChange = { displayName = it }, label = "Your display name")

                    FindlyButton(text = "Create a family", onClick = { onCreateFamily(displayName) })
                    FindlyButton(
                        text = "I have an invite code",
                        onClick = { onAcceptInvite(displayName) },
                        style = FindlyButtonStyle.Secondary,
                    )
                    FindlyButton(
                        text = "Create a group",
                        onClick = { onCreateGroup(displayName) },
                        style = FindlyButtonStyle.Secondary,
                    )
                    FindlyButton(
                        text = "Join a group",
                        onClick = { onJoinGroup(displayName) },
                        style = FindlyButtonStyle.Secondary,
                    )
                }

                OnboardingVariant.FamilyLess -> {
                    FindlyEmptyState(
                        title = "No family yet",
                        message = "Create a family, join one with an invite code, or keep using groups.",
                    )
                    FindlyButton(text = "Create a family", onClick = { onCreateFamily(displayName) })
                    FindlyButton(
                        text = "I have an invite code",
                        onClick = { onAcceptInvite(displayName) },
                        style = FindlyButtonStyle.Secondary,
                    )
                    FindlyButton(text = "Groups", onClick = onOpenGroups, style = FindlyButtonStyle.Secondary)
                }
            }

            FindlyButton(text = "Privacy & data", onClick = onOpenPrivacy, style = FindlyButtonStyle.Secondary)
        }
    }
}

@Preview(name = "Onboarding — profile-less", showBackground = true)
@Composable
private fun OnboardingScreenProfileLessPreview() {
    FindlyTheme(darkTheme = false) {
        OnboardingScreen(variant = OnboardingVariant.ProfileLess)
    }
}

@Preview(name = "Onboarding — family-less", showBackground = true)
@Composable
private fun OnboardingScreenFamilyLessPreview() {
    FindlyTheme(darkTheme = true) {
        OnboardingScreen(variant = OnboardingVariant.FamilyLess)
    }
}
