import SwiftUI

/// specs/009-device-runtime.md §7 — the prominent disclosure, shown **before** the OS permission
/// prompt.
///
/// This is a policy requirement, not a nicety: Play's background-location review expects an in-app
/// screen that states what is collected, why, and who sees it, *ahead* of the system dialog, and
/// asks for a recording of that flow. Apple asks the same question in different words via the
/// purpose strings. It is also simply the honest ordering — the system dialog is a yes/no with no
/// room to explain why a family locator wants background location.
///
/// Two kinds, deliberately separate screens (003 §11.2): Android 11+ forbids bundling the
/// foreground and background asks in one dialog, so each gets its own explanation immediately
/// before its own prompt.
///
/// Composes design-system components only, and holds no state: acknowledgement is written by the
/// caller through `PermissionDisclosureStateStoring`, and what to show next is decided by
/// `PermissionFlowPolicy`.
public struct PermissionDisclosureScreen: View {
    @Environment(\.theme) private var theme
    private let kind: PermissionDisclosureKind
    private let onContinue: () -> Void
    private let onNotNow: () -> Void

    public init(
        kind: PermissionDisclosureKind,
        onContinue: @escaping () -> Void,
        onNotNow: @escaping () -> Void
    ) {
        self.kind = kind
        self.onContinue = onContinue
        self.onNotNow = onNotNow
    }

    public var body: some View {
        VStack(spacing: 0) {
            FindlyNavBar(title)
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.md) {
                    Text(headline)
                        .font(theme.typography.titleLarge)
                        .foregroundColor(theme.colors.onSurface)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: theme.spacing.sm) {
                        ForEach(points, id: \.self) { point in
                            HStack(alignment: .top, spacing: theme.spacing.sm) {
                                // A plain bullet, not an icon set: these are three sentences of
                                // disclosure, and decorating them would undercut the tone.
                                Text("•")
                                    .font(theme.typography.bodyLarge)
                                    .foregroundColor(theme.colors.primary)
                                Text(point)
                                    .font(theme.typography.bodyMedium)
                                    .foregroundColor(theme.colors.onSurface)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    Text(closing)
                        .font(theme.typography.bodyMedium)
                        .foregroundColor(theme.colors.onSurface.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(theme.spacing.md)
            }

            VStack(spacing: theme.spacing.sm) {
                FindlyButton(continueTitle, action: onContinue)
                // "Not now" must be a real, equally reachable choice — a disclosure that only
                // offers agreement is a dark pattern, and reviewers do notice. Declining is
                // non-fatal here: the family map still works, this device just doesn't report.
                FindlyButton("Not now", style: .secondary, action: onNotNow)
            }
            .padding(theme.spacing.md)
            .background(theme.colors.surface)
        }
        .background(theme.colors.surfaceVariant)
    }

    private var title: String {
        switch kind {
        case .foreground: return "Sharing your location"
        case .background: return "Sharing in the background"
        }
    }

    private var headline: String {
        switch kind {
        case .foreground:
            return "Findly shares your location with your family"
        case .background:
            return "Keep sharing when Findly isn't open"
        }
    }

    /// The three things a disclosure has to answer: what is collected, what it is used for, and who
    /// can see it. Written plainly — a family member reads this, not a lawyer.
    private var points: [String] {
        switch kind {
        case .foreground:
            return [
                "Findly collects this device's location so it can appear on your family's map.",
                "Only people in the families and groups you have joined can see it. It is never sold or shared with anyone else.",
                "You can pause sharing at any time in Settings, and delete your history and account from inside the app.",
            ]
        case .background:
            return [
                "To keep the map up to date, Findly needs to collect your location even when the app is closed or not in use.",
                "This is what lets your family see where you are without you opening the app, and what makes arrival and departure alerts work for places like home or school.",
                "Background updates follow the interval you choose in Settings, and stop entirely when you pause sharing.",
            ]
        }
    }

    private var closing: String {
        switch kind {
        case .foreground:
            return "On the next screen, iOS will ask for permission. Choosing “Don't Allow” keeps everything else working — you just won't appear on the map."
        case .background:
            return "On the next screen, iOS will ask whether Findly can always use your location. You can change this at any time in iOS Settings."
        }
    }

    private var continueTitle: String {
        switch kind {
        case .foreground: return "Continue"
        case .background: return "Allow in the background"
        }
    }
}
