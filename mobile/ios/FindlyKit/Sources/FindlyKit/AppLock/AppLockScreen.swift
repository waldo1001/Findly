import SwiftUI

/// specs/010-app-shell-and-screen-ux.md §1.4 "The lock screen" — opaque, full-screen: icon,
/// `Findly is locked`, and an **Unlock** button. Composed from design-system components only.
///
/// The icon is an SF Symbol in the brand tint rather than the app icon: an `AppIcon` asset-catalog
/// entry cannot be loaded as an `Image` at runtime.
public struct AppLockScreen: View {
    @Environment(\.theme) private var theme
    private let onUnlock: () -> Void

    public init(onUnlock: @escaping () -> Void) {
        self.onUnlock = onUnlock
    }

    public var body: some View {
        VStack(spacing: theme.spacing.lg) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(theme.colors.onPrimary)
                .frame(width: 88, height: 88)
                .background(theme.colors.primary)
                .clipShape(RoundedRectangle(cornerRadius: theme.corner.lg))
                .accessibilityHidden(true)
            Text("Findly is locked")
                .font(theme.typography.titleLarge.font)
                .foregroundColor(theme.colors.onSurface)
            FindlyButton("Unlock", action: onUnlock)
                .padding(.horizontal, theme.spacing.xl)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.surface.ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
    }
}

/// specs/010 §1.4 "App-switcher snapshot" — the opaque cover drawn while the scene is not active and
/// the lock is on, so the OS task-switcher snapshot never shows family locations. Carries nothing
/// but the name.
public struct AppSwitcherCover: View {
    @Environment(\.theme) private var theme

    public init() {}

    public var body: some View {
        Text("Findly")
            .font(theme.typography.titleLarge.font)
            .foregroundColor(theme.colors.onSurface)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.colors.surface.ignoresSafeArea())
    }
}

/// What the overlay window hosts: the lock screen when locked (it wins over the cover), the cover
/// when only the scene is inactive. Auto-prompts once per lock, once the scene is active.
public struct AppLockOverlay: View {
    @ObservedObject private var controller: AppLockController
    @Environment(\.colorScheme) private var colorScheme

    public init(controller: AppLockController) {
        self.controller = controller
    }

    private struct PromptKey: Equatable {
        let isLocked: Bool
        let phase: AppLockScenePhase
    }

    public var body: some View {
        Group {
            if controller.isLocked {
                AppLockScreen { Task { await controller.unlock() } }
            } else if controller.isCoverVisible {
                AppSwitcherCover()
            }
        }
        .environment(\.theme, colorScheme == .dark ? .dark : .light)
        .task(id: PromptKey(isLocked: controller.isLocked, phase: controller.scenePhase)) {
            await controller.autoPromptIfNeeded()
        }
    }
}
