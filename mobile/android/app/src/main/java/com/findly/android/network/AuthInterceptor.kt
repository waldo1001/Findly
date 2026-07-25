package com.findly.android.network

import com.findly.android.auth.AuthProvider
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
 */
class AuthInterceptor(private val authProvider: AuthProvider) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val token = runBlocking { authProvider.currentIdToken() }
        val original = chain.request()
        val request = if (token != null) {
            original.newBuilder().header("Authorization", "Bearer $token").build()
        } else {
            original
        }
        return chain.proceed(request)
    }
}
