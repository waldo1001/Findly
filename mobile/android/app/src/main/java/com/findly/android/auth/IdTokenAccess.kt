package com.findly.android.auth

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/**
 * The one way the network layer obtains an ID token (specs/003-android-client.md §6.5, A52): used
 * by `AuthInterceptor` for every request and by `FindlyApiClient`'s forced refresh after
 * `AUTH_TOKEN_EXPIRED` (§6.4), so both sites behave identically.
 *
 * Returns `null` when nobody is signed in. Otherwise either returns a token or throws an
 * [IdTokenException] — nothing else, except the **calling coroutine's own cancellation**, which a
 * `suspend` function must not absorb (A42) and which is therefore passed through:
 * - [IdTokenException.UserInvalid] from the provider (Firebase says the user is deleted/disabled):
 *   signs the user out locally, then rethrows. The sign-out happens only if the user who was
 *   signed in when the fetch began is still the signed-in user — a late failure for user A must
 *   never sign out user B who has since signed in — and `signOut` is idempotent, so a burst of
 *   concurrent requests all failing for the same user is harmless.
 * - [IdTokenException.Transient] is rethrown as is: no sign-out, the session may be fine.
 * - any other `Exception` from a provider is treated as transient and wrapped, so a provider that
 *   forgot to map an SDK exception can never leak a non-`IOException` toward OkHttp.
 * - a `CancellationException` is the caller's cancellation **only if the calling coroutine is
 *   actually cancelled** ([ensureActive] rethrows it then). Otherwise it is foreign — a cancelled
 *   Play-services `Task` — and is just a failed fetch, hence [IdTokenException.Transient]:
 *   propagating it would silently end a caller nobody cancelled (e.g. the launch gate's
 *   `authState` collector, through `FindlyApiClient.withAuthRetry`).
 */
suspend fun AuthProvider.idTokenOrThrow(forceRefresh: Boolean = false): String? {
    val uidAtStart = (authState.value as? AuthState.SignedIn)?.uid
    try {
        return currentIdToken(forceRefresh)
    } catch (e: CancellationException) {
        currentCoroutineContext().ensureActive() // the caller's own cancellation: propagate it
        throw IdTokenException.Transient(e) // foreign (e.g. a cancelled Task): a failed fetch
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
