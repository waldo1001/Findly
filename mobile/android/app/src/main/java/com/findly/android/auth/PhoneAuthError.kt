package com.findly.android.auth

/**
 * The closed client-side phone sign-in error set (specs/006-phone-auth.md §4.2). Every Firebase
 * SDK failure (and this app's own client-side validation) is mapped onto one of these — raw SDK
 * exception text never reaches a screen; `PhoneAuthUserMessage.kt` maps each case to its fixed v1
 * user-facing message.
 */
enum class PhoneAuthError {
    INVALID_PHONE_NUMBER,
    TOO_MANY_REQUESTS,
    SMS_QUOTA_EXCEEDED,
    REGION_NOT_ALLOWED,
    APP_VERIFICATION_FAILED,
    INVALID_CODE,
    CODE_EXPIRED,
    NETWORK,
    UNKNOWN,
}

/** A phone sign-in failure carrying only the closed [error] set — never the raw SDK/provider
 * message (mirrors the "no raw error text reaches a screen" principle behind [PhoneAuthError]). */
class PhoneAuthException(val error: PhoneAuthError) : Exception(error.name)
