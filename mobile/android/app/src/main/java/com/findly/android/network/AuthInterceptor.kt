package com.findly.android.network

import com.findly.android.auth.AuthProvider
import com.findly.android.auth.IdTokenException
import com.findly.android.auth.idTokenOrThrow
import java.io.IOException
import kotlinx.coroutines.runBlocking
import okhttp3.Interceptor
import okhttp3.Response

/**
 * Attaches `Authorization: Bearer <token>` to every request (001-api-contract.md §1.2 — required
 * on every endpoint, no anonymous routes). `X-Device-Id` is deliberately NOT added here: it is
 * only required on the three endpoints 001 §1.2 lists, and is passed explicitly as a Retrofit
 * `@Header` parameter on those methods (`FindlyApiService.kt`) so it can never leak elsewhere.
 *
 * `runBlocking` is used because OkHttp interceptors are synchronous by contract (they already
 * run on a background dispatch thread); this is the standard, documented pattern for bridging a
 * suspend token source into an `Interceptor`.
 *
 * **Only an `IOException` may leave this interceptor** (specs/003 §6.5, A52). OkHttp 4.12's
 * `RealCall.AsyncCall.run` hands a callback only an `IOException`; for any other `Throwable` it
 * reports a synthetic "canceled" `IOException` and then **rethrows the original on its dispatcher
 * thread** — on Android, a process kill, which is how a cached session for a deleted Firebase user
 * crashed the app on every launch. [idTokenOrThrow] already reduces a provider's failure to an
 * [IdTokenException] (an `IOException`) and signs out a deleted/disabled user; the extra catch here
 * contains what that function deliberately does not absorb or cannot foresee (a cancelled
 * Play-services `Task`'s `CancellationException`, an `InterruptedException` out of `runBlocking`).
 * No request is sent when no token can be obtained.
 */
class AuthInterceptor(private val authProvider: AuthProvider) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val token = tokenOrThrowIOException()
        val original = chain.request()
        val request = if (token != null) {
            original.newBuilder().header("Authorization", "Bearer $token").build()
        } else {
            original
        }
        return chain.proceed(request)
    }

    private fun tokenOrThrowIOException(): String? = try {
        runBlocking { authProvider.idTokenOrThrow() }
    } catch (e: IOException) {
        throw e
    } catch (e: Exception) {
        throw IdTokenException.Transient(e)
    }
}
