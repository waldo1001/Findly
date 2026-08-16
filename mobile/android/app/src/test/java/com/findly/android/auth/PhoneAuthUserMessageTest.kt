package com.findly.android.auth

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** [PhoneAuthError.userMessage] must return the exact fixed 006-phone-auth.md §4.2 string for
 * every case — never blank, never raw SDK text (mirrors `ApiErrorUserMessageTest`). */
class PhoneAuthUserMessageTest {

    @Test
    fun `every PhoneAuthError maps to its exact 006 par4point2 message`() {
        assertEquals(
            "That doesn't look like a valid phone number.",
            PhoneAuthError.INVALID_PHONE_NUMBER.userMessage(),
        )
        assertEquals(
            "Too many attempts. Wait a while and try again.",
            PhoneAuthError.TOO_MANY_REQUESTS.userMessage(),
        )
        assertEquals(
            "SMS limit reached for now. Try again later.",
            PhoneAuthError.SMS_QUOTA_EXCEEDED.userMessage(),
        )
        assertEquals(
            "Findly can't send a code to that country yet.",
            PhoneAuthError.REGION_NOT_ALLOWED.userMessage(),
        )
        assertEquals(
            "Couldn't verify this device. Update the app and try again.",
            PhoneAuthError.APP_VERIFICATION_FAILED.userMessage(),
        )
        assertEquals(
            "That code isn't right. Check the SMS and try again.",
            PhoneAuthError.INVALID_CODE.userMessage(),
        )
        assertEquals(
            "That code expired. Request a new one.",
            PhoneAuthError.CODE_EXPIRED.userMessage(),
        )
        assertEquals(
            "No connection. Check your network and try again.",
            PhoneAuthError.NETWORK.userMessage(),
        )
        assertEquals(
            "Couldn't sign in. Try again.",
            PhoneAuthError.UNKNOWN.userMessage(),
        )
    }

    @Test
    fun `every PhoneAuthError value produces a distinct, non-blank message`() {
        val messages = PhoneAuthError.entries.map { it.userMessage() }

        messages.forEach { assertTrue(it.isNotBlank()) }
        assertEquals("messages must be pairwise distinct", messages.size, messages.toSet().size)
    }

    @Test
    fun `PhoneAuthException carries only the closed error - never a raw message string`() {
        val exception = PhoneAuthException(PhoneAuthError.INVALID_CODE)

        assertEquals(PhoneAuthError.INVALID_CODE, exception.error)
        assertNotEquals("some raw SDK exception text", exception.message)
    }
}
