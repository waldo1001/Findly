package com.findly.android.ui.signin

import com.findly.android.auth.AuthProvider
import com.findly.android.auth.PhoneAuthError
import com.findly.android.auth.PhoneAuthException
import com.findly.android.auth.PhoneNumberNormalizer
import com.findly.android.auth.PhoneVerificationEvent
import com.findly.android.auth.userMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** The two-step phone sign-in screen's state — 006-phone-auth.md §4.1's state machine, verbatim
 * (specs/003-android-client.md §7). Deliberately no `Success` case — on a successful
 * [SignInStateHolder.submitCode] / Android instant-verification `Completed`,
 * [AuthProvider.authState] itself transitions to `SignedIn`, which the caller (`FindlyNavHost`)
 * observes directly. */
sealed interface SignInUiState {
    /** Initial state; also reached whenever verification fails outright and the user must retype
     * or fix the number. [phone] is prefilled `"+32"` (006 §3.3) and otherwise carries the last
     * number the user attempted, so a failure doesn't force them to retype it. */
    data class EnteringPhone(val phone: String = "+32", val error: String? = null) : SignInUiState

    /** Waiting on the provider to start/resend SMS verification for [phone]. */
    data class SendingCode(val phone: String) : SignInUiState

    /** The SMS was sent for [phone]; [resendSecondsLeft] counts down from 30 (006 §4.1). */
    data class EnteringCode(val phone: String, val resendSecondsLeft: Int, val error: String? = null) : SignInUiState

    /** Confirming a submitted code for [phone]. */
    data class ConfirmingCode(val phone: String) : SignInUiState
}

/**
 * The two-step phone sign-in screen's pure state machine (specs/006-phone-auth.md §4.1):
 *
 * ```
 * EnteringPhone --submit(valid)--> SendingCode --code sent--> EnteringCode
 * EnteringCode  --submit code-->   ConfirmingCode --success--> (authState flips to SignedIn)
 * ```
 *
 * Constructor-injected [CoroutineScope] (tests supply `backgroundScope`) — same shape as
 * [com.findly.android.ui.map.MapStateHolder] — so the 30 s resend-cooldown ticker (§4.1) is
 * virtual-time testable, matching [com.findly.android.ui.locate.LocateStateHolder]'s
 * `delay`-based poll-loop convention.
 */
class SignInStateHolder(
    private val authProvider: AuthProvider,
    private val scope: CoroutineScope,
) {
    private val _state = MutableStateFlow<SignInUiState>(SignInUiState.EnteringPhone())
    val state: StateFlow<SignInUiState> = _state.asStateFlow()

    /** The resend cooldown's *live* remaining seconds. Tracked separately from
     * [SignInUiState.EnteringCode.resendSecondsLeft] because it must keep counting (and its value
     * must survive) across a round trip through [SignInUiState.ConfirmingCode], which carries no
     * `resendSecondsLeft` field of its own (006 §4.1: "INVALID_CODE → EnteringCode(phone, error)
     * [stay; cooldown unaffected]"). */
    private var resendSecondsLeft = 0
    private var cooldownJob: Job? = null
    private var verificationJob: Job? = null

    /** Normalizes [rawInput] (006 §3) and, if valid, starts SMS verification; an invalid number is
     * rejected client-side with no provider call (006 §4.1's "invalid → EnteringPhone(error) [no
     * provider call]"). No-op unless currently [SignInUiState.EnteringPhone]. */
    fun submitPhone(rawInput: String) {
        if (_state.value !is SignInUiState.EnteringPhone) return
        val normalized = PhoneNumberNormalizer.normalize(rawInput)
        if (normalized == null) {
            _state.value = SignInUiState.EnteringPhone(
                phone = rawInput,
                error = PhoneAuthError.INVALID_PHONE_NUMBER.userMessage(),
            )
            return
        }
        startVerification(normalized)
    }

    /** Re-invokes verification for the number already on [SignInUiState.EnteringCode] — a resend
     * (006 §4.1) — only once the 30 s cooldown has reached zero. No-op otherwise. */
    fun resend() {
        val current = _state.value
        if (current is SignInUiState.EnteringCode && resendSecondsLeft == 0) {
            startVerification(current.phone)
        }
    }

    /** Confirms [code] for the in-flight verification. No-op unless currently
     * [SignInUiState.EnteringCode]. */
    fun submitCode(code: String) {
        val current = _state.value
        if (current !is SignInUiState.EnteringCode) return
        val phone = current.phone
        _state.value = SignInUiState.ConfirmingCode(phone)
        scope.launch {
            try {
                authProvider.confirmCode(code)
                // authState flips to SignedIn; the caller (FindlyNavHost) observes that directly.
            } catch (e: PhoneAuthException) {
                _state.value = if (e.error == PhoneAuthError.CODE_EXPIRED) {
                    // "must request a new code" (006 §4.1).
                    SignInUiState.EnteringPhone(phone = phone, error = e.error.userMessage())
                } else {
                    // INVALID_CODE and every other confirm-phase error: stay on EnteringCode,
                    // cooldown unaffected.
                    SignInUiState.EnteringCode(phone = phone, resendSecondsLeft = resendSecondsLeft, error = e.error.userMessage())
                }
            }
        }
    }

    /** Returns to phone entry, carrying the current number forward for editing (006 §4.1), and
     * cancels the resend cooldown. No-op unless currently [SignInUiState.EnteringCode]. */
    fun changeNumber() {
        val current = _state.value
        if (current is SignInUiState.EnteringCode) {
            cooldownJob?.cancel()
            resendSecondsLeft = 0
            _state.value = SignInUiState.EnteringPhone(phone = current.phone)
        }
    }

    private fun startVerification(phone: String) {
        _state.value = SignInUiState.SendingCode(phone)
        verificationJob?.cancel()
        verificationJob = scope.launch {
            authProvider.startPhoneVerification(phone).collect { event ->
                when (event) {
                    is PhoneVerificationEvent.CodeSent -> {
                        startCooldown()
                        _state.value = SignInUiState.EnteringCode(phone, resendSecondsLeft)
                    }
                    is PhoneVerificationEvent.Completed -> {
                        // Android instant verification / auto-retrieval (006 §4.3) — authState
                        // has already flipped to SignedIn; nothing further to do here, regardless
                        // of whether this arrives from SendingCode or (later) from EnteringCode.
                    }
                    is PhoneVerificationEvent.Failed -> {
                        _state.value = SignInUiState.EnteringPhone(phone = phone, error = event.error.userMessage())
                    }
                }
            }
        }
    }

    private fun startCooldown() {
        resendSecondsLeft = RESEND_COOLDOWN_SECONDS
        cooldownJob?.cancel()
        cooldownJob = scope.launch {
            while (resendSecondsLeft > 0) {
                delay(1_000)
                resendSecondsLeft--
                val current = _state.value
                if (current is SignInUiState.EnteringCode) {
                    _state.value = current.copy(resendSecondsLeft = resendSecondsLeft)
                }
            }
        }
    }

    private companion object {
        const val RESEND_COOLDOWN_SECONDS = 30
    }
}
