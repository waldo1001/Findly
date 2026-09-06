import Foundation

/// specs/009-device-runtime.md §7 (I50 fix 4, amended 2026-09-06) — the pure coordination logic
/// behind "request `UNUserNotificationCenter` authorization on first sign-in, never re-prompt
/// automatically once answered." Nothing in the shipped client ever called
/// `requestAuthorization` at all — the delegate was set and remote notifications were registered,
/// but without user authorization no geofence alert and no locate alert could ever display on iOS.
///
/// Kept separate from `PushRuntimeContainer` (which owns push MESSAGE routing, not OS-permission
/// prompts) so the app target's sign-in-completion callback has one small, directly-testable seam
/// to call — mirrors how `LocationRuntimeContainer.onSignedIn()` is the equivalent seam for the
/// geofence-config-sync trigger.
public final class NotificationAuthorizationCoordinator {
    private let requester: NotificationAuthorizationRequesting
    private let stateStore: NotificationAuthorizationStateStoring

    public init(requester: NotificationAuthorizationRequesting, stateStore: NotificationAuthorizationStateStoring) {
        self.requester = requester
        self.stateStore = stateStore
    }

    /// Call from the sign-in-completion path (specs/009 §7: "on first sign-in"). A no-op on every
    /// call after the first for this stored state — safe to call from BOTH the cold-launch
    /// already-signed-in path and an interactive sign-in completion, which is the real call
    /// pattern `FindlyApp`'s `onSignedIn` closure has.
    public func requestOnFirstSignInIfNeeded() async {
        guard !stateStore.hasRequested else { return }
        await requester.requestAuthorization()
        stateStore.markRequested()
    }
}
