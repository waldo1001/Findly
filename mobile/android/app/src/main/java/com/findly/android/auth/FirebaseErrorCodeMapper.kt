package com.findly.android.auth

/**
 * Maps a `FirebaseAuthException.errorCode` string onto the closed 006 §4.2 set.
 *
 * Deliberately a **pure top-level function in its own file**, not a private method on
 * `FirebaseAuthProvider`: the provider needs an initialized `FirebaseApp`/`Context` and so stays an
 * untested adapter (003 §7), which previously left this table — the part that decides what a user
 * actually reads — with no test at all. Nothing here touches a Firebase type; only the code string.
 */
fun phoneAuthErrorForFirebaseCode(errorCode: String?): PhoneAuthError = when (errorCode) {
    "ERROR_QUOTA_EXCEEDED" -> PhoneAuthError.SMS_QUOTA_EXCEEDED
    "ERROR_TOO_MANY_REQUESTS" -> PhoneAuthError.TOO_MANY_REQUESTS
    "ERROR_SESSION_EXPIRED" -> PhoneAuthError.CODE_EXPIRED
    "ERROR_INVALID_VERIFICATION_CODE" -> PhoneAuthError.INVALID_CODE
    "ERROR_INVALID_PHONE_NUMBER" -> PhoneAuthError.INVALID_PHONE_NUMBER
    "ERROR_APP_NOT_AUTHORIZED" -> PhoneAuthError.APP_VERIFICATION_FAILED
    "ERROR_NETWORK_REQUEST_FAILED" -> PhoneAuthError.NETWORK
    // Firebase status 17006 ("SMS unable to be sent until this region enabled by the app
    // developer"), raised when the number's country is outside the §6.3 SMS region allowlist.
    // Firebase reuses this code for "the Phone provider is disabled", but §6.2 makes Phone-enabled
    // a hard project requirement, so in a correctly-provisioned project it always means the region
    // policy. Previously fell through to UNKNOWN — "Couldn't sign in. Try again." — which invites a
    // retry that can never succeed, on the one screen gating the whole app (006 §4.2).
    "ERROR_OPERATION_NOT_ALLOWED" -> PhoneAuthError.REGION_NOT_ALLOWED
    else -> PhoneAuthError.UNKNOWN
}
