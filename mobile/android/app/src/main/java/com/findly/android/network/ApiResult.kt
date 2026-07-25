package com.findly.android.network

/**
 * The outcome of any [FindlyApiClient] call (specs/003-android-client.md §6.2). `features` is
 * nullable **only** to represent 001-api-contract.md's two documented body-less successes:
 * §3.6's bare `204` and §7.1's bare `304`. Every other endpoint always carries [Features].
 */
sealed class ApiResult<out T> {
    data class Success<T>(val data: T, val features: Features?) : ApiResult<T>()
    data class Failure(val error: ApiError) : ApiResult<Nothing>()
}

/** Wraps a value together with the `ETag` header it was served with (§7.1/§7.2's ETag flow). */
data class ETagged<T>(val value: T, val etag: String)
