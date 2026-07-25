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
}
