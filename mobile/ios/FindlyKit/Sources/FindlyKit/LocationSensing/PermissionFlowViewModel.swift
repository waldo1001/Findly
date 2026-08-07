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
    /// specs/009 §7 (I31, mirrors A25) — non-nil when the banner's action should re-open the
    /// full-screen disclosure (the OS was never actually asked for that kind); `nil` when the OS
    /// itself has already irrevocably refused, so the only route back is system settings. See
    /// `PermissionFlowPolicy.bannerReopenKind`'s doc for why `authorization` alone cannot decide
    /// this — the acknowledged/declined distinction is load-bearing.
    @Published public private(set) var bannerReopenKind: PermissionDisclosureKind?

    private let authorization: () -> LocationAuthorization
    private let requiresBackground: () -> Bool
    private let disclosureStore: PermissionDisclosureStateStoring
    private let requestForeground: () -> Void
    private let requestBackgroundUpgrade: () -> Void

    /// Session-only, deliberately not persisted (009 §7's "dismissible-per-session") — a device
    /// that cannot report is re-surfaced next launch rather than staying silently broken.
    private var bannerDismissedThisSession = false

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
        let foregroundAcknowledged = disclosureStore.isAcknowledged(.foreground)
        let backgroundAcknowledged = disclosureStore.isAcknowledged(.background)
        // I31 (mirrors A25): "Not now" is persisted (disclosureStore.isDeclined), so nextStep()
        // itself already returns .none for a declined kind — no more session-only in-memory filter
        // here. That in-memory set was exactly the bug: it reset on every cold launch, so a fresh
        // process always saw an empty decline set and re-showed the disclosure regardless of what
        // the user had already answered.
        let foregroundDeclined = disclosureStore.isDeclined(.foreground)
        let backgroundDeclined = disclosureStore.isDeclined(.background)

        banner = PermissionFlowPolicy.banner(
            authorization: auth,
            requiresBackground: needsBackground,
            foregroundDisclosureDeclined: foregroundDeclined,
            dismissedThisSession: bannerDismissedThisSession
        )

        // I31 (mirrors A25 round-1 Major 1): computed on every refresh so the banner's action never
        // dead-ends — see `PermissionFlowPolicy.bannerReopenKind`'s doc for why `authorization`
        // alone cannot decide "reopen the disclosure" vs "route to system settings".
        bannerReopenKind = PermissionFlowPolicy.bannerReopenKind(
            authorization: auth,
            foregroundDisclosureAcknowledged: foregroundAcknowledged,
            backgroundDisclosureAcknowledged: backgroundAcknowledged
        )

        let step = PermissionFlowPolicy.nextStep(
            authorization: auth,
            foregroundDisclosureAcknowledged: foregroundAcknowledged,
            foregroundDisclosureDeclined: foregroundDeclined,
            backgroundDisclosureAcknowledged: backgroundAcknowledged,
            backgroundDisclosureDeclined: backgroundDeclined,
            requiresBackground: needsBackground
        )

        switch step {
        case .showDisclosure(let kind):
            disclosure = kind
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

    /// "Not now" (I31, mirrors A25, 009 §7). A real choice: no prompt, no acknowledgement recorded
    /// — and now persisted via `disclosureStore.decline`, so it is not re-presented on ANY future
    /// launch or foreground, not just for the rest of this session. Only an explicit action on the
    /// banner (`reopenDisclosure()`) brings it back.
    public func declineDisclosure() {
        guard let kind = disclosure else { return }
        disclosureStore.decline(kind)
        disclosure = nil
    }

    public func dismissBanner() {
        bannerDismissedThisSession = true
        banner = .none
    }

    /// The banner's explicit action when `bannerReopenKind` is non-nil (009 §7, I31/mirrors A25):
    /// forgets the prior decline for that kind only, then re-evaluates — which re-presents the
    /// full-screen disclosure since nothing else about the underlying state changed. A no-op when
    /// `bannerReopenKind` is `nil` (the OS was already asked; the caller should route to system
    /// settings instead).
    public func reopenDisclosure() {
        guard let kind = bannerReopenKind else { return }
        disclosureStore.clearDeclined(kind)
        refresh()
    }
}
