#if os(iOS)
import Combine
import SwiftUI
import UIKit

/// specs/010-app-shell-and-screen-ux.md §1.4 "Opaque and full-screen above everything (including
/// sheets and dialogs)" — a UIKit bridge, verified by `xcodebuild` (004 §2), not `swift test`.
///
/// A SwiftUI `.overlay` on the root view sits BELOW anything the root presents (the permission
/// disclosure `fullScreenCover`, sheets, alerts), so the lock would leave those readable. A
/// dedicated `UIWindow` above `.alert` covers them all, and the same window carries the
/// app-switcher cover (the OS snapshot is taken of every window of the scene).
///
/// While the overlay is visible every OTHER window is hidden from VoiceOver (restored on hide),
/// focus moves to the lock screen, and the first responder is resigned app-wide.
/// The decisions live in `AppLockOverlayVisibility` (unit-tested).
///
/// The window is shown synchronously from the controller's `@Published` willSet, before the
/// SwiftUI content has re-rendered, so its hosting view is opaque `systemBackground` rather than
/// clear: no frame of the app underneath can slip through while SwiftUI catches up.
@MainActor
public final class AppLockWindowPresenter {
    private let controller: AppLockController
    private var window: UIWindow?
    private var subscription: AnyCancellable?
    /// Views whose `accessibilityElementsHidden` this presenter changed, with the prior value.
    private var hiddenViews: [(view: WeakView, previous: Bool)] = []
    private var isShowing = false
    private var hasMovedFocus = false

    private struct WeakView { weak var view: UIView? }

    public init(controller: AppLockController) {
        self.controller = controller
        // No `removeDuplicates`: `apply` is idempotent, and re-running it on every scene-phase
        // change is the retry path when no `UIWindowScene` was available at the first attempt.
        subscription = Publishers.CombineLatest4(
            controller.$isLocked, controller.$isCoverVisible, controller.$scenePhase, controller.$isEnabled
        )
        .sink { [weak self] locked, cover, _, enabled in
            self?.apply(AppLockOverlayVisibility(isLocked: locked, isCoverVisible: cover), isEnabled: enabled)
        }
    }

    private func apply(_ visibility: AppLockOverlayVisibility, isEnabled: Bool) {
        if visibility.isVisible {
            guard let window = window ?? makeWindow() else { return }  // retried on the next change
            self.window = window
            window.isHidden = false
            if !visibility.movesAccessibilityFocusToOverlay { hasMovedFocus = false }
            if !isShowing {
                isShowing = true
                if visibility.hidesOtherWindowsFromAccessibility { hideOtherWindowsFromAccessibility(except: window) }
                if visibility.resignsFirstResponder {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
            if visibility.movesAccessibilityFocusToOverlay, !hasMovedFocus {
                hasMovedFocus = true
                UIAccessibility.post(notification: .screenChanged, argument: window.rootViewController?.view)
            }
        } else {
            hasMovedFocus = false
            if isShowing {
                isShowing = false
                restoreOtherWindows()
                window?.isHidden = true
                // Rebuilt against the current scene at the next show.
                window = nil
            }
            // Pre-created hidden while the lock is on, so the first cover/lock render is not racing
            // the app-switcher snapshot.
            if isEnabled, window == nil, let precreated = makeWindow() {
                precreated.isHidden = true
                window = precreated
            }
        }
    }

    private func hideOtherWindowsFromAccessibility(except overlay: UIWindow) {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for other in scene.windows where other !== overlay {
                // The WINDOW itself, not its root view: UIKit-presented sheets, covers and dialogs
                // live in presentation containers that are siblings of the root view in the window.
                hiddenViews.append((WeakView(view: other), other.accessibilityElementsHidden))
                other.accessibilityElementsHidden = true
            }
        }
    }

    private func restoreOtherWindows() {
        for entry in hiddenViews { entry.view.view?.accessibilityElementsHidden = entry.previous }
        hiddenViews = []
    }

    private func makeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState != .unattached }) else { return nil }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        let host = UIHostingController(rootView: AppLockOverlay(controller: controller))
        host.view.backgroundColor = .systemBackground
        window.rootViewController = host
        _ = host.view  // load now, so the content is ready before the window is first shown
        return window
    }
}
#endif
