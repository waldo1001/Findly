package com.findly.android.applock

import android.content.Context
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * The real [AppLockAuthenticator] (specs/010 section 1.4): `androidx.biometric.BiometricPrompt`
 * with `BIOMETRIC_WEAK or DEVICE_CREDENTIAL` - the one combination supported on every API level the
 * app runs on. This is an app gate, not a crypto operation (no CryptoObject), so WEAK is adequate.
 * [activityProvider] yields the current foreground `FragmentActivity`; with none, the attempt
 * fails (the lock stays up). Not unit-tested - it is the thin platform seam.
 */
class BiometricAppLockAuthenticator(
    private val context: Context,
    private val activityProvider: () -> FragmentActivity?,
) : AppLockAuthenticator {

    override fun canAuthenticate(): Boolean =
        BiometricManager.from(context).canAuthenticate(AUTHENTICATORS) == BiometricManager.BIOMETRIC_SUCCESS

    override suspend fun authenticate(): AuthOutcome {
        val activity = activityProvider() ?: return AuthOutcome.Failed
        return suspendCancellableCoroutine { cont ->
            val prompt = BiometricPrompt(
                activity,
                ContextCompat.getMainExecutor(activity),
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                        if (cont.isActive) cont.resume(AuthOutcome.Success)
                    }

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        val cancelled = errorCode == BiometricPrompt.ERROR_USER_CANCELED ||
                            errorCode == BiometricPrompt.ERROR_NEGATIVE_BUTTON ||
                            errorCode == BiometricPrompt.ERROR_CANCELED
                        if (cont.isActive) cont.resume(if (cancelled) AuthOutcome.Cancelled else AuthOutcome.Failed)
                    }
                    // onAuthenticationFailed (one bad attempt): the prompt stays up; the OS applies
                    // its own retry limits, so nothing to do here.
                },
            )
            val info = BiometricPrompt.PromptInfo.Builder()
                .setTitle("Unlock Findly")
                .setAllowedAuthenticators(AUTHENTICATORS)
                .build()
            prompt.authenticate(info)
            cont.invokeOnCancellation { prompt.cancelAuthentication() }
        }
    }

    private companion object {
        const val AUTHENTICATORS = BIOMETRIC_WEAK or DEVICE_CREDENTIAL
    }
}
