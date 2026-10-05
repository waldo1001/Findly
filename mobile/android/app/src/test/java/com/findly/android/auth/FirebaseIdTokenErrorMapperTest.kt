package com.findly.android.auth

import com.google.firebase.FirebaseNetworkException
import com.google.firebase.FirebaseTooManyRequestsException
import com.google.firebase.auth.FirebaseAuthInvalidUserException
import com.google.firebase.auth.FirebaseAuthRecentLoginRequiredException
import java.io.IOException
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * specs/003-android-client.md §6.5 rule 2: which Firebase failures mean "the user itself is gone"
 * (sign out) and which are merely transient (do nothing). The one test class that constructs
 * Firebase *exception objects* — plain `Throwable`s, no `FirebaseApp`, no `Context` — because the
 * `is FirebaseAuthInvalidUserException` check IS the behaviour under test.
 */
class FirebaseIdTokenErrorMapperTest {

    @Test
    fun `FirebaseAuthInvalidUserException is UserInvalid for every code the SDK uses for it`() {
        // Verified against firebase-auth 24.2.0's status->exception table: 17005, 17011, 17017 and
        // 17021 are the four statuses that construct FirebaseAuthInvalidUserException.
        val codes = listOf(
            "ERROR_USER_DISABLED" to "The user account has been disabled by an administrator.",
            "ERROR_USER_NOT_FOUND" to "There is no user record corresponding to this identifier. The user may have been deleted.",
            "ERROR_INVALID_USER_TOKEN" to "This user's credential isn't valid for this project.",
            "ERROR_USER_TOKEN_EXPIRED" to "The user's credential is no longer valid. The user must sign in again.",
        )
        for ((code, message) in codes) {
            val original = FirebaseAuthInvalidUserException(code, message)

            val mapped = original.toIdTokenException()

            assertTrue("$code must map to UserInvalid, was $mapped", mapped is IdTokenException.UserInvalid)
            assertSame("the SDK exception is kept as the cause for diagnosis", original, mapped.cause)
        }
    }

    @Test
    fun `FirebaseNetworkException is Transient - an offline device is not a deleted user`() {
        val original = FirebaseNetworkException("A network error (such as timeout, interrupted connection or unreachable host) has occurred.")

        val mapped = original.toIdTokenException()

        assertTrue("was $mapped", mapped is IdTokenException.Transient)
        assertSame(original, mapped.cause)
    }

    @Test
    fun `throttling and other Firebase or plain exceptions are Transient`() {
        val others = listOf<Throwable>(
            FirebaseTooManyRequestsException("slow down"),
            FirebaseAuthRecentLoginRequiredException("ERROR_REQUIRES_RECENT_LOGIN", "re-authenticate"),
            IllegalStateException("anything else"),
            IOException("socket reset"),
        )
        for (original in others) {
            val mapped = original.toIdTokenException()

            assertTrue("$original must be Transient, was $mapped", mapped is IdTokenException.Transient)
            assertFalse("$original must never be treated as a dead user", mapped is IdTokenException.UserInvalid)
        }
    }

    @Test
    fun `an exception that is already an IdTokenException is returned as is`() {
        val already = IdTokenException.UserInvalid()

        assertSame(already, already.toIdTokenException())
    }
}
