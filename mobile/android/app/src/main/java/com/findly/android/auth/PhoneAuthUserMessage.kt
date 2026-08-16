package com.findly.android.auth

/**
 * Maps every [PhoneAuthError] to its fixed 006-phone-auth.md §4.2 user-facing message — **never**
 * raw Firebase SDK exception text (000 §O8: fixed English v1 copy). Mirrors
 * `network/ApiErrorUserMessage.kt`'s one-place-to-localize convention.
 */
fun PhoneAuthError.userMessage(): String = when (this) {
    PhoneAuthError.INVALID_PHONE_NUMBER -> "That doesn't look like a valid phone number."
    PhoneAuthError.TOO_MANY_REQUESTS -> "Too many attempts. Wait a while and try again."
    PhoneAuthError.SMS_QUOTA_EXCEEDED -> "SMS limit reached for now. Try again later."
    PhoneAuthError.REGION_NOT_ALLOWED -> "Findly can't send a code to that country yet."
    PhoneAuthError.APP_VERIFICATION_FAILED -> "Couldn't verify this device. Update the app and try again."
    PhoneAuthError.INVALID_CODE -> "That code isn't right. Check the SMS and try again."
    PhoneAuthError.CODE_EXPIRED -> "That code expired. Request a new one."
    PhoneAuthError.NETWORK -> "No connection. Check your network and try again."
    PhoneAuthError.UNKNOWN -> "Couldn't sign in. Try again."
}
