package com.findly.android.fakes

import com.findly.android.auth.AuthProvider
import com.findly.android.auth.AuthState
import com.findly.android.auth.PhoneVerificationEvent
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.consumeAsFlow

/** Test fake — mirrors the backend's `test/fakes/` convention (backend/README.md). */
class FakeAuthProvider(
    initialToken: String? = "fake-token",
    initialState: AuthState = AuthState.SignedIn("uid-test"),
) : AuthProvider {

    private val state = MutableStateFlow(initialState)
    override val authState: StateFlow<AuthState> = state

    var currentToken: String? = initialToken

    /** Set before a test to simulate what a forced refresh yields. */
    var tokenAfterRefresh: String? = null

    var forceRefreshCallCount = 0
        private set

    /** Scripted failure thrown by **every** [currentIdToken] call (specs/003 §6.5) — the real
     * provider throws [com.findly.android.auth.IdTokenException], but tests also script raw
     * non-`IOException`s here to reproduce what an unmapped SDK exception does to OkHttp. */
    var tokenFailure: Throwable? = null

    /** Like [tokenFailure] but only for a **forced** refresh (specs/003 §6.4 + §6.5) — lets the
     * first attempt succeed and the refresh after an `AUTH_TOKEN_EXPIRED` fail. */
    var refreshFailure: Throwable? = null

    /** Runs at the very start of every [currentIdToken] call — lets a test change who is signed in
     * while a token fetch is "in flight". */
    var onTokenFetch: (() -> Unit)? = null

    override suspend fun currentIdToken(forceRefresh: Boolean): String? {
        onTokenFetch?.invoke()
        if (forceRefresh) {
            forceRefreshCallCount++
            refreshFailure?.let { throw it }
            tokenAfterRefresh?.let { currentToken = it }
        }
        tokenFailure?.let { throw it }
        return currentToken
    }

    /** Test seam: flips [authState] directly, as a Firebase `AuthStateListener` would. */
    fun setAuthState(newState: AuthState) {
        state.value = newState
    }

    var signOutCallCount = 0
        private set

    override suspend fun signOut() {
        signOutCallCount++
        state.value = AuthState.SignedOut
    }

    /** Scripted outcome of the next [deleteCurrentUser] call (specs/008-privacy-endpoints.md
     * §1.3) — defaults to success. */
    var deleteCurrentUserResult: Boolean = true
    var deleteCurrentUserCallCount = 0
        private set

    override suspend fun deleteCurrentUser(): Boolean {
        deleteCurrentUserCallCount++
        return deleteCurrentUserResult
    }

    /** Scripted event(s) emitted as soon as the next [startPhoneVerification] call's flow is
     * collected — defaults to a single [PhoneVerificationEvent.CodeSent], mirroring
     * `signInResult`'s "defaults to success" convention. Use [emitVerificationEvent] instead when
     * a test needs a *later*, separately-timed event on the same in-flight verification (e.g.
     * Android instant-verification completion arriving after the collector already moved on to
     * `EnteringCode`, specs/006-phone-auth.md §4.3). */
    var verificationEventsOnStart: List<PhoneVerificationEvent> = listOf(PhoneVerificationEvent.CodeSent)

    val startPhoneVerificationCalls = mutableListOf<String>()

    private var verificationChannel: Channel<PhoneVerificationEvent>? = null
    private var lastPhoneNumber: String = "uid-test"

    override fun startPhoneVerification(phoneNumberE164: String): Flow<PhoneVerificationEvent> {
        startPhoneVerificationCalls.add(phoneNumberE164)
        lastPhoneNumber = phoneNumberE164
        val channel = Channel<PhoneVerificationEvent>(Channel.UNLIMITED)
        verificationChannel = channel
        verificationEventsOnStart.forEach { emitToChannel(channel, it) }
        return channel.consumeAsFlow()
    }

    /** Pushes another event onto the flow returned by the most recent [startPhoneVerification]
     * call — for simulating an event that arrives later than the initial collection (e.g. Android
     * instant-verification completion arriving only after the collector already moved on to
     * `EnteringCode`, specs/006-phone-auth.md §4.3). */
    fun emitVerificationEvent(event: PhoneVerificationEvent) {
        verificationChannel?.let { emitToChannel(it, event) }
    }

    private fun emitToChannel(channel: Channel<PhoneVerificationEvent>, event: PhoneVerificationEvent) {
        if (event is PhoneVerificationEvent.Completed) {
            // Mirrors the real contract (006 §4.3): `authState` has already flipped to `SignedIn`
            // by the time `Completed` is emitted.
            state.value = AuthState.SignedIn(lastPhoneNumber)
        }
        channel.trySend(event)
    }

    /** Scripted outcome of the next [confirmCode] call. Defaults to success, signing in with
     * [signedInUidOnConfirm]. */
    var confirmCodeResult: Result<Unit> = Result.success(Unit)
    var signedInUidOnConfirm: String = "uid-test"

    val confirmCodeCalls = mutableListOf<String>()

    override suspend fun confirmCode(code: String) {
        confirmCodeCalls.add(code)
        confirmCodeResult.onSuccess { state.value = AuthState.SignedIn(signedInUidOnConfirm) }.getOrThrow()
    }
}
