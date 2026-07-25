package com.findly.android.auth

import com.findly.android.fakes.FakeAuthProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class AuthProviderFactoryTest {

    @Test
    fun `InsecureLocal mode yields a DevAuthProvider`() {
        val provider = AuthProviderFactory.create(AuthMode.InsecureLocal, firebaseProjectId = "findly-dev") {
            error("must not be invoked for InsecureLocal")
        }

        assertTrue(provider is DevAuthProvider)
    }

    @Test
    fun `Firebase mode invokes the lazy firebaseAuthProvider supplier`() {
        val fake = FakeAuthProvider()

        val provider = AuthProviderFactory.create(AuthMode.Firebase, firebaseProjectId = "findly-prod") { fake }

        assertTrue(provider === fake)
    }

    @Test
    fun `AuthMode fromBuildConfigValue maps both legal values and rejects anything else`() {
        assertEquals(AuthMode.InsecureLocal, AuthMode.fromBuildConfigValue("insecure-local"))
        assertEquals(AuthMode.Firebase, AuthMode.fromBuildConfigValue("firebase"))
        assertThrows(IllegalStateException::class.java) {
            AuthMode.fromBuildConfigValue("something-else")
        }
    }
}
