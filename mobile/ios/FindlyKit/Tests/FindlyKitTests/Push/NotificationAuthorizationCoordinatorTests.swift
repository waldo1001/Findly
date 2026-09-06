import Testing
@testable import FindlyKit

private final class FakeNotificationAuthorizationRequester: NotificationAuthorizationRequesting {
    private(set) var requestCallCount = 0
    func requestAuthorization() async { requestCallCount += 1 }
}

/// specs/009-device-runtime.md §7 (I50 fix 4, amended 2026-09-06) — "the latter [notification
/// authorization] MUST actually be issued on first sign-in" and "never re-prompt automatically
/// once answered." `NotificationAuthorizationCoordinator` is the pure decision/coordination logic
/// behind that rule, kept separate from `SystemNotificationAuthorizationRequester` (the real
/// `UNUserNotificationCenter`-touching glue, `#if os(iOS) && canImport(UserNotifications)`) so it's
/// testable on any host — mirrors the split every other I50 fix uses.
struct NotificationAuthorizationCoordinatorTests {

    @Test func requestOnFirstSignInIfNeeded_neverRequestedBefore_requestsAndRecordsIt() async {
        let requester = FakeNotificationAuthorizationRequester()
        let stateStore = InMemoryNotificationAuthorizationStateStore()
        let coordinator = NotificationAuthorizationCoordinator(requester: requester, stateStore: stateStore)

        await coordinator.requestOnFirstSignInIfNeeded()

        #expect(requester.requestCallCount == 1)
        #expect(stateStore.hasRequested)
    }

    @Test func requestOnFirstSignInIfNeeded_alreadyRequested_isANoOp() async {
        let requester = FakeNotificationAuthorizationRequester()
        let stateStore = InMemoryNotificationAuthorizationStateStore()
        stateStore.markRequested()
        let coordinator = NotificationAuthorizationCoordinator(requester: requester, stateStore: stateStore)

        await coordinator.requestOnFirstSignInIfNeeded()

        #expect(requester.requestCallCount == 0, "must never re-prompt automatically once answered")
    }

    @Test func requestOnFirstSignInIfNeeded_calledTwiceInARow_onlyRequestsOnce() async {
        // The realistic call pattern: FindlyApp's onSignedIn closure runs at cold launch (already
        // signed in) AND again from RootView's interactive sign-in completion.
        let requester = FakeNotificationAuthorizationRequester()
        let stateStore = InMemoryNotificationAuthorizationStateStore()
        let coordinator = NotificationAuthorizationCoordinator(requester: requester, stateStore: stateStore)

        await coordinator.requestOnFirstSignInIfNeeded()
        await coordinator.requestOnFirstSignInIfNeeded()

        #expect(requester.requestCallCount == 1)
    }
}
