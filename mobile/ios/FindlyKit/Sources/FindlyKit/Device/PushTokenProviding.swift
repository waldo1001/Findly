import Foundation

/// specs/004-ios-client.md §4 — an `AsyncStream` of push-token values (FCM/APNs token). Every
/// emission MUST trigger a `POST /devices` re-registration (001 §4.1, 000 §O4); the real
/// implementation bridges FCM/APNs delegate callbacks into this stream (on-device wiring, iOS-only
/// — scaffolded here behind the protocol so `DeviceRegistrationService` stays testable everywhere).
public protocol PushTokenProviding {
    var tokenUpdates: AsyncStream<String> { get }
}

/// Test/dev double — call `emit(_:)` to simulate a token refresh.
public final class StubPushTokenProvider: PushTokenProviding {
    public let tokenUpdates: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation

    public init() {
        var continuation: AsyncStream<String>.Continuation!
        self.tokenUpdates = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    public func emit(_ token: String) {
        continuation.yield(token)
    }

    public func finish() {
        continuation.finish()
    }
}
