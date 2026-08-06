import SwiftUI

/// specs/009-device-runtime.md §7 — the persistent, dismissible-per-session degraded-state banner.
///
/// Denial is never fatal in this app: the family map still works and other members' locations are
/// unaffected; only *this* device stops contributing. That is precisely why the banner is required
/// — without it the app looks like it is working while quietly reporting nothing, which is the
/// worst outcome for a product whose whole promise is "you can see where everyone is".
///
/// Stateless and presentational like every other component here: what to show is decided by
/// `PermissionFlowPolicy.banner(...)`, never by this view.
public struct PermissionBannerView: View {
    @Environment(\.theme) private var theme
    private let banner: PermissionBanner
    private let onOpenSettings: () -> Void
    private let onDismiss: () -> Void

    public init(
        banner: PermissionBanner,
        onOpenSettings: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.banner = banner
        self.onOpenSettings = onOpenSettings
        self.onDismiss = onDismiss
    }

    public var body: some View {
        if banner != .none {
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                HStack(alignment: .top, spacing: theme.spacing.sm) {
                    VStack(alignment: .leading, spacing: theme.spacing.xs) {
                        Text(title)
                            .font(theme.typography.titleMedium.font)
                            .foregroundColor(theme.colors.onSurface)
                        Text(message)
                            .font(theme.typography.bodyMedium.font)
                            .foregroundColor(theme.colors.onSurface.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(theme.typography.labelSmall.font)
                            .foregroundColor(theme.colors.onSurface.opacity(0.6))
                            .padding(theme.spacing.xs)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Dismiss")
                }

                // 009 §7 requires "a route into system settings" — a banner that only states the
                // problem leaves the user to find Settings themselves, which most will not.
                FindlyButton("Open Settings", style: .secondary, action: onOpenSettings)
            }
            .padding(theme.spacing.md)
            .background(theme.colors.surfaceVariant)
            .overlay(alignment: .leading) {
                // A severity stripe rather than a coloured background: it reads at a glance without
                // making the whole banner shout, and it distinguishes the two states by form as
                // well as by wording.
                Rectangle()
                    .fill(banner == .cannotReport ? theme.colors.danger : theme.colors.primary)
                    .frame(width: 4)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var title: String {
        switch banner {
        case .cannotReport: return "Your location isn't being shared"
        case .foregroundOnly: return "Only sharing while Findly is open"
        case .none: return ""
        }
    }

    /// Says what is happening, what the consequence is, and how to fix it — no apology, no blame
    /// for having refused. Refusing is a legitimate choice; the app's job is to be honest that it
    /// changes what the family sees.
    private var message: String {
        switch banner {
        case .cannotReport:
            return "Findly can't access your location, so your family can't see where you are. "
                + "You can still see everyone else. Turn on location access to start sharing again."
        case .foregroundOnly:
            return "Your location updates only while Findly is open on screen. "
                + "Allow location access all the time to keep your family up to date in the background."
        case .none:
            return ""
        }
    }
}
