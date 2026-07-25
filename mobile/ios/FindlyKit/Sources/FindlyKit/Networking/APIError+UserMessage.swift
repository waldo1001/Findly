import Foundation

/// specs/004-ios-client.md I2 — a stable, user-facing string per §10 error code, shared by every
/// I2 view model's error-state rendering. Mirrors the server's own "`message` is for logs/debugging
/// only" stance (specs/001 §1.3): we never surface the raw server `message` in the UI.
extension APIError {
    public var userFacingMessage: String {
        switch self {
        case .server(let body, _):
            switch body.code {
            case .authMissingToken, .authInvalidToken, .authTokenExpired:
                return "Please sign in again."
            case .authForbidden:
                return "You don't have permission to do that."
            case .trackingPaused:
                return "Tracking is paused for this device."
            case .profileNotFound:
                return "We couldn't find your profile."
            case .familyNotFound:
                return "Family not found."
            case .memberNotFound:
                return "That family member could not be found."
            case .deviceNotFound:
                return "That device could not be found."
            case .locateRequestNotFound:
                return "That locate request could not be found."
            case .groupNotFound:
                return "That group could not be found."
            case .familyAlreadyMember:
                return "You already belong to a family."
            case .geofenceVersionConflict:
                return "Someone else updated the geofences. Refresh and try again."
            case .groupAlreadyMember:
                return "You already belong to that group."
            case .groupFull:
                return "That group is full."
            case .inviteExpired:
                return "That invite code has expired."
            case .locateRequestExpired:
                return "That locate request has expired."
            case .groupExpired:
                return "That group has ended."
            case .inviteInvalid:
                return "That invite code isn't valid."
            case .inviteAlreadyUsed:
                return "That invite code has already been used."
            case .groupCodeInvalid:
                return "That group code isn't valid."
            case .validationFailed:
                return "Please check your input and try again."
            case .locationBatchTooLarge:
                return "Too many locations at once."
            case .limitExceeded:
                return "You've reached a plan limit."
            case .rateLimited:
                return "Too many requests — please wait a moment."
            case .internalError:
                return "Something went wrong. Please try again."
            case .pushDeliveryFailed:
                return "Couldn't reach the device."
            case .unknown:
                return "Something went wrong. Please try again."
            }
        case .notModified:
            return "Nothing new."
        case .transport:
            return "Network error. Please check your connection."
        case .decoding:
            return "Something went wrong. Please try again."
        }
    }

    /// The decoded server error code, if this is a `.server` case — `nil` for transport/decoding
    /// failures. View models branch on this for code-specific UX (e.g. a geofence version conflict
    /// triggers a re-fetch + merge flow rather than a plain error banner).
    public var serverCode: APIErrorCode? {
        if case .server(let body, _) = self { return body.code }
        return nil
    }
}

/// Dispatches any thrown `Error` to a stable user-facing string — `APIError` cases get their
/// specific message; anything else (e.g. `AuthError`, a decoding surprise outside the client) gets
/// a generic fallback. Used by every I2 view model so error handling stays consistent.
func userFacingMessage(for error: Error) -> String {
    (error as? APIError)?.userFacingMessage ?? "Something went wrong. Please try again."
}
