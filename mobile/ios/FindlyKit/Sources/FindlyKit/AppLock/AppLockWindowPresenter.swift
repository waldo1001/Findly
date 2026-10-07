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
/// The window is shown synchronously from the controller's `@Published` willSet, before the
/// SwiftUI content has re-rendered, so its hosting view is opaque `systemBackground` rather than
/// clear: no frame of the app underneath can slip through while SwiftUI catches up.
@MainActor
public final class AppLockWindowPresenter {
    private let controller: AppLockController
    private var window: UIWindow?
    private var subscription: AnyCancellable?

    public init(controller: AppLockController) {
        self.controller = controller
        subscription = controller.$isLocked
            .combineLatest(controller.$isCoverVisible)
            .map { $0 || $1 }
            .removeDuplicates()
            .sink { [weak self] visible in self?.setVisible(visible) }
    }

    private func setVisible(_ visible: Bool) {
        if visible {
            guard let window = window ?? makeWindow() else { return }
            self.window = window
            window.isHidden = false
        } else {
            window?.isHidden = true
        }
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
        return window
    }
}
#endif
