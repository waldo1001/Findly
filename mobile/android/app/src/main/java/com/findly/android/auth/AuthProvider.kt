package com.findly.android.auth

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow

/**
 * Abstraction over the phone-number Firebase Auth ID-token source (specs/006-phone-auth.md,
 * specs/003-android-client.md §7). [FirebaseAuthProvider] is the real implementation (H2-wired:
 * on-device SMS verification needs the Firebase console phone-auth setup); [DevAuthProvider] is
 * the dev/stub implementation used when `BuildConfig.AUTH_MODE == "insecure-local"`.
 *
 * Pure Kotlin/JVM — no `android.*` import — unit-testable without an emulator. The former
 * email/password shape (`signIn(email, password)`, `AuthSignInException`) is deleted entirely —
 * phone-number sign-in (SMS one-time code) is the only way into the app (006 §1).
 */
interface AuthProvider {
    val authState: StateFlow<AuthState>

    /**
     * The current Firebase ID token, or `null` if signed out. [forceRefresh] is used by
     * `network/FindlyApiClient.kt`'s retry-once-on-`AUTH_TOKEN_EXPIRED` path (001-api-contract.md
     * §2.1/§6.4) — it is NOT the push-token refresh mechanism (see `push/PushTokenProvider.kt`
     * and specs/003 §7 for why the two are distinct).
     */
    suspend fun currentIdToken(forceRefresh: Boolean = false): String?

    suspend fun signOut()

    /**
     * Starts SMS verification for [phoneNumberE164] (already normalized per 006 §3 —
     * `PhoneNumberNormalizer`; this function never re-rejects malformed input, callers MUST
     * normalize first). Calling this again with the **same number** while a verification is
     * already in flight is a resend — the provider reuses its internal resend token internally;
     * that session state (`verificationId`, `ForceResendingToken`) is provider-internal and MUST
     * NOT cross this interface (006 §4.1).
     */
    fun startPhoneVerification(phoneNumberE164: String): Flow<PhoneVerificationEvent>

    /**
     * Confirms the SMS code for the provider-tracked in-flight verification. On success,
     * [authState] flips to [AuthState.SignedIn] — callers (e.g. `FindlyNavHost`) observe that
     * directly rather than relying on this function's return. Throws [PhoneAuthException] on
     * failure.
     */
    suspend fun confirmCode(code: String)
}

/** The closed 006 §4.1 sign-in-flow event set emitted by [AuthProvider.startPhoneVerification]. */
sealed interface PhoneVerificationEvent {
    /** The SMS was sent; the caller should move to code entry. */
    data object CodeSent : PhoneVerificationEvent

    /** Android-only instant verification / SMS auto-retrieval (006 §4.3): the provider already
     * completed sign-in without any code being typed — `authState` has already flipped to
     * `SignedIn` by the time this is emitted. May arrive while still `SendingCode` **or** after
     * already reaching `EnteringCode` (both are mandatory transitions, 006 §4.1). */
    data object Completed : PhoneVerificationEvent

    data class Failed(val error: PhoneAuthError) : PhoneVerificationEvent
}
