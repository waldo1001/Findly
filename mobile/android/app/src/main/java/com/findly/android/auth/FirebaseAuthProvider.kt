package com.findly.android.auth

import com.google.firebase.FirebaseException
import com.google.firebase.FirebaseNetworkException
import com.google.firebase.FirebaseTooManyRequestsException
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseAuthException
import com.google.firebase.auth.FirebaseAuthInvalidCredentialsException
import com.google.firebase.auth.FirebaseAuthMissingActivityForRecaptchaException
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.auth.PhoneAuthCredential
import com.google.firebase.auth.PhoneAuthOptions
import com.google.firebase.auth.PhoneAuthProvider
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.channels.trySendBlocking
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await

/**
 * The real [AuthProvider] for `BuildConfig.AUTH_MODE == "firebase"` (specs/006-phone-auth.md,
 * specs/003-android-client.md §7). Constructor-**injects** [firebaseAuth] and
 * [activityProvider] rather than resolving either itself — `FirebaseAuth.getInstance()` needs an
 * initialized `FirebaseApp`/Android `Context`, unavailable in this project's plain-JVM unit tests
 * (no Robolectric) — so this class stays a **thin, untested adapter** (same category as
 * [com.findly.android.device.AndroidDeviceInfoProvider]) while [AuthProviderFactory] and its
 * test remain pure-JVM. Only [com.findly.android.AppContainer] constructs this, with a real
 * `FirebaseAuth.getInstance()` and the app's [CurrentActivityProvider].
 *
 * On-device SMS verification against this class needs the Firebase console phone-auth setup (H2:
 * Blaze plan, Phone provider, SMS region allowlist, App Check) — expected to remain unexercised
 * until then; [DevAuthProvider] is what's actually run/tested locally in the meantime.
 */
class FirebaseAuthProvider(
    private val firebaseAuth: FirebaseAuth,
    private val activityProvider: CurrentActivityProvider,
) : AuthProvider {

    private val _authState = MutableStateFlow(mapUser(firebaseAuth.currentUser))
    override val authState: StateFlow<AuthState> = _authState.asStateFlow()

    /** The in-flight verification's provider-internal session state (006 §4.1) — never crosses
     * the [AuthProvider] interface. [resendToken] lets a same-number resend reuse Firebase's
     * internal throttling/session rather than starting a brand new one. */
    private var verificationId: String? = null
    private var resendToken: PhoneAuthProvider.ForceResendingToken? = null

    init {
        // Held for the app process's lifetime (same as everything else in AppContainer) — never
        // removed, there is no matching "dispose" hook for a singleton composition root.
        firebaseAuth.addAuthStateListener { auth -> _authState.value = mapUser(auth.currentUser) }
    }

    private fun mapUser(user: FirebaseUser?): AuthState =
        if (user != null) AuthState.SignedIn(user.uid) else AuthState.SignedOut

    override suspend fun currentIdToken(forceRefresh: Boolean): String? =
        firebaseAuth.currentUser?.getIdToken(forceRefresh)?.await()?.token

    override suspend fun signOut() {
        firebaseAuth.signOut()
        verificationId = null
        resendToken = null
    }

    /** specs/008-privacy-endpoints.md §1.3 — deletes the signed-in Firebase Auth user. Never
     * throws: a failure (no current user, `requires-recent-login`, network, …) is reported as
     * `false` so [com.findly.android.ui.settings.PrivacyStateHolder] can offer a retry path
     * instead of crashing the delete-account flow. */
    override suspend fun deleteCurrentUser(): Boolean {
        val user = firebaseAuth.currentUser ?: return false
        return try {
            user.delete().await()
            true
        } catch (e: Exception) {
            false
        }
    }

    override fun startPhoneVerification(phoneNumberE164: String): Flow<PhoneVerificationEvent> = callbackFlow {
        val activity = activityProvider.current()
        if (activity == null) {
            // Not realistically reachable — the UI triggered this call — but Firebase's own
            // verification requires an Activity for Play Integrity / reCAPTCHA (specs/003 §7).
            trySendBlocking(PhoneVerificationEvent.Failed(PhoneAuthError.APP_VERIFICATION_FAILED))
            close()
            return@callbackFlow
        }

        val callbacks = object : PhoneAuthProvider.OnVerificationStateChangedCallbacks() {
            override fun onCodeSent(id: String, token: PhoneAuthProvider.ForceResendingToken) {
                verificationId = id
                resendToken = token
                trySendBlocking(PhoneVerificationEvent.CodeSent)
            }

            override fun onVerificationCompleted(credential: PhoneAuthCredential) {
                // Instant verification / SMS auto-retrieval (006 §4.3) — sign in directly.
                firebaseAuth.signInWithCredential(credential)
                    .addOnSuccessListener { trySendBlocking(PhoneVerificationEvent.Completed) }
                    .addOnFailureListener { trySendBlocking(PhoneVerificationEvent.Failed(mapSendError(it))) }
            }

            override fun onVerificationFailed(e: FirebaseException) {
                trySendBlocking(PhoneVerificationEvent.Failed(mapSendError(e)))
            }
        }

        val optionsBuilder = PhoneAuthOptions.newBuilder(firebaseAuth)
            .setPhoneNumber(phoneNumberE164)
            .setTimeout(60L, TimeUnit.SECONDS)
            .setActivity(activity)
            .setCallbacks(callbacks)
        resendToken?.let { optionsBuilder.setForceResendingToken(it) }

        PhoneAuthProvider.verifyPhoneNumber(optionsBuilder.build())

        awaitClose { /* Firebase's SDK has no explicit "stop verifying" call to release here. */ }
    }

    override suspend fun confirmCode(code: String) {
        val id = verificationId ?: throw PhoneAuthException(PhoneAuthError.CODE_EXPIRED)
        try {
            firebaseAuth.signInWithCredential(PhoneAuthProvider.getCredential(id, code)).await()
        } catch (e: Exception) {
            throw PhoneAuthException(mapConfirmError(e))
        }
    }

    /**
     * Maps a send-phase (`onVerificationFailed` / instant-verification sign-in) failure onto the
     * closed 006 §4.2 set. Best-effort: Firebase Auth doesn't expose one distinct exception type
     * per §4.2 row, so the well-documented types are checked first (`FirebaseAuthInvalidCredentialsException`
     * → invalid phone number at send-time; `FirebaseTooManyRequestsException` → throttling;
     * `FirebaseAuthMissingActivityForRecaptchaException` → app verification), then
     * [FirebaseAuthException.errorCode] as a fallback for the rest (SMS quota vs. per-number
     * throttling isn't otherwise distinguishable in the public API) — unverifiable without a
     * device/emulator, called out as a follow-up in the task report.
     */
    private fun mapSendError(e: Exception): PhoneAuthError = when (e) {
        is FirebaseAuthInvalidCredentialsException -> PhoneAuthError.INVALID_PHONE_NUMBER
        is FirebaseAuthMissingActivityForRecaptchaException -> PhoneAuthError.APP_VERIFICATION_FAILED
        is FirebaseTooManyRequestsException -> PhoneAuthError.TOO_MANY_REQUESTS
        is FirebaseNetworkException -> PhoneAuthError.NETWORK
        is FirebaseAuthException -> mapByErrorCode(e.errorCode)
        else -> PhoneAuthError.UNKNOWN
    }

    /** Maps a confirm-phase (`confirmCode`/`signInWithCredential`) failure — `invalid credential`
     * here means a wrong SMS code, not an invalid phone number (see [mapSendError]'s doc). */
    private fun mapConfirmError(e: Exception): PhoneAuthError = when (e) {
        is FirebaseAuthInvalidCredentialsException -> PhoneAuthError.INVALID_CODE
        is FirebaseTooManyRequestsException -> PhoneAuthError.TOO_MANY_REQUESTS
        is FirebaseNetworkException -> PhoneAuthError.NETWORK
        is FirebaseAuthException -> mapByErrorCode(e.errorCode)
        else -> PhoneAuthError.UNKNOWN
    }

    private fun mapByErrorCode(errorCode: String?): PhoneAuthError = when (errorCode) {
        "ERROR_QUOTA_EXCEEDED" -> PhoneAuthError.SMS_QUOTA_EXCEEDED
        "ERROR_TOO_MANY_REQUESTS" -> PhoneAuthError.TOO_MANY_REQUESTS
        "ERROR_SESSION_EXPIRED" -> PhoneAuthError.CODE_EXPIRED
        "ERROR_INVALID_VERIFICATION_CODE" -> PhoneAuthError.INVALID_CODE
        "ERROR_INVALID_PHONE_NUMBER" -> PhoneAuthError.INVALID_PHONE_NUMBER
        "ERROR_APP_NOT_AUTHORIZED" -> PhoneAuthError.APP_VERIFICATION_FAILED
        "ERROR_NETWORK_REQUEST_FAILED" -> PhoneAuthError.NETWORK
        else -> PhoneAuthError.UNKNOWN
    }
}
