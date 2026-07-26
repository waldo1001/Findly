package com.findly.android.push

import org.junit.Assert.assertEquals
import org.junit.Test

/** [RealPushTokenProvider]'s listener bookkeeping is pure and unit-tested here, mirroring
 * `StubPushTokenProviderTest` exactly (specs/003-android-client.md §9). Its `currentToken()`
 * Task-bridging is thin, untested Android/Play-Services glue by design (same category as
 * [com.findly.android.auth.FirebaseAuthProvider]) — the `firebaseMessaging` lambda below is never
 * invoked by these tests, so no real `FirebaseMessaging`/`FirebaseApp` needs to exist. */
class RealPushTokenProviderTest {

    private fun provider() = RealPushTokenProvider(
        firebaseMessaging = { error("not exercised by listener-bookkeeping tests") },
    )

    @Test
    fun `notifyTokenRefreshed notifies every registered listener`() {
        val provider = provider()
        val received = mutableListOf<String>()
        provider.addRefreshListener { token -> received.add(token) }
        provider.addRefreshListener { token -> received.add("second:$token") }

        provider.notifyTokenRefreshed("new-token")

        assertEquals(listOf("new-token", "second:new-token"), received)
    }

    @Test
    fun `a listener added after a refresh does not retroactively receive it`() {
        val provider = provider()
        provider.notifyTokenRefreshed("before-listener")
        val received = mutableListOf<String>()

        provider.addRefreshListener { token -> received.add(token) }

        assertEquals(emptyList<String>(), received)
    }
}
