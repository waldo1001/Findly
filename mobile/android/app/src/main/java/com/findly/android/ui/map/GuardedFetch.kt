package com.findly.android.ui.map

import com.findly.android.network.ApiResult

/**
 * RED SKELETON (A55 hardening): passes straight through, so an exception escapes exactly as it did
 * before — the new tests fail on that.
 */
internal suspend fun <T> fetchGuarded(call: suspend () -> ApiResult<T>): ApiResult<T> = call()
