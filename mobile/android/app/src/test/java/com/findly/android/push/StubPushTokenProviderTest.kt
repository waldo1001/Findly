package com.findly.android.push

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class StubPushTokenProviderTest {

    @Test
    fun `currentToken is always null (no real FCM wired in A1)`() = runTest {
        val provider = StubPushTokenProvider()

        assertNull(provider.currentToken())
    }

    @Test
    fun `simulateTokenRefresh notifies every registered listener`() {
        val provider = StubPushTokenProvider()
        val received = mutableListOf<String>()
        provider.addRefreshListener { token -> received.add(token) }
        provider.addRefreshListener { token -> received.add("second:$token") }

        provider.simulateTokenRefresh("new-token")

        assertEquals(listOf("new-token", "second:new-token"), received)
    }

    @Test
    fun `a listener added after a refresh does not retroactively receive it`() {
        val provider = StubPushTokenProvider()
        provider.simulateTokenRefresh("before-listener")
        val received = mutableListOf<String>()

        provider.addRefreshListener { token -> received.add(token) }

        assertEquals(emptyList<String>(), received)
    }
}
