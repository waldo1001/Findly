import Foundation

public enum PollOutcome: Equatable {
    case applied
    case deviceNotFound
    case failed
}

/// The pull-based settings poll (specs/009-device-runtime.md §4 / §3.5's third path): "while
/// paused the client MUST re-check its settings via `GET /devices` on every app foreground and at
/// least every 6 hours." Fetches this device's row from `GET /devices` (001-api-contract.md
/// §4.2 — the only settings-read endpoint; there is no "get my own device" call, so the family-wide
/// list is filtered by `deviceId`) and applies it through `DeviceSettingsApplying`. Callable from
/// **both** §4's required triggers (app foreground and a low-frequency ≥6-hourly background
/// check — `LocationRuntimeContainer` wires both to this one method); harmless to call when not
/// actually paused since `DeviceSettingsCoordinator.applySettings` is a no-op unless something
/// changed. Mirrors Android's `SettingsPoller`.
public final class PausedDevicePoller {
    private let apiClient: FindlyAPIClient
    private let deviceId: () -> String?
    private let settingsApplying: DeviceSettingsApplying

    public init(apiClient: FindlyAPIClient, deviceId: @escaping () -> String?, settingsApplying: DeviceSettingsApplying) {
        self.apiClient = apiClient
        self.deviceId = deviceId
        self.settingsApplying = settingsApplying
    }

    public func poll() async -> PollOutcome {
        guard let deviceId = deviceId() else { return .failed }
        do {
            let envelope = try await apiClient.listDevices()
            guard let own = envelope.data.devices.first(where: { $0.deviceId == deviceId }) else {
                return .deviceNotFound
            }
            await settingsApplying.applySettings(DeviceSettingsSnapshot(syncIntervalMinutes: own.syncIntervalMinutes, trackingEnabled: own.trackingEnabled))
            return .applied
        } catch {
            return .failed
        }
    }
}
