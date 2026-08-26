import Foundation

/// specs/004-ios-client.md §1.2, §2.4 — owns the current route. Contains zero styling; the app
/// target's root view switches on `route` to pick which screen (composed from design-system
/// components) to show.
@MainActor
public final class AppCoordinator: ObservableObject {
    /// specs/004-ios-client.md §2.5 — the back stack. **Invariant: never empty.** Every mutating
    /// method below preserves that, so `route`'s `last!` is total, not a latent crash.
    ///
    /// This used to be a single `@Published var route`, i.e. a router with no history. On a
    /// platform with no hardware back button that made every `showX()` a one-way door — the user
    /// could reach Geofences/LiveMap/History/PrivacySettings/… and had no way out short of killing
    /// the app. Publishing the stack (rather than the derived `route`) is what drives SwiftUI
    /// updates; `route` is computed from it so every existing call site and test reads unchanged.
    @Published public private(set) var stack: [AppRoute]

    /// The screen currently on top of the stack.
    public var route: AppRoute { stack[stack.count - 1] }

    /// specs/004 §2.5 — the single source of truth for whether a back affordance is shown.
    /// `RootView` reads this once, centrally; no screen decides it for itself.
    public var canGoBack: Bool { stack.count > 1 }

    /// specs/004-ios-client.md §3.5, specs/007-public-join-links.md §1 — the deployment constant
    /// `handleDeepLink` matches https universal links against (`AppConfig.joinLinkHost`).
    private let joinLinkHost: String

    /// Defaults to `.launching` (specs/004 §2.6) — deliberately NOT `.signIn`, which would both
    /// flash a sign-in screen at every launch for a restored session and require reading
    /// `currentUserId` this early. See `AppRoute.launching` for what that early read does to
    /// Firebase's own initialization.
    public init(route: AppRoute = .launching, joinLinkHost: String = AppConfig.defaultJoinLinkHost) {
        self.stack = [route]
        self.joinLinkHost = joinLinkHost
    }

    /// specs/004 §2.6, specs/010 §1.1 — called once by `RootView` on first appear, when
    /// `UIApplication.shared` genuinely exists and reading the auth session is therefore safe. The
    /// caller (`RootView`) resolves the actual `LaunchDestination` via `AppLaunchResolver` (the
    /// `GET /families/me` probe, run BEFORE any device registration) — this method only applies
    /// the result to the stack.
    ///
    /// **Idempotent by design.** SwiftUI's `.task` can re-run (view identity changes, scene
    /// reattachment), and re-resolving would yank a user who has since navigated elsewhere back to
    /// a root. It therefore only acts while the stack is still exactly `[.launching]`.
    public func resolveLaunch(destination: LaunchDestination) {
        guard stack == [.launching] else { return }
        stack = [Self.route(for: destination)]
    }

    /// specs/010 §1.1 — an interactive sign-in resolves through the exact SAME launch-resolution
    /// table `resolveLaunch` uses (unlike the pre-010 code, which went straight to the retired
    /// `.home` unconditionally regardless of profile state — a brand-new phone-auth signup used to
    /// land on Home's own internal `.profileless` branch instead of anywhere the router knew
    /// about). NOT gated on `stack == [.launching]`: sign-in is reached from `.signIn`, never
    /// `.launching`, so `resolveLaunch`'s idempotency guard doesn't apply here.
    public func showPostSignIn(_ destination: LaunchDestination) {
        stack = [Self.route(for: destination)]
    }

    private static func route(for destination: LaunchDestination) -> AppRoute {
        switch destination {
        case .signIn: return .signIn
        case .familyMap: return .liveMap
        case .onboarding(let variant): return .onboarding(variant)
        }
    }

    // MARK: - Stack primitives (specs/004 §2.5)

    /// Pushes unless `route` is already on top — a double tap must not stack a duplicate that
    /// then needs two backs to escape.
    private func push(_ route: AppRoute) {
        guard route != self.route else { return }
        // `.launching` is a splash, not a navigation entry — anything that navigates REPLACES it
        // rather than stacking on top. Otherwise a cold start via a join link (`onOpenURL` can
        // arrive before `RootView`'s `.task` resolves the launch) would leave the splash sitting
        // behind the join screen, and backing out would reveal it.
        if stack == [.launching] {
            stack = [route]
            return
        }
        stack.append(route)
    }

    /// Undo the last push. A no-op at the root: the stack never empties, so there is always a
    /// screen to render.
    public func pop() {
        guard canGoBack else { return }
        stack.removeLast()
    }

    /// Unwind to an *existing* entry — the counterpart to Android's
    /// `popBackStack(route, inclusive = false)`, used by terminal callbacks that mean "this flow
    /// is over, return to the screen that started it" (e.g. leaving a group returns to the groups
    /// list). Distinct from `push`: re-pushing the destination would leave the just-finished
    /// screen sitting *behind* it, so back would walk into a group the user has already left.
    ///
    /// If `route` isn't on the stack at all — reachable when a cold-start deep link opened this
    /// flow directly, so the caller's "return to" screen was never visited — rebuild a minimal
    /// sane stack under it rather than stranding the user on a finished screen.
    public func popTo(_ route: AppRoute) {
        if let index = stack.lastIndex(of: route) {
            stack.removeSubrange((index + 1)...)
        } else if route == .liveMap {
            stack = [.liveMap]
        } else {
            stack = [.liveMap, route]
        }
    }

    // MARK: - Navigation roots (specs/004 §2.5, specs/010 §1.1/§2.2)
    //
    // These RESET the stack rather than pushing. You can never go "back" into a sign-in screen or
    // an Onboarding screen, and the Family Map is the top of the app. The reset is also what
    // guarantees no authenticated screen stays reachable behind sign-in after a sign-out / account
    // deletion (specs/008 §4.4).

    public func showSignIn() {
        stack = [.signIn]
    }

    /// specs/010 §1.1 — the renamed `showHome()`; the reset-the-stack semantics are unchanged, only
    /// the target changed (the retired `.home` hub -> the Family Map, now the app's root screen).
    public func showRoot() {
        stack = [.liveMap]
    }

    /// specs/010 §2.2 — Onboarding is a root: no back affordance, no drawer. Reached from the
    /// launch/sign-in resolution (§1.1) or from a feature screen's load path hitting a confirmed
    /// `PROFILE_NOT_FOUND`/`FAMILY_NOT_FOUND` (§2.1) — either way there is nothing behind it worth
    /// going back to, since every family screen would fail the same way.
    public func showOnboarding(_ variant: OnboardingVariant) {
        stack = [.onboarding(variant)]
    }

    // MARK: - I2 feature-screen routes

    public func showHistory(userId: String, deviceId: String? = nil) {
        push(.history(userId: userId, deviceId: deviceId))
    }

    public func showGeofences() {
        push(.geofences)
    }

    public func showLocate(target: LocateTarget, targetDisplayName: String) {
        push(.locate(target: target, targetDisplayName: targetDisplayName))
    }

    public func showDeviceSettings(isParent: Bool) {
        push(.deviceSettings(isParent: isParent))
    }

    public func showFamilyMembers() {
        push(.familyMembers)
    }

    public func showCreateInvite() {
        push(.createInvite)
    }

    public func showAcceptInvite(prefillCode: String = "") {
        push(.acceptInvite(prefillCode: prefillCode))
    }

    // MARK: - I17 profile-bootstrap route (001 §1.5.3, §3.1)

    public func showCreateFamily() {
        push(.createFamily)
    }

    // MARK: - I5 groups routes (specs/004 §3.4)

    public func showGroupsList() {
        push(.groupsList)
    }

    public func showCreateGroup() {
        push(.createGroup)
    }

    public func showGroupDetail(groupId: String) {
        push(.groupDetail(groupId: groupId))
    }

    public func showGroupJoin(prefillCode: String = "") {
        push(.groupJoin(prefillCode: prefillCode))
    }

    public func showGroupMap(groupId: String) {
        push(.groupMap(groupId: groupId))
    }

    // MARK: - I8 privacy routes (specs/004 §3.6; specs/008)

    public func showPrivacySettings() {
        push(.privacySettings)
    }

    public func showExportData() {
        push(.exportData)
    }

    public func showDeleteAccount() {
        push(.deleteAccount)
    }

    public func showDeleteFamily() {
        push(.deleteFamily)
    }

    /// The app target's `onOpenURL` forwards here (specs/004 §3.4/§3.5, specs/007 §4) —
    /// `GroupCodeParsing`/`InviteCodeParsing` (pure, FindlyKit) validate/normalize the incoming
    /// link BEFORE any route change. Four forms are recognized, each routing to its own screen and
    /// never the other's (007 §7: "`/f` never routes to the group-join screen, nor `/g` to the
    /// family one"): the legacy `findly://group-join?code=…` / `findly://family-join?code=…`
    /// schemes (unchanged behavior — an unrecognized/codeless link is silently ignored, no route
    /// change, no crash) and, since 007, the `https://{joinLinkHost}/g#CODE` /
    /// `https://{joinLinkHost}/f#CODE` universal links, where a recognized host+path with no
    /// usable fragment DOES route with an empty prefill (007 §4 / 003 §12.3) — a deliberate
    /// difference from the `findly://` case, since only the https form's contract specifies that
    /// behavior. A URL matching none of the four forms is silently ignored, rather than surfacing
    /// a raw error for what may be an unrelated/malformed external URL.
    /// specs/004 §2.5: a link arriving while the app is already running **pushes**, so dismissing
    /// the destination screen returns the user wherever they were rather than dropping them at a
    /// root. An unrecognized link still changes nothing at all — it must not grow the stack either.
    public func handleDeepLink(_ url: URL) {
        if let code = GroupCodeParsing.normalize(url.absoluteString) {
            push(.groupJoin(prefillCode: code))
            return
        }
        // The family-invite deep link only, NOT `InviteCodeParsing.normalize(_:)`'s full breadth
        // — that broader function also accepts the legacy `findly://invite/<code>` PATH form
        // (kept for `AcceptInviteViewModel`'s own paste handling, specs/004 I2), which
        // `handleDeepLink` has never routed and must keep NOT routing here
        // (`handleDeepLink_inviteDeepLink_isIgnoredNotMisroutedToGroupJoin`'s existing contract).
        if let rawCode = CodeLinkParsing.extractQueryCode(from: url, expectedHost: "family-join"),
           let code = CodeLinkParsing.normalizeCode(rawCode) {
            push(.acceptInvite(prefillCode: code))
            return
        }
        if case .recognized(let code) = GroupCodeParsing.matchHttpsJoinLink(url, joinLinkHost: joinLinkHost) {
            push(.groupJoin(prefillCode: code ?? ""))
            return
        }
        if case .recognized(let code) = InviteCodeParsing.matchHttpsInviteLink(url, joinLinkHost: joinLinkHost) {
            push(.acceptInvite(prefillCode: code ?? ""))
        }
    }
}
