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
    private let sleep: (Duration) async -> Void
    private var pollTask: Task<Void, Never>?

    public init(
        apiClient: FindlyAPIClient,
        pollInterval: Duration = .seconds(2),
        sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }
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
