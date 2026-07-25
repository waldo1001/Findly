import Foundation

/// specs/006-phone-auth.md §4.2 — the fixed v1 English user-facing message per closed error case.
/// Mirrors `APIError.userFacingMessage`'s "raw text never reaches a screen" stance: SDK failures
/// are mapped to `PhoneAuthError` by the provider, and only ever rendered through this mapping.
extension PhoneAuthError {
    public var userMessage: String {
        switch self {
        case .invalidPhoneNumber:
            return "That doesn't look like a valid phone number."
        case .tooManyRequests:
            return "Too many attempts. Wait a while and try again."
        case .smsQuotaExceeded:
            return "SMS limit reached for now. Try again later."
        case .appVerificationFailed:
            return "Couldn't verify this device. Update the app and try again."
        case .invalidCode:
            return "That code isn't right. Check the SMS and try again."
        case .codeExpired:
            return "That code expired. Request a new one."
        case .network:
            return "No connection. Check your network and try again."
        case .unknown:
            return "Couldn't sign in. Try again."
        }
    }
}

/// Dispatches any thrown `Error` to a stable user-facing string — a `PhoneAuthError` gets its
/// specific message; anything else (a provider surprise outside the closed set) gets the generic
/// `.unknown` fallback. Used by `SignInViewModel` so error handling stays consistent.
func phoneAuthUserMessage(for error: Error) -> String {
    (error as? PhoneAuthError)?.userMessage ?? PhoneAuthError.unknown.userMessage
}
