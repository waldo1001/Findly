import Foundation

/// specs/004-ios-client.md I2 (001 §6) — "locate now": create a locate request, then poll every
/// 2 s (§6.2) until a terminal status. `.pending` renders "last known, updating…" (000 §O1's push-
/// reliability fallback UX) since `lastKnown` (the instant answer, §6.1) is tracked separately from
/// the polled terminal outcome.
public enum LocateUIStatus: Equatable {
    case requesting
    case pending
    case fulfilled
    case pushFailed
    case expired
    case failed(String)
}

@MainActor
public final class LocateViewModel: ObservableObject {
    @Published public private(set) var status: LocateUIStatus = .requesting
    @Published public private(set) var lastKnown: LastKnownFix?
    @Published public private(set) var fulfilledFix: FulfilledFix?

    private let apiClient: FindlyAPIClient
    private let pollInterval: Duration
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
        sleep: @escaping (Duration) async -> Void = {
            let (seconds, attoseconds) = $0.components
            let nanoseconds = UInt64(max(0, seconds)) * 1_000_000_000 + UInt64(max(0, attoseconds) / 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.apiClient = apiClient
        self.pollInterval = pollInterval
        self.sleep = sleep
    }

    public func requestLocate(target: LocateTarget) async {
        pollTask?.cancel()
        status = .requesting
        lastKnown = nil
        fulfilledFix = nil
        do {
            let envelope = try await apiClient.createLocateRequest(target: target)
            lastKnown = envelope.data.lastKnown
            let uiStatus = Self.uiStatus(for: envelope.data.status)
            status = uiStatus
            if uiStatus == .pending {
                startPolling(requestId: envelope.data.requestId)
            }
        } catch {
            status = .failed(userFacingMessage(for: error))
        }
    }

    public func cancel() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func startPolling(requestId: String) {
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.sleep(self.pollInterval)
                if Task.isCancelled { break }
                do {
                    let envelope = try await self.apiClient.pollLocateRequest(requestId: requestId)
                    if Task.isCancelled { break }
                    if let fix = envelope.data.fix {
                        self.fulfilledFix = fix
                    }
                    let uiStatus = Self.uiStatus(for: envelope.data.status)
                    self.status = uiStatus
                    if uiStatus != .pending {
                        break
                    }
                } catch {
                    self.status = .failed(userFacingMessage(for: error))
                    break
                }
            }
        }
    }

    private static func uiStatus(for status: LocateStatus) -> LocateUIStatus {
        switch status {
        case .pending: return .pending
        case .fulfilled: return .fulfilled
        case .expired: return .expired
        case .pushFailed: return .pushFailed
        }
    }
}
