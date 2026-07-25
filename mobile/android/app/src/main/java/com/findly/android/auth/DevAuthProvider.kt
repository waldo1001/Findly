package com.findly.android.auth

import java.nio.charset.StandardCharsets
import java.util.Base64
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flow

/**
 * Dev/stub [AuthProvider] (specs/006-phone-auth.md §5, specs/003-android-client.md §7), active
 * when `BuildConfig.AUTH_MODE == "insecure-local"`. Implements the same two-step phone shape as
 * [FirebaseAuthProvider] entirely locally — no SMS, no Firebase — so the phone sign-in UI is
 * fully exercisable and testable without the Firebase console phone-auth setup (H2):
 * `startPhoneVerification` validates the normalized number (§3) and immediately reports code-sent;
 * `confirmCode` accepts **any non-blank code** and signs in with `uid = <normalized E.164 number>`
 * (the phone-shaped analogue of the previous "uid = email" dev shortcut).
 *
 * Keeps an in-memory signed-in dev user and constructs an **unsigned** JWT-shaped bearer token at
 * call time — matching 001-api-contract.md §2.3's "Firebase Auth emulator / hand-crafted JWTs"
 * local-dev shape (the backend's `AUTH_MODE=insecure-local` trusts `sub` as-is, no signature
 * check). No literal token string is embedded anywhere in source or tests — only this
 * construction code — so nothing here can be mistaken for a real credential by a secret scan.
 *
 * `java.util.Base64` (JDK standard library, natively available since API 26 — this project's
 * exact `minSdk`) is used rather than the still-evolving `kotlin.io.encoding.Base64` stdlib API,
 * to avoid any doubt about that API's experimental/stable status at the pinned Kotlin version
 * with no toolchain available here to check.
 *
 * NOT for production use — see [FirebaseAuthProvider] for the real implementation.
 */
class DevAuthProvider(
    private val firebaseProjectId: String,
    private val clock: () -> Long = { System.currentTimeMillis() / 1000 },
    initialUid: String? = null,
) : AuthProvider {

    private val state = MutableStateFlow<AuthState>(
        if (initialUid != null) AuthState.SignedIn(initialUid) else AuthState.SignedOut,
    )
    override val authState: StateFlow<AuthState> = state.asStateFlow()

    /** The in-flight verification's normalized number (006 §4.1's provider-internal session
     * state) — set by the last [startPhoneVerification] call that passed §3 validation. */
    private var pendingPhoneNumber: String? = null

    /** Dev-only helper — signs in a fake uid directly, without the two-step dance (specs/006 §5:
     * "`signInDev(uid)` stays for tests"). */
    fun signInDev(uid: String) {
        state.value = AuthState.SignedIn(uid)
    }

    override suspend fun currentIdToken(forceRefresh: Boolean): String? {
        val current = state.value
        if (current !is AuthState.SignedIn) return null
        return buildUnsignedJwt(current.uid)
    }

    override suspend fun signOut() {
        state.value = AuthState.SignedOut
        pendingPhoneNumber = null
    }

    /** Dev/stub shape (specs/008-privacy-endpoints.md §1.3): there is no real Firebase user to
     * delete here, so this just signs the in-memory dev session out and reports success — always
     * `true`, matching a real deletion's happy path so the delete-account flow is exercisable
     * against `AUTH_MODE=insecure-local` without the Firebase console setup (H2). */
    override suspend fun deleteCurrentUser(): Boolean {
        state.value = AuthState.SignedOut
        pendingPhoneNumber = null
        return true
    }

    /** Dev-mode two-step shape (006 §5): re-validates [phoneNumberE164] against §3 (defensive —
     * callers are expected to already have normalized it) and immediately emits `CodeSent`; no
     * SMS, no Firebase. An unnormalizable number fails client-side with `INVALID_PHONE_NUMBER`
     * and never "sends" anything. */
    override fun startPhoneVerification(phoneNumberE164: String): Flow<PhoneVerificationEvent> = flow {
        val normalized = PhoneNumberNormalizer.normalize(phoneNumberE164)
        if (normalized == null) {
            emit(PhoneVerificationEvent.Failed(PhoneAuthError.INVALID_PHONE_NUMBER))
            return@flow
        }
        pendingPhoneNumber = normalized
        emit(PhoneVerificationEvent.CodeSent)
    }

    /** Dev-mode shortcut (006 §5): any non-blank [code] signs in with `uid` = the normalized
     * E.164 number from the last [startPhoneVerification] call — no real credential exchange. */
    override suspend fun confirmCode(code: String) {
        if (code.isBlank()) {
            throw PhoneAuthException(PhoneAuthError.INVALID_CODE)
        }
        val uid = pendingPhoneNumber ?: throw PhoneAuthException(PhoneAuthError.CODE_EXPIRED)
        state.value = AuthState.SignedIn(uid)
    }

    private fun buildUnsignedJwt(uid: String): String {
        val nowSeconds = clock()
        val header = "{\"alg\":\"none\",\"typ\":\"JWT\"}"
        val payload = "{\"iss\":\"https://securetoken.google.com/$firebaseProjectId\"," +
            "\"aud\":\"$firebaseProjectId\",\"sub\":\"$uid\",\"iat\":$nowSeconds,\"exp\":${nowSeconds + 3600}}"
        val encoder = Base64.getUrlEncoder().withoutPadding()
        val encodedHeader = encoder.encodeToString(header.toByteArray(StandardCharsets.UTF_8))
        val encodedPayload = encoder.encodeToString(payload.toByteArray(StandardCharsets.UTF_8))
        // Unsigned: the signature segment is intentionally empty (001 §2.3's "unsigned tokens").
        return "$encodedHeader.$encodedPayload."
    }
}
