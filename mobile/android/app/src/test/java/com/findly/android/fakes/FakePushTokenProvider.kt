package com.findly.android.fakes

import com.findly.android.push.PushTokenProvider
import com.findly.android.push.PushTokenRefreshListener

/** Test fake — mirrors the backend's `test/fakes/` convention (backend/README.md). [currentToken]
 * returns [tokenToReturn] (defaults to `null`, matching the "FCM hasn't produced a token yet"
 * contract `RealPushTokenProvider` documents) and records every call via [currentTokenCallCount].
 * [addRefreshListener] just records the listener — no test in this codebase currently needs to
 * trigger a refresh through the fake, but the seam is here if one does. */
class FakePushTokenProvider(
    var tokenToReturn: String? = null,
) : PushTokenProvider {

    var currentTokenCallCount = 0
        private set

    override suspend fun currentToken(): String? {
        currentTokenCallCount++
        return tokenToReturn
    }

    val listeners = mutableListOf<PushTokenRefreshListener>()

    override fun addRefreshListener(listener: PushTokenRefreshListener) {
        listeners.add(listener)
    }
}
