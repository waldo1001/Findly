package com.findly.android.auth

import java.io.IOException

/**
 * Why [AuthProvider.currentIdToken] could not produce a token (specs/003-android-client.md §6.5,
 * A52). The only failure type that interface may throw — no Firebase type ever crosses it — and an
 * [IOException] on purpose: OkHttp 4.12's `RealCall.AsyncCall.run` delivers only an `IOException`
 * to a call's callback and rethrows anything else on its dispatcher thread, where Android's default
 * handler kills the process (the deleted-user crash that motivated §6.5). Being an `IOException`
 * means that even an instance that reached OkHttp by some route this code did not anticipate is
 * reported as a failed call instead.
 */
sealed class IdTokenException(message: String, cause: Throwable?) : IOException(message, cause) {

    /**
     * Firebase reports the **user itself** is invalid — deleted, disabled, or its credentials
     * revoked (`FirebaseAuthInvalidUserException`). The session cannot recover: [idTokenOrThrow]
     * signs the user out locally, and the request surfaces as a confirmed auth failure (§6.5 rule 3).
     */
    class UserInvalid(cause: Throwable? = null) :
        IdTokenException("the signed-in user is no longer valid", cause)

    /**
     * Any other failure — no network, throttling, an SDK-internal error. The session may be perfectly
     * valid, so nothing is signed out (§6.5 rule 4).
     */
    class Transient(cause: Throwable? = null) :
        IdTokenException("the ID token could not be obtained", cause)
}
