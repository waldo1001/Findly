package com.findly.android.ui.signin

import com.findly.android.auth.AuthState
import com.findly.android.auth.PhoneAuthError
import com.findly.android.auth.PhoneAuthException
import com.findly.android.auth.PhoneVerificationEvent
import com.findly.android.fakes.FakeAuthProvider
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [SignInStateHolder] implements 006-phone-auth.md §4.1's state machine verbatim — tested with
 * [FakeAuthProvider] and `kotlinx-coroutines-test` virtual time (specs/003-android-client.md §7,
 * §14, §16), same `backgroundScope` pattern as `MapStateHolderTest`/`LocateStateHolderTest`. No
 * real-looking phone number ever appears here — only the fictional `+3247000000x` family
 * (docs/security-review-checklist.md).
 */
class SignInStateHolderTest {

    @Test
    fun `initial state is EnteringPhone, prefilled with plus32 and no error`() = runTest {
        val holder = SignInStateHolder(FakeAuthProvider(initialState = AuthState.SignedOut), backgroundScope)

        assertEquals(SignInUiState.EnteringPhone(phone = "+32", error = null), holder.state.value)
    }

    @Test
    fun `submitting an invalid number is rejected client-side without calling the authProvider`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedOut)
        val holder = SignInStateHolder(authProvider, backgroundScope)

        holder.submitPhone("not-a-number")

        assertEquals(
            SignInUiState.EnteringPhone(phone = "not-a-number", error = "That doesn't look like a valid phone number."),
            holder.state.value,
        )
        assertEquals(0, authProvider.startPhoneVerificationCalls.size)
    }

    @Test
    fun `submitting a valid number normalizes it, moves to SendingCode, then EnteringCode once the code is sent`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedOut)
        val holder = SignInStateHolder(authProvider, backgroundScope)

        holder.submitPhone("0470000001")

        // The transition to SendingCode happens synchronously (before the provider is ever
        // called) — the provider call itself is dispatched, so it only actually runs once pumped.
        assertEquals(SignInUiState.SendingCode("+32470000001"), holder.state.value)
        assertEquals(0, authProvider.startPhoneVerificationCalls.size)

        runCurrent()

        assertEquals(listOf("+32470000001"), authProvider.startPhoneVerificationCalls)
        assertEquals(SignInUiState.EnteringCode("+32470000001", resendSecondsLeft = 30), holder.state.value)
    }

    @Test
    fun `a send-phase failure returns to EnteringPhone with the mapped message, phone preserved`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedOut).apply {
            verificationEventsOnStart = listOf(PhoneVerificationEvent.Failed(PhoneAuthError.TOO_MANY_REQUESTS))
        }
        val holder = SignInStateHolder(authProvider, backgroundScope)

        holder.submitPhone("+32470000001")
        runCurrent()

        assertEquals(
            SignInUiState.EnteringPhone(phone = "+32470000001", error = "Too many attempts. Wait a while and try again."),
            holder.state.value,
        )
    }

    @Test
    fun `Android instant verification completing from SendingCode signs in without ever reaching EnteringCode`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedOut).apply {
            verificationEventsOnStart = listOf(PhoneVerificationEvent.Completed)
        }
        val holder = SignInStateHolder(authProvider, backgroundScope)

        holder.submitPhone("+32470000001")
        runCurrent()

        assertTrue(authProvider.authState.value is AuthState.SignedIn)
        assertTrue("never reached EnteringCode", holder.state.value !is SignInUiState.EnteringCode)
    }

    @Test
    fun `Android instant verification completing after EnteringCode signs in without a submitted code`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedOut)
        val holder = SignInStateHolder(authProvider, backgroundScope)

        holder.submitPhone("+32470000001")
        runCurrent()
        assertTrue(holder.state.value is SignInUiState.EnteringCode)
        assertTrue(authProvider.authState.value is AuthState.SignedOut)

        authProvider.emitVerificationEvent(PhoneVerificationEvent.Completed)
        runCurrent()

        assertTrue(authProvider.authState.value is AuthState.SignedIn)
    }

    @Test
    fun `submitCode moves to ConfirmingCode then signs in on success`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedOut)
        val holder = SignInStateHolder(authProvider, backgroundScope)
        holder.submitPhone("+32470000001")
        runCurrent()

        holder.submitCode("123456")

        assertEquals(SignInUiState.ConfirmingCode("+32470000001"), holder.state.value)

        runCurrent()

        assertEquals(listOf("123456"), authProvider.confirmCodeCalls)
        assertTrue(authProvider.authState.value is AuthState.SignedIn)
    }

    @Test
    fun `submitCode ignored unless currently EnteringCode`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedOut)
        val holder = SignInStateHolder(authProvider, backgroundScope)

        holder.submitCode("123456")

        assertEquals(SignInUiState.EnteringPhone(), holder.state.value)
        assertEquals(0, authProvider.confirmCodeCalls.size)
    }

    @Test
    fun `INVALID_CODE stays on EnteringCode with the mapped message and the cooldown is unaffected`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedOut)
        val holder = SignInStateHolder(authProvider, backgroundScope)
        holder.submitPhone("+32470000001")
        runCurrent()
        advanceTimeBy(5_000); runCurrent()
        assertEquals(25, (holder.state.value as SignInUiState.EnteringCode).resendSecondsLeft)

        authProvider.confirmCodeResult = Result.failure(PhoneAuthException(PhoneAuthError.INVALID_CODE))
        holder.submitCode("000000")
        runCurrent()

        val state = holder.state.value
        assertTrue(state is SignInUiState.EnteringCode)
        state as SignInUiState.EnteringCode
        assertEquals("That code isn't right. Check the SMS and try again.", state.error)
        assertEquals("cooldown must be unaffected by a failed confirm", 25, state.resendSecondsLeft)
    }

    @Test
    fun `CODE_EXPIRED returns to EnteringPhone requiring a new code`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedOut)
        val holder = SignInStateHolder(authProvider, backgroundScope)
        holder.submitPhone("+32470000001")
        runCurrent()

        authProvider.confirmCodeResult = Result.failure(PhoneAuthException(PhoneAuthError.CODE_EXPIRED))
        holder.submitCode("000000")
        runCurrent()

        assertEquals(
            SignInUiState.EnteringPhone(phone = "+32470000001", error = "That code expired. Request a new one."),
            holder.state.value,
        )
    }

    @Test
    fun `any other confirm error also stays on EnteringCode`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedOut)
        val holder = SignInStateHolder(authProvider, backgroundScope)
        holder.submitPhone("+32470000001")
        runCurrent()

        authProvider.confirmCodeResult = Result.failure(PhoneAuthException(PhoneAuthError.NETWORK))
        holder.submitCode("000000")
        runCurrent()

        val state = holder.state.value
        assertTrue(state is SignInUiState.EnteringCode)
        assertEquals("No connection. Check your network and try again.", (state as SignInUiState.EnteringCode).error)
    }

    @Test
    fun `resend is blocked before the 30s cooldown reaches zero`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedOut)
        val holder = SignInStateHolder(authProvider, backgroundScope)
        holder.submitPhone("+32470000001")
        runCurrent()
        authProvider.startPhoneVerificationCalls.clear()

        holder.resend()
        runCurrent()

        assertEquals(0, authProvider.startPhoneVerificationCalls.size)
        assertEquals(30, (holder.state.value as SignInUiState.EnteringCode).resendSecondsLeft)
    }

    @Test
    fun `resend re-invokes start-verification exactly once with the same number once the cooldown reaches zero`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedOut)
        val holder = SignInStateHolder(authProvider, backgroundScope)
        holder.submitPhone("+32470000001")
        runCurrent()
        advanceTimeBy(30_000); runCurrent()
        assertEquals(0, (holder.state.value as SignInUiState.EnteringCode).resendSecondsLeft)
        authProvider.startPhoneVerificationCalls.clear()

        holder.resend()
        runCurrent()

        assertEquals(listOf("+32470000001"), authProvider.startPhoneVerificationCalls)
        assertEquals(SignInUiState.EnteringCode("+32470000001", resendSecondsLeft = 30), holder.state.value)
    }

    @Test
    fun `changeNumber returns to EnteringPhone carrying the number forward`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedOut)
        val holder = SignInStateHolder(authProvider, backgroundScope)
        holder.submitPhone("+32470000001")
        runCurrent()

        holder.changeNumber()

        assertEquals(SignInUiState.EnteringPhone(phone = "+32470000001", error = null), holder.state.value)
    }

    @Test
    fun `changeNumber ignored unless currently EnteringCode`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedOut)
        val holder = SignInStateHolder(authProvider, backgroundScope)

        holder.changeNumber()

        assertEquals(SignInUiState.EnteringPhone(), holder.state.value)
    }

    @Test
    fun `the cooldown ticks down one second at a time under virtual time`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedOut)
        val holder = SignInStateHolder(authProvider, backgroundScope)
        holder.submitPhone("+32470000001")
        runCurrent()

        advanceTimeBy(1_000); runCurrent()
        assertEquals(29, (holder.state.value as SignInUiState.EnteringCode).resendSecondsLeft)

        advanceTimeBy(1_000); runCurrent()
        assertEquals(28, (holder.state.value as SignInUiState.EnteringCode).resendSecondsLeft)
    }
}
