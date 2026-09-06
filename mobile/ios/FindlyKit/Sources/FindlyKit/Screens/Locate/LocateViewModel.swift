import Foundation

/// specs/004-ios-client.md I2 (001 §6) — "locate now": create a locate request, then poll every
/// 2 s (§6.2) until a terminal status. `.pending` renders "last known, updating…" (000 §O1's push-
/// reliability fallback UX) since `lastKnown` (the instant answer, §6.1) is tracked separately from
/// the polled terminal outcome.
///
/// **specs/009-device-runtime.md §5.1 "Requester side" (amended 2026-09-06, I51, building on
/// B26/A39's Android precedent, `LocateStateHolder`).** Polling now stops at a terminal status **or
/// the local end of the request window**, then performs one `GET /locations/latest` fallback and,
/// if the target's `recordedAt` is newer than the request's `createdAt` **and** a fix is present,
/// shows that position (`.late`) before declaring the device `.unreachable`. `.fulfilled` ("fresh")
/// and `.late` are both definitive answers; `.late` renders identically to `.fulfilled` — the
/// screen adds the age caption (`LocateAgeCaption`).
public enum LocateUIStatus: Equatable {
    case requesting
    case pending
    /// A definitive fulfil within the request window ("fresh").
    case fulfilled
    /// Either a definitive fulfil inside B26's 10-minute grace (wire `late: true`) or a position
    /// found by the post-window `/locations/latest` fallback whose `recordedAt` is newer than the
    /// request's `createdAt`. Both render identically — see `resolvedPosition`.
    case late
    /// Terminal, with no usable position even after the fallback check.
    case unreachable
    case failed(String)
    /// specs/010-app-shell-and-screen-ux.md §2.1 — a confirmed `PROFILE_NOT_FOUND`/
    /// `FAMILY_NOT_FOUND` from `requestLocate`, this screen's load path (`POST /locate-requests`
    /// is family-scoped, 001 §6/§1.5.4). MUST NOT render the retryable `.failed` card.
    case routeToOnboarding(OnboardingVariant)
}

/// The position shown for `.fulfilled`/`.late` — deliberately not the wire `FulfilledFix` type,
/// since a `.late` outcome resolved via the `/locations/latest` fallback comes from a `DeviceLocation`
/// (no `fixId`/`batteryPct`/`source` guarantee), not a `POST .../fulfill` response.
public struct LocatedPosition: Equatable {
    public let lat: Double
    public let lon: Double
    public let accuracyM: Double
    public let recordedAt: String
}

@MainActor
public final class LocateViewModel: ObservableObject {
    @Published public private(set) var status: LocateUIStatus = .requesting
    @Published public private(set) var lastKnown: LastKnownFix?
    @Published public private(set) var resolvedPosition: LocatedPosition?
    /// **I51 review fix (Blocking, finding 1).** The raw wire status that triggered `.unreachable`,
    /// kept "for the UI's own copy" — mirrors Android's `LocateStateHolder`/`LocateUiState.Terminal
    /// .status`. `nil` until a fallback resolution actually runs. Set from whichever triggered it:
    /// the wire's own `.expired`/`.pushFailed` when the poll or create response supplied one, or
    /// `.expired` as the default for a purely local-window timeout (the server never actually said
    /// anything). Only `.pushFailed` gets the distinct "couldn't reach the device" copy (001 §6.2);
    /// everything else renders "request expired" — a request that was delivered and simply never
    /// answered must not be told the opposite of the truth.
    @Published public private(set) var wireStatus: LocateStatus?

    private let apiClient: FindlyAPIClient
    private let pollInterval: Duration
    /// specs/009 §5.1 "Requester side" clock-skew rule: injected so the local-elapsed-time check
    /// (never an absolute comparison against the server's `expiresAt`) is deterministic under test —
    /// mirrors `LocateRequestPushHandler`'s own `now` seam and Android's `LocateStateHolder`.
    private let now: () -> Date
    /// Injectable so tests can drive the poll loop deterministically instead of waiting on a real
    /// 2 s timer (specs/004 §9's "poll-until-terminal" test requirement).
    ///
    /// Defaults through `Task.sleep(nanoseconds:)`, deliberately NOT `Task.sleep(for: Duration)` —
    /// see `SignInViewModel.sleep`'s doc (I13): the latter is a known Swift concurrency runtime
    /// defect (swiftlang/swift#86204) that crashed `swift test` via `SignInViewModel`'s identical
    /// `[weak self]`-polling-loop shape. `LocateViewModel`'s own tests happen to always gate/cancel
    /// `pollTask` before it can race a deinit, so this specific call site wasn't the one that
    /// reproduced the crash — but it is the exact same pattern, in the same module, and the same
    /// defect is just as reachable from a real device (backgrounding this screen mid-poll), so it
    /// gets the same fix rather than being left as a known-latent twin.
    private let sleep: (Duration) async -> Void
    private var pollTask: Task<Void, Never>?

    public init(
        apiClient: FindlyAPIClient,
        pollInterval: Duration = .seconds(2),
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (Duration) async -> Void = {
            let (seconds, attoseconds) = $0.components
            let nanoseconds = UInt64(max(0, seconds)) * 1_000_000_000 + UInt64(max(0, attoseconds) / 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.apiClient = apiClient
        self.pollInterval = pollInterval
        self.now = now
        self.sleep = sleep
    }

    public func requestLocate(target: LocateTarget) async {
        pollTask?.cancel()
        status = .requesting
        lastKnown = nil
        resolvedPosition = nil
        wireStatus = nil
        do {
            let envelope = try await apiClient.createLocateRequest(target: target)
            let data = envelope.data
            lastKnown = data.lastKnown
            guard data.status == .pending else {
                // §6.1: the create response is only ever "pending" or, immediately, "pushFailed"
                // (no valid token to send to) — it never carries a fix, so a "pushFailed" here takes
                // the same one-shot fallback path any other non-fresh terminal does, rather than
                // being assumed unreachable outright (009 §5.1 "Requester side"). `data.status` here
                // is always `.pushFailed` per §6.1, carried through as-is rather than hardcoded.
                await resolveViaFallback(targetDeviceId: data.targetDeviceId, createdAt: data.createdAt, wireStatus: data.status)
                return
            }
            status = .pending
            startPolling(requestId: data.requestId, targetDeviceId: data.targetDeviceId, createdAt: data.createdAt, expiresAt: data.expiresAt)
        } catch {
            if let variant = onboardingRoutingOutcome(for: error) {
                status = .routeToOnboarding(variant)
            } else {
                status = .failed(userFacingMessage(for: error))
            }
        }
    }

    public func cancel() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func startPolling(requestId: String, targetDeviceId: String, createdAt: String, expiresAt: String) {
        // Captured once, right as the create response is received (mirrors A39's Android review,
        // finding 6) — the window is measured from here, in locally-elapsed time.
        let receivedAt = now()
        let pollWindow = Self.pollWindow(createdAt: createdAt, expiresAt: expiresAt)
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.sleep(self.pollInterval)
                if Task.isCancelled { break }
                do {
                    let envelope = try await self.apiClient.pollLocateRequest(requestId: requestId)
                    if Task.isCancelled { break }
                    let data = envelope.data
                    // I51 review fix (Minor, finding 4): a `fulfilled` wire response REQUIRES a
                    // usable fix — otherwise this falls through to the same fallback/unreachable
                    // decision as any other non-fresh terminal, rather than rendering a "Live" chip
                    // with no position (outcome and usable fix must move in lockstep, mirroring
                    // A39's finding 13 on the fallback path).
                    if data.status == .fulfilled, let fix = data.fix {
                        self.resolvedPosition = LocatedPosition(lat: fix.lat, lon: fix.lon, accuracyM: fix.accuracyM, recordedAt: fix.recordedAt)
                        self.status = data.late ? .late : .fulfilled
                        return
                    }
                    let windowElapsed = Self.hasElapsed(pollWindow: pollWindow, since: receivedAt, now: self.now)
                    if data.status == .expired || data.status == .pushFailed || data.status == .fulfilled || windowElapsed {
                        // I51 review fix (Blocking, finding 1): carry the wire's own terminal status
                        // through so `.unreachable` can tell "couldn't reach the device" (pushFailed)
                        // apart from "request expired" (everything else, incl. a fixless "fulfilled"
                        // and a purely local-window timeout the server never actually confirmed).
                        //
                        // I51 re-review fix (Minor, finding 1): `.pending` is the only status that can
                        // reach this line through the window-elapsed path alone — `fulfilled`, `expired`
                        // and `pushFailed` either return above or are themselves the trigger. Defaulting
                        // to `.expired` for anything but `.pending` fabricated a status the wire never
                        // sent (e.g. a fixless `fulfilled` became `.expired`, falsely claiming the server
                        // never answered). Only the genuine local timeout gets defaulted now; every
                        // wire-supplied status is carried through untouched.
                        let triggerStatus: LocateStatus = data.status == .pending ? .expired : data.status
                        await self.resolveViaFallback(targetDeviceId: targetDeviceId, createdAt: createdAt, wireStatus: triggerStatus)
                        return
                    }
                    self.status = .pending
                } catch {
                    self.status = .failed(userFacingMessage(for: error))
                    return
                }
            }
        }
    }

    /// specs/009 §5.1 "Requester side": the one-shot `GET /locations/latest` check performed before
    /// ever declaring `.unreachable` — a `recordedAt` newer than `createdAt` for `targetDeviceId`,
    /// **with a usable fix**, is shown as `.late` instead (a late fulfil, or some other report,
    /// already updated last-known). A31/A39-equivalent rule: `recordedAt` alone is not enough — a
    /// "no location yet" device row (001 §5.2, `lat`/`lon` null) must not be rendered as located.
    ///
    /// `wireStatus` (I51 review, finding 1) is whatever triggered this call — published onto
    /// `self.wireStatus` immediately so it is visible even if this resolves to `.late` instead of
    /// `.unreachable` (harmless either way: only the `.unreachable` chip reads it).
    private func resolveViaFallback(targetDeviceId: String, createdAt: String, wireStatus: LocateStatus) async {
        self.wireStatus = wireStatus
        let createdAtDate = Self.parseISO8601(createdAt)
        let device: DeviceLocation?
        do {
            let envelope = try await apiClient.getLatestLocations()
            device = envelope.data.members
                .flatMap { $0.devices }
                .first { $0.deviceId == targetDeviceId }
        } catch {
            device = nil
        }
        let recordedAtDate = device?.recordedAt.flatMap(Self.parseISO8601)
        let position = device.flatMap { device -> LocatedPosition? in
            guard let lat = device.lat, let lon = device.lon, let recordedAt = device.recordedAt else { return nil }
            return LocatedPosition(lat: lat, lon: lon, accuracyM: device.accuracyM ?? 0, recordedAt: recordedAt)
        }
        if let createdAtDate, let recordedAtDate, recordedAtDate > createdAtDate, let position {
            resolvedPosition = position
            status = .late
        } else {
            status = .unreachable
        }
    }

    /// The window is `Duration(createdAt, expiresAt)` — two **server** values, so a constant clock
    /// skew cancels out of the subtraction — never the server's `expiresAt` compared directly
    /// against this device's own `now()` (a fast client clock must not expire on the first poll
    /// tick). A zero-length or unparsable window is malformed data, not an already-expired request,
    /// and must never satisfy the elapsed check (returns `nil`, which `hasElapsed` treats as "never
    /// expires locally").
    private static func pollWindow(createdAt: String, expiresAt: String) -> TimeInterval? {
        guard let created = parseISO8601(createdAt), let expires = parseISO8601(expiresAt) else { return nil }
        let window = expires.timeIntervalSince(created)
        return window > 0 ? window : nil
    }

    /// Both readings come from the same injected `now`, so a constant skew in that clock cancels out
    /// of this subtraction — only the *locally elapsed* duration since `receivedAt` matters.
    private static func hasElapsed(pollWindow: TimeInterval?, since receivedAt: Date, now: () -> Date) -> Bool {
        guard let pollWindow else { return false }
        return now().timeIntervalSince(receivedAt) >= pollWindow
    }

    private static func parseISO8601(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }
}
