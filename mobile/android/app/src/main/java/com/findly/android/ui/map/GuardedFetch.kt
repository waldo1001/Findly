package com.findly.android.ui.map

import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import kotlinx.coroutines.CancellationException

/**
 * Runs a map roster fetch so that **nothing it throws can escape** (specs/010 §3.6 hardening,
 * row A55): the 30 s timer repeats the `GET` for as long as the map is open, on `viewModelScope`,
 * which has no `CoroutineExceptionHandler` — an uncaught throw from any of those launches kills the
 * process (specs/003 §3.1).
 *
 * `FindlyApiClient` only converts an `IOException` into `ApiResult.Failure`; anything else it lets
 * escape. The realistic one is a `SerializationException` from a 200 with a body that is not the
 * envelope — exactly what a captive-portal Wi-Fi's login page is — which before polling could only
 * hit on a screen entry or a tap, and with polling would hit within 30 s of leaving the map open.
 * Such a throw is reported as a transport-class failure ([ApiError.NetworkFailure]): silent on a
 * periodic refresh (010 §3.6), the error state on a first load or an explicit Refresh.
 *
 * [CancellationException] is rethrown untouched (003 §3.1's cancellation-pass-through rule): the
 * `try` block suspends, so swallowing it would break structured concurrency.
 */
internal suspend fun <T> fetchGuarded(call: suspend () -> ApiResult<T>): ApiResult<T> =
    try {
        call()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        ApiResult.Failure(ApiError.NetworkFailure(e))
    }
