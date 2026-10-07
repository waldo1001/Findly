package com.findly.android.auth

import com.google.firebase.auth.FirebaseAuthInvalidUserException

/**
 * Maps whatever the Firebase SDK threw while fetching an ID token onto the closed
 * [IdTokenException] pair (specs/003-android-client.md §6.5 rule 2).
 *
 * Only [FirebaseAuthInvalidUserException] means the *user itself* is gone — the SDK raises it for
 * exactly four statuses (firebase-auth 24.2.0: `ERROR_USER_DISABLED`, `ERROR_USER_NOT_FOUND`,
 * `ERROR_INVALID_USER_TOKEN`, `ERROR_USER_TOKEN_EXPIRED`), all of which are unrecoverable without
 * signing in again. Everything else — `FirebaseNetworkException` (expired token while offline),
 * throttling, any SDK-internal failure — is [IdTokenException.Transient]: signing a user out on a
 * guess would be far worse than one failed request.
 *
 * A **pure top-level function in its own file**, not a private method on [FirebaseAuthProvider]:
 * the provider needs an initialized `FirebaseApp`/`Context` and so stays an untested adapter
 * (003 §7), which would leave this — the line that decides whether a user is signed out — with no
 * test at all (same reasoning as [phoneAuthErrorForFirebaseCode]).
 */
fun Throwable.toIdTokenException(): IdTokenException = when (this) {
    is IdTokenException -> this
    is FirebaseAuthInvalidUserException -> IdTokenException.UserInvalid(this)
    else -> IdTokenException.Transient(this)
}
