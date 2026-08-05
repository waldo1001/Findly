import Foundation

/// specs/009-device-runtime.md §7 — drives the disclosure/prompt/banner sequence.
///
/// **Why the sequencing lives here and not in a view.** §7's core requirement is an ordering: the
/// explanation must come *before* the OS prompt. That is a statement about what must not happen
/// yet, and if it lives inside a SwiftUI view this project cannot verify it at all — there is no
/// rendering harness (I18), and the simulator's permission alert is drawn by SpringBoard and
/// ignores injected taps. Held in a plain `ObservableObject`, "no prompt fired while a disclosure
/// is pending" becomes an ordinary assertion, which is exactly what `PermissionFlowViewModelTests`
/// makes.
///
/// Holds no policy of its own: every decision comes from `PermissionFlowPolicy`.
@MainActor
public final class PermissionFlowViewModel: ObservableObject {
    /// Non-nil while an explanation is on screen. **No OS prompt may fire while this is set.**
    @Published public private(set) var disclosure: PermissionDisclosureKind?
    @Published public private(set) var banner: PermissionBanner = .none

    private let authorization: () -> LocationAuthorization
    private let requiresBackground: () -> Bool
    private let disclosureStore: PermissionDisclosureStateStoring
    private let requestForeground: () -> Void
    private let requestBackgroundUpgrade: () -> Void

    /// Session-only, deliberately not persisted (009 §7's "dismissible-per-session") — a device
    /// that cannot report is re-surfaced next launch rather than staying silently broken.
    private var bannerDismissedThisSession = false

    /// Set when the user picks "Not now", so the foreground re-check does not re-present the same
    /// screen every time the app comes back. Session-only too: declining today should not silence
    /// the explanation forever, but it must not become a loop the user cannot escape either.
    private var declinedThisSession: Set<PermissionDisclosureKind> = []

    public init(
        authorization: @escaping () -> LocationAuthorization,
        requiresBackground: @escaping () -> Bool,
        disclosureStore: PermissionDisclosureStateStoring,
        requestForeground: @escaping () -> Void,
        requestBackgroundUpgrade: @escaping () -> Void
    ) {
        self.authorization = authorization
        self.requiresBackground = requiresBackground
        self.disclosureStore = disclosureStore
        self.requestForeground = requestForeground
        self.requestBackgroundUpgrade = requestBackgroundUpgrade
    }

    /// Re-evaluate. Called on first appear and on **every app foreground** — §7 requires the
    /// re-check because the user can revoke permission from system settings at any time, and the
    /// app must notice rather than keep believing it is reporting.
    public func refresh() {
        let auth = authorization()
        let needsBackground = requiresBackground()

        banner = PermissionFlowPolicy.banner(
            authorization: auth,
            requiresBackground: needsBackground,
            dismissedThisSession: bannerDismissedThisSession
        )

        let step = PermissionFlowPolicy.nextStep(
            authorization: auth,
            foregroundDisclosureAcknowledged: disclosureStore.isAcknowledged(.foreground),
            backgroundDisclosureAcknowledged: disclosureStore.isAcknowledged(.background),
            requiresBackground: needsBackground
        )

        switch step {
        case .showDisclosure(let kind):
            // Suppressed only for a kind declined in THIS session — see `declinedThisSession`.
            disclosure = declinedThisSession.contains(kind) ? nil : kind
        case .requestForeground, .requestBackgroundUpgrade, .none:
            // Deliberately does NOT fire the prompt from here. `refresh()` runs on every foreground;
            // prompting from it would re-ask on each return from Settings. The prompt is fired
            // exactly once, by `acknowledgeDisclosure()`, as the user's own next action.
            disclosure = nil
        }
    }

    /// The user read the explanation and chose to continue: record it, close the screen, and only
    /// now fire the OS prompt.
    public func acknowledgeDisclosure() {
        guard let kind = disclosure else { return }
        disclosureStore.acknowledge(kind)
        disclosure = nil

        switch kind {
        case .foreground: requestForeground()
        case .background: requestBackgroundUpgrade()
        }
    }

    /// "Not now". A real choice: no prompt, no acknowledgement recorded, and not re-presented for
    /// the rest of this session.
    public func declineDisclosure() {
        guard let kind = disclosure else { return }
        declinedThisSession.insert(kind)
        disclosure = nil
    }

    public func dismissBanner() {
        bannerDismissedThisSession = true
        banner = .none
    }
}
