import Foundation

/// specs/004-ios-client.md §5, specs/001 §4.1 — builds and sends device-registration requests.
/// Triggers (MUST, wired by the app target through this type's public API): first launch after
/// sign-in, every push-token refresh (`observePushTokenRefreshes`), and every app update (caller's
/// responsibility to detect and call `registerOrUpdate()` again).
public final class DeviceRegistrationService {
    private let apiClient: FindlyAPIClient
    private let deviceIdProvider: DeviceIdProviding
    private let deviceInfoProvider: DeviceInfoProviding
    private let authProvider: AuthProviding

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
        authProvider: AuthProviding
    ) {
        self.apiClient = apiClient
        self.deviceIdProvider = deviceIdProvider
        self.deviceInfoProvider = deviceInfoProvider
        self.authProvider = authProvider
    }

    @discardableResult
    public func registerOrUpdate(
        pushToken: String? = nil,
        locationPushToken: String? = nil,
        deviceName: String? = nil
    ) async throws -> Envelope<DeviceResponse> {
        guard let userId = authProvider.currentUserId else { throw AuthError.notSignedIn }

        if let pushToken { lastPushToken = pushToken }
        if let locationPushToken { lastLocationPushToken = locationPushToken }

        let request = RegisterDeviceRequest(
            deviceId: deviceIdProvider.deviceId(forUserId: userId),
            platform: deviceInfoProvider.platform,
            model: deviceInfoProvider.model,
            appVersion: deviceInfoProvider.appVersion,
            pushToken: lastPushToken,
            locationPushToken: lastLocationPushToken,
            deviceName: deviceName
        )
        return try await apiClient.registerDevice(request)
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
    /// `observePushTokenRefreshes`: a failed call does NOT mark the version as registered, so the
    /// next opportunity retries it — the existing `404 DEVICE_NOT_FOUND` self-heal path
    /// (`LocationRuntimeContainer`'s `onReRegisterDevice`) remains the ultimate backstop regardless.
    @discardableResult
    public func registerOnLaunchIfNeeded(appVersionTracker: AppVersionRegistrationTracking) async -> Bool {
        guard let userId = authProvider.currentUserId else { return false }
        let currentVersion = deviceInfoProvider.appVersion
        guard appVersionTracker.lastRegisteredAppVersion(forUserId: userId) != currentVersion else { return false }
        guard (try? await registerOrUpdate()) != nil else { return false }
        appVersionTracker.setLastRegisteredAppVersion(currentVersion, forUserId: userId)
        return true
    }
}
