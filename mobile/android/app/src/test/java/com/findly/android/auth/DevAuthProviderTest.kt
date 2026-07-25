package com.findly.android.auth

import java.util.Base64
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [DevAuthProvider] implements the two-step phone shape entirely locally (specs/006-phone-auth.md
 * §5: no SMS, no Firebase, dev-mode complete and testable without H2). No real-looking phone
 * number ever appears here — only the fictional `+3247000000x` family
 * (docs/security-review-checklist.md).
 */
class DevAuthProviderTest {

    @Test
    fun `initially signed out with no token`() = runTest {
        val provider = DevAuthProvider(firebaseProjectId = "findly-dev")

        assertEquals(AuthState.SignedOut, provider.authState.value)
        assertNull(provider.currentIdToken())
    }

    @Test
    fun `startPhoneVerification with a valid number emits CodeSent without signing in`() = runTest {
        val provider = DevAuthProvider(firebaseProjectId = "findly-dev")

        val events = provider.startPhoneVerification("+32470000001").toList()

        assertEquals(listOf(PhoneVerificationEvent.CodeSent), events)
        assertEquals(AuthState.SignedOut, provider.authState.value)
    }

    @Test
    fun `startPhoneVerification with an unnormalizable number fails INVALID_PHONE_NUMBER without signing in`() = runTest {
        val provider = DevAuthProvider(firebaseProjectId = "findly-dev")

        val events = provider.startPhoneVerification("not-a-number").toList()

        assertEquals(listOf(PhoneVerificationEvent.Failed(PhoneAuthError.INVALID_PHONE_NUMBER)), events)
        assertEquals(AuthState.SignedOut, provider.authState.value)
    }

    @Test
    fun `confirmCode with any non-blank code signs in with uid equal to the normalized E164 number`() = runTest {
        val provider = DevAuthProvider(firebaseProjectId = "findly-dev", clock = { 1_000L })
        provider.startPhoneVerification("+32470000001").toList()

        provider.confirmCode("123456")

        assertEquals(AuthState.SignedIn("+32470000001"), provider.authState.value)
    }

    @Test
    fun `confirmCode accepts an arbitrary non-blank code, not just 6 digits`() = runTest {
        val provider = DevAuthProvider(firebaseProjectId = "findly-dev")
        provider.startPhoneVerification("+32470000002").toList()

        provider.confirmCode("x")

        assertEquals(AuthState.SignedIn("+32470000002"), provider.authState.value)
    }

    @Test
    fun `confirmCode with a blank code throws PhoneAuthException INVALID_CODE and does not sign in`() = runTest {
        val provider = DevAuthProvider(firebaseProjectId = "findly-dev")
        provider.startPhoneVerification("+32470000001").toList()

        val exception = try {
            provider.confirmCode("   ")
            null
        } catch (e: PhoneAuthException) {
            e
        }

        assertNotNull(exception)
        assertEquals(PhoneAuthError.INVALID_CODE, exception?.error)
        assertEquals(AuthState.SignedOut, provider.authState.value)
    }

    @Test
    fun `confirmCode yields an unsigned JWT-shaped token whose sub is the signed-in uid`() = runTest {
        val provider = DevAuthProvider(firebaseProjectId = "findly-dev", clock = { 1_000L })
        provider.startPhoneVerification("+32470000001").toList()
        provider.confirmCode("123456")

        val token = provider.currentIdToken()
        requireNotNull(token)
        val parts = token.split(".")
        assertEquals(3, parts.size)
        assertTrue("signature segment must be empty (unsigned)", parts[2].isEmpty())

        val decoder = Base64.getUrlDecoder()
        val header = String(decoder.decode(parts[0]))
        val payload = String(decoder.decode(parts[1]))
        assertTrue(header.contains("\"alg\":\"none\""))
        assertTrue(payload.contains("\"sub\":\"+32470000001\""))
        assertTrue(payload.contains("\"iss\":\"https://securetoken.google.com/findly-dev\""))
        assertTrue(payload.contains("\"aud\":\"findly-dev\""))
        assertTrue(payload.contains("\"iat\":1000"))
        assertTrue(payload.contains("\"exp\":4600"))
    }

    @Test
    fun `signOut clears the signed-in state and the token`() = runTest {
        val provider = DevAuthProvider(firebaseProjectId = "findly-dev")
        provider.startPhoneVerification("+32470000001").toList()
        provider.confirmCode("123456")

        provider.signOut()

        assertEquals(AuthState.SignedOut, provider.authState.value)
        assertNull(provider.currentIdToken())
    }

    @Test
    fun `signInDev still signs in directly for tests that don't want the two-step dance`() = runTest {
        val provider = DevAuthProvider(firebaseProjectId = "findly-dev")

        provider.signInDev("uid-123")

        assertEquals(AuthState.SignedIn("uid-123"), provider.authState.value)
        assertNotNull(provider.currentIdToken())
    }

    @Test
    fun `no literal token constant appears — construction is entirely dynamic`() = runTest {
        // This test intentionally asserts behavior only (see the test bodies above); the
        // requirement it documents is structural (no literal JWT string anywhere in source),
        // enforced by code review / the security-review secret scan, not by an assertion here.
        val providerA = DevAuthProvider(firebaseProjectId = "findly-dev", clock = { 1L })
        val providerB = DevAuthProvider(firebaseProjectId = "findly-dev", clock = { 2L })
        providerA.signInDev("+32470000001")
        providerB.signInDev("+32470000001")

        assertTrue(providerA.currentIdToken() != providerB.currentIdToken())
    }
}
