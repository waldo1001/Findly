import Foundation

/// specs/001-api-contract.md §1.5.3, §4.1 (I24) — `POST /devices` is NOT one of the four
/// profile-bootstrapping endpoints (`POST /families`, `/invites/accept`, `/groups`,
/// `/groups/join`), so a caller with no `Users` profile row gets `404 PROFILE_NOT_FOUND` from it —
/// whether because they haven't finished onboarding yet (the common case, caught by
/// `registerOrUpdate`'s pre-flight probe) or because their profile was deleted out from under an
/// in-flight session, e.g. a concurrent `DELETE /users/me` from another device (I24 review, Finding
/// 4 — caught only by the real `POST /devices` response, since an established device skips the
/// probe). Both collapse to this ONE case because callers treat them identically: expected, not an
/// error, nothing to retry from here. Thrown instead of letting a call doomed either way propagate
/// as a raw, undifferentiated `APIError`, so callers can tell it apart from a genuine registration
/// failure (network/server error, which propagates as whatever
/// `FindlyAPIClient.registerDevice`/`getMyFamily` itself throws).
public enum DeviceRegistrationError: Error, Equatable {
    case profileNotYetBootstrapped
    /// specs/010-app-shell-and-screen-ux.md §1.1 (amended, row A37; A37 review, Finding 2) — the
    /// pre-flight `GET /families/me` probe (or the real `POST /devices` response itself) came back
    /// with a CONFIRMED `AUTH_MISSING_TOKEN`/`AUTH_INVALID_TOKEN`/`AUTH_TOKEN_EXPIRED`/
    /// `AUTH_FORBIDDEN` (001 §10). Deliberately distinct from [profileNotYetBootstrapped] — this is
    /// not "hasn't onboarded yet", it's "the backend has told us this caller is unauthorized" —
    /// callers must not treat the two as interchangeable.
    case callerUnauthorized
}

/// I24 review (security, Minor) — a curated, log-safe summary of a device-registration failure,
/// used by `FindlyApp`'s `onReRegisterDevice` catch instead of logging the whole `Error`. Projects
/// ONLY `code`/`httpStatus`/`requestId` for a `.server` error (never `message`/`details` — those
/// stay safe today only because of an invariant enforced far away, in
/// `backend/src/http/errors.ts`/`validate.ts`, with nothing at the log call site to catch a future
/// regression there) and a bare category label for anything else (never its associated string, for
/// the same reason). `docs/security-review-checklist.md`: "log IDs and counts, never coordinates,
/// push tokens, or phone numbers" — `code`/`httpStatus`/`requestId` are exactly that.
public func loggableSummary(forDeviceRegistrationFailure error: Error) -> String {
    guard let apiError = error as? APIError else {
        return "non-API error (\(String(describing: type(of: error))))"
    }
    switch apiError {
    case .server(let body, let httpStatus):
        return "server(code: \(body.code.rawValue), httpStatus: \(httpStatus), requestId: \(body.requestId))"
    case .notModified:
        return "notModified"
    case .transport:
        return "transport"
    case .decoding:
        return "decoding"
    }
}

/// specs/004-ios-client.md §5, specs/001 §4.1 — builds and sends device-registration requests.
/// Triggers (MUST, wired by the app target through this type's public API): first launch after
/// sign-in, every push-token refresh (`observePushTokenRefreshes`), and every app update (caller's
/// responsibility to detect and call `registerOrUpdate()` again). Also retried by `RootView`
/// (I24) once any of the four profile-bootstrap paths completes, since a call made before that
/// point is guaranteed to hit `DeviceRegistrationError.profileNotYetBootstrapped` below.
public final class DeviceRegistrationService {
    private let apiClient: FindlyAPIClient
    private let deviceIdProvider: DeviceIdProviding
    private let deviceInfoProvider: DeviceInfoProviding
    private let authProvider: AuthProviding
    // I24 review (Finding 2) — also doubles as the "has this device ever registered successfully
    // for this user" bit `registerOrUpdate` consults below, so no second store was added.
    private let appVersionTracker: AppVersionRegistrationTracking

    /// Remembers the most recently supplied tokens so a call that doesn't supply one (e.g. a
    /// plain app-update re-registration) still resends the last known value — the server itself
    /// also preserves omitted tokens (001 §4.1), but resending what we have keeps this client's
    /// own request self-consistent and avoids relying solely on server-side memory.
    private var lastPushToken: String?
    private var lastLocationPushToken: String?

    public init(
        apiClient: FindlyAPIClient,
        deviceIdProvider: DeviceIdProviding,
        deviceInfoProvider: DeviceInfoProviding,
        authProvider: AuthProviding,
        appVersionTracker: AppVersionRegistrationTracking
    ) {
        self.apiClient = apiClient
        self.deviceIdProvider = deviceIdProvider
        self.deviceInfoProvider = deviceInfoProvider
        self.authProvider = authProvider
        self.appVersionTracker = appVersionTracker
    }

    @discardableResult
    public func registerOrUpdate(
        pushToken: String? = nil,
        locationPushToken: String? = nil,
        deviceName: String? = nil
    ) async throws -> Envelope<DeviceResponse> {
        guard let userId = authProvider.currentUserId else { throw AuthError.notSignedIn }

        // specs/001 §1.5.3 (I24; review Finding 2) — probe for a profile before attempting the
        // doomed POST /devices call, but ONLY when there's no local evidence this device has EVER
        // registered successfully for this user. A prior success proves a profile existed at that
        // point (POST /devices requires one) — for that overwhelmingly common case (an established
        // user's push-token refresh, location-push-token capture, or the DEVICE_NOT_FOUND
        // self-heal), probing on every single call, forever, would be pure waste. `appVersionTracker`
        // already tracks exactly this bit (see the unconditional `setLastRegisteredAppVersion` call
        // on the success path below, which is what keeps it accurate regardless of WHICH trigger
        // last succeeded) — reused rather than adding a second store. A brand-new device/user (no
        // stored version yet) is exactly the case that DOES need the probe. This is a deliberately
        // different condition from CreateGroupViewModel/GroupJoinViewModel's `isBootstrappingProfile`
        // (I17), which probes when `displayName` is blank — that's a proxy specific to those two
        // screens' own optional-field ambiguity, not applicable here.
        let hasRegisteredBefore = appVersionTracker.lastRegisteredAppVersion(forUserId: userId) != nil
        if !hasRegisteredBefore {
            switch await probeProfileState() {
            case .exists:
                break
            case .missing:
                throw DeviceRegistrationError.profileNotYetBootstrapped
            case .confirmedUnauthorized:
                // TODO(A37 RED): deliberately wrong — throws the WRONG typed error, so
                // DeviceRegistrationServiceTests' new assertion (`catch .callerUnauthorized`)
                // fails on a value mismatch rather than a missing symbol (CLAUDE.md "stub wrong,
                // don't stub absent"). `registerDeviceCalls.isEmpty` already passes here, which is
                // exactly why that assertion alone would NOT have caught this bug — the
                // reviewer's point. Fixed in the immediately following GREEN commit.
                throw DeviceRegistrationError.profileNotYetBootstrapped
            }
        }

        if let pushToken { lastPushToken = pushToken }
        if let locationPushToken { lastLocationPushToken = locationPushToken }

        let appVersion = deviceInfoProvider.appVersion
        let request = RegisterDeviceRequest(
            deviceId: deviceIdProvider.deviceId(forUserId: userId),
            platform: deviceInfoProvider.platform,
            model: deviceInfoProvider.model,
            appVersion: appVersion,
            pushToken: lastPushToken,
            locationPushToken: lastLocationPushToken,
            deviceName: deviceName
        )
        do {
            let response = try await apiClient.registerDevice(request)
            // Records success from EVERY trigger, not just `registerOnLaunchIfNeeded` — this is
            // what keeps `hasRegisteredBefore` above accurate no matter which path last succeeded,
            // and is exactly the bookkeeping "every app update" (004 §5) needs anyway.
            appVersionTracker.setLastRegisteredAppVersion(appVersion, forUserId: userId)
            return response
        } catch {
            // I24 review (Finding 4) — reached even when `hasRegisteredBefore` was true (so the
            // probe above was skipped) if the profile was deleted out from under an in-flight
            // session, e.g. a concurrent `DELETE /users/me` from another device. Mapping to the
            // SAME typed error the probe throws keeps every caller's handling (silence, not a
            // logged failure) correct regardless of which of the two paths actually produced it.
            if (error as? APIError)?.serverCode == .profileNotFound {
                throw DeviceRegistrationError.profileNotYetBootstrapped
            }
            throw error
        }
    }

    /// The pre-flight probe's classification of the caller (specs/010-app-shell-and-screen-ux.md
    /// §1.1, amended by row A37). `.missing` only on a confirmed `PROFILE_NOT_FOUND` (001 §1.5.3);
    /// `.confirmedUnauthorized` only on a confirmed `AUTH_MISSING_TOKEN`/`AUTH_INVALID_TOKEN`/
    /// `AUTH_TOKEN_EXPIRED`/`AUTH_FORBIDDEN` (001 §10) — a caller the backend has told us is
    /// unauthorized must never reach `POST /devices` either (A37 review, Finding 2: this probe
    /// previously treated any code OTHER than `PROFILE_NOT_FOUND` — including all four auth
    /// codes — as "profile exists"). Anything else (inconclusive: a transport/decode failure, or a
    /// server-carried code the four cases above don't cover, e.g. `FAMILY_NOT_FOUND`, which is
    /// deliberately `.exists` — device endpoints work without a family, 001 §1.5.4) fails OPEN to
    /// `.exists`, same reasoning as `CreateGroupViewModel.isBootstrappingProfile` /
    /// `GroupJoinViewModel.isBootstrappingProfile`.
    private enum ProfileProbeState {
        case exists
        case missing
        case confirmedUnauthorized
    }

    private func probeProfileState() async -> ProfileProbeState {
        do {
            _ = try await apiClient.getMyFamily()
            return .exists
        } catch {
            switch (error as? APIError)?.serverCode {
            case .profileNotFound:
                return .missing
            case .authMissingToken, .authInvalidToken, .authTokenExpired, .authForbidden:
                return .confirmedUnauthorized
            default:
                return .exists
            }
        }
    }

    /// Subscribes to push-token refreshes and re-registers with the new token on every emission
    /// (001 §4.1, 000 §O4). Failures are swallowed here (best-effort background sync); callers
    /// that need failure visibility should call `registerOrUpdate` directly instead.
    public func observePushTokenRefreshes(_ provider: PushTokenProviding) {
        Task { [weak self] in
            for await token in provider.tokenUpdates {
                _ = try? await self?.registerOrUpdate(pushToken: token)
            }
        }
    }

    /// Subscribes to APNs Location Push token availability (000 §O1) and re-registers with it the
    /// moment it's captured — same best-effort semantics as `observePushTokenRefreshes`.
    public func observeLocationPushTokenUpdates(_ provider: LocationPushTokenHandling) {
        Task { [weak self] in
            for await token in provider.locationPushTokenUpdates {
                _ = try? await self?.registerOrUpdate(locationPushToken: token)
            }
        }
    }

    /// specs/004-ios-client.md §5's remaining two triggers this class didn't yet wire: **first
    /// launch after sign-in** and **every app update** (compare stored vs running `appVersion`) —
    /// push-token refresh was already covered by `observePushTokenRefreshes`. `previousVersion ==
    /// nil` covers BOTH triggers at once: no stored version for this `userId` means either this
    /// user has never registered on this device (first launch after THEIR sign-in — keyed per-user,
    /// so a different user signing in on the same device is correctly its own "first launch") or
    /// the tracker was never populated; either way 001 §4.1's upsert semantics make a redundant
    /// `registerOrUpdate` call harmless.
    ///
    /// Call once per app launch (and safe to call again on every foreground/sign-in event — it's a
    /// no-op once the current version is already recorded). Best-effort like
    /// `observePushTokenRefreshes`: a failed call does NOT mark the version as registered (since
    /// `registerOrUpdate` above only records success on ITS success path), so the next opportunity
    /// retries it — the existing `404 DEVICE_NOT_FOUND` self-heal path (`LocationRuntimeContainer`'s
    /// `onReRegisterDevice`) remains the ultimate backstop regardless.
    @discardableResult
    public func registerOnLaunchIfNeeded() async -> Bool {
        guard let userId = authProvider.currentUserId else { return false }
        let currentVersion = deviceInfoProvider.appVersion
        guard appVersionTracker.lastRegisteredAppVersion(forUserId: userId) != currentVersion else { return false }
        return (try? await registerOrUpdate()) != nil
    }
}
