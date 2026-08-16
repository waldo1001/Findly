package com.findly.android.auth

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * [phoneAuthErrorForFirebaseCode] is the pure half of `FirebaseAuthProvider`'s error mapping,
 * extracted so the 006 §4.2 table is testable on the JVM — the provider itself needs a real
 * `FirebaseApp`/`Context` and stays an untested adapter (003 §7).
 */
class FirebaseErrorCodeMapperTest {

    @Test
    fun `region-blocked SMS maps to REGION_NOT_ALLOWED, never UNKNOWN`() {
        // Firebase status 17006. Reproduced on a device 2026-08-16 with a number outside the
        // §6.3 allowlist: "SMS unable to be sent until this region enabled by the app developer."
        assertEquals(
            PhoneAuthError.REGION_NOT_ALLOWED,
            phoneAuthErrorForFirebaseCode("ERROR_OPERATION_NOT_ALLOWED"),
        )
    }

    @Test
    fun `every mapped Firebase code keeps its 006 par4point2 error`() {
        assertEquals(PhoneAuthError.SMS_QUOTA_EXCEEDED, phoneAuthErrorForFirebaseCode("ERROR_QUOTA_EXCEEDED"))
        assertEquals(PhoneAuthError.TOO_MANY_REQUESTS, phoneAuthErrorForFirebaseCode("ERROR_TOO_MANY_REQUESTS"))
        assertEquals(PhoneAuthError.CODE_EXPIRED, phoneAuthErrorForFirebaseCode("ERROR_SESSION_EXPIRED"))
        assertEquals(PhoneAuthError.INVALID_CODE, phoneAuthErrorForFirebaseCode("ERROR_INVALID_VERIFICATION_CODE"))
        assertEquals(PhoneAuthError.INVALID_PHONE_NUMBER, phoneAuthErrorForFirebaseCode("ERROR_INVALID_PHONE_NUMBER"))
        assertEquals(PhoneAuthError.APP_VERIFICATION_FAILED, phoneAuthErrorForFirebaseCode("ERROR_APP_NOT_AUTHORIZED"))
        assertEquals(PhoneAuthError.NETWORK, phoneAuthErrorForFirebaseCode("ERROR_NETWORK_REQUEST_FAILED"))
    }

    @Test
    fun `an unrecognised or absent code falls back to UNKNOWN`() {
        assertEquals(PhoneAuthError.UNKNOWN, phoneAuthErrorForFirebaseCode("ERROR_SOMETHING_NEW"))
        assertEquals(PhoneAuthError.UNKNOWN, phoneAuthErrorForFirebaseCode(null))
        assertEquals(PhoneAuthError.UNKNOWN, phoneAuthErrorForFirebaseCode(""))
    }
}
