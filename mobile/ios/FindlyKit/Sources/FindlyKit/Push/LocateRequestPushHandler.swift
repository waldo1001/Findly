import Foundation

/// `LOCATE_REQUEST` (specs/001-api-contract.md §8.1; specs/009-device-runtime.md §5.1). On receipt:
/// if `now > expiresAt + 10 min`, ignore it silently (no GPS burn for a stale request); otherwise
/// capture one **high-accuracy** fix and `POST /locate-requests/{id}/fulfill` with
/// `source: "locate"` (§6.3).
///
/// Deliberately takes no pause/tracking-enabled input at all — a paused device still fulfills an
/// explicit locate request (009 §5.1); only the periodic pipeline's own suppression rules
/// (`FixCaptureCoordinator`) check pause state, and this class calls `LocationProviding` directly,
/// bypassing that coordinator entirely (mirrors Android's `LocateRequestPushHandler` bypassing
/// `FixCaptureCoordinator`/calling `LocationCapturer` directly — see `FixCaptureCoordinator`'s own
/// doc for why `source: .locate` must never route through it).
///
/// A malformed payload (missing/blank `requestId`, missing/unparsable `expiresAt`) is dropped
/// silently, never crashed on (009 §5 intro). Failure to obtain a fix, no signed-in device to
/// fulfill as, or a failed `fulfill` call are also silent give-ups — "the requester's poll surfaces
/// the outcome" (009 §5.1).
public final class LocateRequestPushHandler: LocateRequestHandling {
    private let locationProvider: LocationProviding
    private let apiClient: FindlyAPIClient
    /// Resolves the current device's `deviceId`, or `nil` if there is none to fulfill as (signed
    /// out, never registered). Re-evaluated on every call, not captured once.
    private let deviceId: () -> String?
    private let now: () -> Date

    public init(
        locationProvider: LocationProviding,
        apiClient: FindlyAPIClient,
        deviceId: @escaping () -> String?,
        now: @escaping () -> Date = Date.init
    ) {
        self.locationProvider = locationProvider
        self.apiClient = apiClient
        self.deviceId = deviceId
        self.now = now
    }

    public func handle(_ data: [String: String]) async {
        guard let requestId = data["requestId"], !requestId.isEmpty else { return }
        guard let expiresAt = data["expiresAt"].flatMap(Self.parseISO8601) else { return }
        guard now() <= expiresAt.addingTimeInterval(Self.staleGraceSeconds) else { return }
        guard let deviceId = deviceId() else { return }
        guard let fix = try? await locationProvider.requestSingleFix(source: .locate) else { return }

        // Result intentionally ignored - a failed fulfill call is silent per 009 §5.1.
        _ = try? await apiClient.fulfillLocateRequest(deviceId: deviceId, requestId: requestId, fix: fix)
    }

    /// specs/001 §6.3 / specs/009 §5.1: "no GPS burn for a stale request."
    private static let staleGraceSeconds: TimeInterval = 10 * 60

    private static func parseISO8601(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }
}
