package com.findly.android.ui.signin

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
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
import com.findly.android.ui.designsystem.components.FindlyErrorState
import com.findly.android.ui.designsystem.components.FindlyLoadingState
import com.findly.android.ui.designsystem.components.FindlyTextField
import com.findly.android.ui.designsystem.components.FindlyTopBar

/**
 * The phone sign-in screen (specs/006-phone-auth.md §4.1, specs/003-android-client.md §7): one
 * screen, two steps — phone entry, then code entry — rendered entirely through
 * `ui/designsystem` components, driven by state hoisted from [SignInStateHolder] via
 * [SignInViewModel]. There is no "signed in" branch here — once verification/confirmation
 * succeeds, `AuthProvider.authState` itself flips to `SignedIn`, which `FindlyNavHost` observes to
 * pop this screen off the back stack.
 */
@Composable
fun SignInRoute(viewModel: SignInViewModel, modifier: Modifier = Modifier) {
    val state by viewModel.state.collectAsState()
    SignInScreen(
        state = state,
        onSubmitPhone = viewModel::submitPhone,
        onSubmitCode = viewModel::submitCode,
        onResend = viewModel::resend,
        onChangeNumber = viewModel::changeNumber,
        modifier = modifier,
    )
}

@Composable
fun SignInScreen(
    state: SignInUiState,
    modifier: Modifier = Modifier,
    onSubmitPhone: (String) -> Unit = {},
    onSubmitCode: (String) -> Unit = {},
    onResend: () -> Unit = {},
    onChangeNumber: () -> Unit = {},
) {
    Column(modifier = modifier.fillMaxSize()) {
        FindlyTopBar(title = "Sign in")

        Column(
            modifier = Modifier.padding(FindlyTheme.spacing.md),
            verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
        ) {
            when (state) {
                is SignInUiState.EnteringPhone -> {
                    var phone by remember(state) { mutableStateOf(state.phone) }
                    FindlyTextField(
                        value = phone,
                        onValueChange = { phone = it },
                        label = "Phone number",
                        placeholder = "+32470000000",
                        isError = state.error != null,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                    )
                    if (state.error != null) {
                        FindlyErrorState(title = "Couldn't sign in", message = state.error)
                    }
                    FindlyButton(text = "Send code", onClick = { onSubmitPhone(phone) })
                }

                is SignInUiState.SendingCode -> {
                    FindlyLoadingState(message = "Sending code…")
                }

                is SignInUiState.EnteringCode -> {
                    var code by remember(state.phone) { mutableStateOf("") }
                    FindlyTextField(
                        value = code,
                        onValueChange = { code = it },
                        label = "Code sent to ${state.phone}",
                        placeholder = "123456",
                        isError = state.error != null,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    )
                    if (state.error != null) {
                        FindlyErrorState(title = "Couldn't sign in", message = state.error)
                    }
                    FindlyButton(text = "Confirm code", onClick = { onSubmitCode(code) })
                    FindlyButton(
                        text = if (state.resendSecondsLeft > 0) "Resend in ${state.resendSecondsLeft}s" else "Resend code",
                        enabled = state.resendSecondsLeft == 0,
                        style = FindlyButtonStyle.Secondary,
                        onClick = onResend,
                    )
                    FindlyButton(text = "Change number", style = FindlyButtonStyle.Secondary, onClick = onChangeNumber)
                }

                is SignInUiState.ConfirmingCode -> {
                    FindlyLoadingState(message = "Signing in…")
                }
            }
        }
    }
}

@Preview(name = "Sign in — phone entry, light", showBackground = true)
@Composable
private fun SignInScreenPhoneLightPreview() {
    FindlyTheme(darkTheme = false) {
        SignInScreen(state = SignInUiState.EnteringPhone())
    }
}

@Preview(name = "Sign in — code entry, dark", showBackground = true)
@Composable
private fun SignInScreenCodeDarkPreview() {
    FindlyTheme(darkTheme = true) {
        SignInScreen(state = SignInUiState.EnteringCode(phone = "+32470000001", resendSecondsLeft = 12))
    }
}
