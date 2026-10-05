package com.findly.android.auth

import kotlinx.coroutines.CancellationException

/**
 * The one way the network layer obtains an ID token (specs/003-android-client.md §6.5, A52): used
 * by `AuthInterceptor` for every request and by `FindlyApiClient`'s forced refresh after
 * `AUTH_TOKEN_EXPIRED` (§6.4), so both sites behave identically.
 *
 * Returns `null` when nobody is signed in. Otherwise either returns a token or throws an
 * [IdTokenException] — nothing else, except coroutine cancellation, which a `suspend` function must
 * not absorb (A42) and which is therefore passed through untouched:
 * - [IdTokenException.UserInvalid] from the provider (Firebase says the user is deleted/disabled):
 *   signs the user out locally, then rethrows. The sign-out happens only if the user who was
 *   signed in when the fetch began is still the signed-in user — a late failure for user A must
 *   never sign out user B who has since signed in — and `signOut` is idempotent, so a burst of
 *   concurrent requests all failing for the same user is harmless.
 * - [IdTokenException.Transient] is rethrown as is: no sign-out, the session may be fine.
 * - any other `Exception` from a provider is treated as transient and wrapped, so a provider that
 *   forgot to map an SDK exception can never leak a non-`IOException` toward OkHttp.
 */
suspend fun AuthProvider.idTokenOrThrow(forceRefresh: Boolean = false): String? {
    val uidAtStart = (authState.value as? AuthState.SignedIn)?.uid
    try {
        return currentIdToken(forceRefresh)
    } catch (e: CancellationException) {
        throw e
    } catch (e: IdTokenException.UserInvalid) {
        if (uidAtStart != null && (authState.value as? AuthState.SignedIn)?.uid == uidAtStart) {
            signOut()
        }
        throw e
    } catch (e: IdTokenException) {
        throw e
    } catch (e: Exception) {
        throw IdTokenException.Transient(e)
    }
}
