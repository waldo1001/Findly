import Foundation

/// specs/004-ios-client.md I2 (001 §4.2–4.3) — the device list + settings screen. `isParent` gates
/// every mutation client-side (matching the server's own §4.3 rule: only a parent may change
/// `syncIntervalMinutes`/`trackingEnabled`/`deviceName`; a non-parent owner may only ever change
/// `pushToken`, which isn't user-editable here — it's set automatically by the push-registration
/// path). specs/010-app-shell-and-screen-ux.md §4.2 (I36): a row's failed update surfaces via
/// `error(forDeviceId:)`, scoped to that device's own card, without discarding the already-loaded
/// list or any other card's error.
@MainActor
public final class DeviceSettingsViewModel: ObservableObject {
    public enum State: Equatable {
        case loading
        case loaded([DeviceListItem])
        case error(String)
        /// specs/010-app-shell-and-screen-ux.md §2.1 — a confirmed `PROFILE_NOT_FOUND` on this
        /// load. `GET /devices` works without a family (001 §1.5.4/§4), so `FAMILY_NOT_FOUND` is
        /// not actually reachable here, but the shared classifier handles it identically anyway.
        case routeToOnboarding(OnboardingVariant)
    }

    @Published public private(set) var state: State = .loading
    /// specs/010-app-shell-and-screen-ux.md §4.2 (I36) — one entry per device with an in-flight
    /// or most-recent mutation failure; rendered on that device's own card. Replaces the retired
    /// shared `lastActionError`, which could not express "this error belongs to device X" and so
    /// pooled every card's failures into one top-of-list banner.
    @Published private(set) var cardErrors: [String: String] = [:]
    /// specs/001-api-contract.md §9 — mirrors the caller's `features.limits.minSyncIntervalMinutes`
    /// from the most recent envelope (`load()` or any successful `update()`, both of which carry a
    /// fresh `features`). Feeds the sync-interval `FindlyDropdownField`'s pre-disable floor.
    /// CLAUDE.md: limits are always read from `features`, never hardcoded at a call site —
    /// `nil` until the first envelope arrives is the honest representation of that; no numeric
    /// default is declared here for a real decision to accidentally key off of, and no card
    /// renders before `state` reaches `.loaded` (which happens in the same envelope handler that
    /// sets this), so a caller can never observe a stale or invented floor.
    @Published public private(set) var minSyncIntervalMinutes: Int?

    public let isParent: Bool
    private let apiClient: FindlyAPIClient

    public init(apiClient: FindlyAPIClient, isParent: Bool) {
        self.apiClient = apiClient
        self.isParent = isParent
    }

    /// specs/010-app-shell-and-screen-ux.md §4.2 (I36) — one device's mutation error, rendered on
    /// that device's own card. Replaces the retired shared `lastActionError`.
    public func error(forDeviceId deviceId: String) -> String? {
        cardErrors[deviceId]
    }

    public func load() async {
        state = .loading
        do {
            let envelope = try await apiClient.listDevices()
            minSyncIntervalMinutes = envelope.features.limits.minSyncIntervalMinutes
            state = .loaded(envelope.data.devices)
        } catch {
            if let variant = onboardingRoutingOutcome(for: error) {
                state = .routeToOnboarding(variant)
            } else {
                state = .error(userFacingMessage(for: error))
            }
        }
    }

    public func setSyncInterval(deviceId: String, minutes: Int) async {
        await update(deviceId: deviceId, UpdateDeviceRequest(syncIntervalMinutes: minutes))
    }

    /// Setting `trackingEnabled: false` is the "pause" button (specs/001 §4.3).
    public func setTrackingEnabled(deviceId: String, _ enabled: Bool) async {
        await update(deviceId: deviceId, UpdateDeviceRequest(trackingEnabled: enabled))
    }

    public func rename(deviceId: String, name: String) async {
        await update(deviceId: deviceId, UpdateDeviceRequest(deviceName: name))
    }

    private func update(deviceId: String, _ request: UpdateDeviceRequest) async {
        guard isParent else {
            cardErrors[deviceId] = "Only a parent can change device settings."
            return
        }
        guard case .loaded(var devices) = state else { return }
        do {
            let envelope = try await apiClient.updateDevice(deviceId: deviceId, request)
            minSyncIntervalMinutes = envelope.features.limits.minSyncIntervalMinutes
            if let index = devices.firstIndex(where: { $0.deviceId == deviceId }) {
                devices[index] = Self.merge(devices[index], with: envelope.data)
                state = .loaded(devices)
            }
            cardErrors[deviceId] = nil
        } catch {
            cardErrors[deviceId] = userFacingMessage(for: error)
        }
    }

    private static func merge(_ item: DeviceListItem, with response: DeviceResponse) -> DeviceListItem {
        DeviceListItem(
            deviceId: response.deviceId, ownerUserId: response.ownerUserId, platform: response.platform,
            deviceName: response.deviceName, model: response.model, appVersion: response.appVersion,
            syncIntervalMinutes: response.syncIntervalMinutes, trackingEnabled: response.trackingEnabled,
            pushInvalid: response.pushInvalid, ownerDisplayName: item.ownerDisplayName, lastSeenAt: item.lastSeenAt
        )
    }
}
