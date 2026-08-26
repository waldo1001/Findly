import SwiftUI
import FindlyKit

/// The presentation root — resolves `.light`/`.dark` from the system `colorScheme` and injects
/// `\.theme` (specs/004-ios-client.md §2.2); everything below this reads `\.theme`, never
/// `colorScheme` directly.
///
/// **Post-review correction (Major finding #4): NOT the composition root any more.** This used to
/// construct `authProvider`/`apiClient`/`SQLiteFixStore`/`LocationRuntimeContainer` itself — but a
/// standalone minimal SwiftUI reproduction confirmed `RootView.init()` reruns on every
/// `coordinator.route` publish (this view holds `coordinator` via `@ObservedObject` while
/// `AppCoordinator` is a `@StateObject` in `FindlyApp`), i.e. on every in-app navigation, not once
/// per launch. Building a live `CLLocationManager`/fresh SQLite connection/`FixQueue` actor inside
/// something that reruns that often silently multiplied them across navigations. Every one of
/// those objects is now built exactly once in `FindlyApp.init()` (SwiftUI-guaranteed to run once
/// per process launch) and handed in here as plain, cheap-to-reassign `let` parameters — so however
/// many times SwiftUI reconstructs this value, it only ever re-references the SAME already-built
/// instances, never rebuilds them.
///
/// `@MainActor`-isolated (explicit, not left to inference) to match `LocationRuntimeContainer`
/// (specs/009-device-runtime.md, I10), whose `stop()` this view calls directly from its body.
@MainActor
struct RootView: View {
    @Environment(\.colorScheme) private var colorScheme
    // specs/009-device-runtime.md §3.4 (trigger 3: foreground) / §4 (the paused-device poll's
    // "every app foreground" requirement) — the one bit of genuine OS-lifecycle *signal* (not
    // logic: the reaction lives entirely in `LocationRuntimeContainer.onAppForeground()`) the app
    // target needs to observe.
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var coordinator: AppCoordinator

    private let authProvider: AuthProviding
    private let apiClient: FindlyAPIClient
    // specs/004-ios-client.md §3.5, specs/007-public-join-links.md §1 — threaded into
    // `GroupDetailScreen` for its share link/QR (`AppConfig.joinLinkHost`).
    private let joinLinkHost: String
    // specs/004-ios-client.md §3.6, specs/008-privacy-endpoints.md §4.4 — as of I10, this is also
    // the SAME instance `LocationRuntimeContainer`'s `deviceId` closure and `onReRegisterDevice`'s
    // re-registration path read/clear (built once, in `FindlyApp.init()`).
    private let deviceIdProvider: DeviceIdProviding
    // specs/009-device-runtime.md (I10) — the real capture/sync engine, built once in
    // `FindlyApp.init()` and passed in here (see this type's top doc for why it can no longer be
    // constructed in THIS init). Post-review (security review, High finding): `DeleteAccountViewModel`
    // no longer takes `fixQueue`/`geofenceEventQueue`/`geofenceConfigStore` directly — it takes the
    // single consolidated `locationRuntimeContainer.wipeLocalState()` closure instead (see the
    // `.deleteAccount` case below), so this type no longer needs a separate `fixQueue` property of
    // its own at all.
    private let locationRuntimeContainer: LocationRuntimeContainer
    // specs/008-privacy-endpoints.md §3.1 — ONE shared instance between `ExportViewModel` (which
    // writes the artifact) and `DeleteAccountViewModel` (whose local wipe must remove it, rule 2)
    // — two independent stores would let the wipe clear an artifact `ExportScreen` never wrote to.
    // The real on-disk implementation (app-private storage + `.completeFileProtection` + backup
    // exclusion, specs/008 §3.1 rules 1/4) — never the in-memory test fake — is what a real device
    // build always gets here.
    private let exportArtifactStore: ExportArtifactStoring
    // specs/008-privacy-endpoints.md §1.3, specs/004-ios-client.md §3.6 (I25) — the SAME instance
    // `DeviceRegistrationService` (built once in `FindlyApp.init()`) reads to decide whether
    // `registerOrUpdate()` needs to probe for a profile; `DeleteAccountViewModel`'s local wipe must
    // clear it here for exactly the same reason it clears `deviceIdProvider`.
    private let appVersionTracker: AppVersionRegistrationTracking
    // specs/009-device-runtime.md §5 (I12) — device re-registration + push-notification
    // registration, run once at cold launch (in `FindlyApp.init()`, if already signed in) and
    // again here once `SignInViewModel` reports a fresh interactive sign-in (a session that starts
    // at the sign-in screen never got the cold-launch call, since nobody was signed in yet then).
    private let onSignedIn: () async -> Void
    // specs/010-app-shell-and-screen-ux.md §1.2 — the shared drawer-header cache, built once in
    // `FindlyApp.init()` (same pattern as every other object above). `@ObservedObject`, not
    // `@StateObject`: this is one long-lived instance handed in from outside, never constructed by
    // this view itself.
    @ObservedObject private var familyContextCache: FamilyContextCache
    // I17 (001 §1.5.3) — the display name typed once on the Onboarding screen's profile-less
    // variant, carried (still editable at the destination) to whichever of the four bootstrap paths the
    // user picks — same "remembered local state instead of a nav-graph argument" pattern Android's
    // `FindlyNavHost` uses for its `pendingOnboardingDisplayName`/`pendingCreateContext`/
    // `pendingJoinContext` (specs/003 §12.2/A21), chosen here too so `AppRoute`'s existing,
    // already-tested cases (`.groupJoin(prefillCode:)` etc., `AppCoordinatorTests`) stay untouched
    // rather than growing a second associated value. This is prefill-only, purely a UX convenience
    // (skip re-typing a name already typed once) — it is NOT how `CreateGroupViewModel`/
    // `GroupJoinViewModel` decide whether a blank name is actually required; those establish that
    // themselves from the server's own profile state (I17 review, Major finding: a caller-supplied
    // "which button was tapped" flag is wrong for arrivals that don't go through these closures at
    // all, e.g. a `findly://group-join` deep link).
    @State private var pendingOnboardingDisplayName = ""
    @State private var pendingGroupBootstrapDisplayName = ""
    // specs/010-app-shell-and-screen-ux.md §2.2/§6 (I34) — `.createGroup`/`.groupJoin` are shared
    // between two entry points: the ORDINARY one (`GroupsListScreen`'s own buttons, an unchanged
    // flow per 010 §6's inventory delta) and the Onboarding screen's profile-less bootstrap
    // buttons. Only the latter's success should reset to the Family Map root (010 §2.2's "on any
    // bootstrap success" rule); the ordinary path keeps its existing "go to the new group's detail"
    // behavior. Same "remembered local state" pattern as `pendingGroupBootstrapDisplayName` above.
    @State private var groupBootstrapReturnsToOnboarding = false

    /// specs/009-device-runtime.md §7 — owns the disclosure/prompt/banner ordering. `@StateObject`,
    /// not `@ObservedObject`: this view is reconstructed on every navigation (see this type's top
    /// doc, and I16), and an `@ObservedObject` here would hand the screen a fresh view model each
    /// time — losing the "declined this session" and "banner dismissed" flags, so a user who
    /// dismissed the banner would see it again on their next tap.
    @StateObject private var permissionFlow: PermissionFlowViewModel

    init(
        coordinator: AppCoordinator,
        config: AppConfig,
        authProvider: AuthProviding,
        apiClient: FindlyAPIClient,
        deviceIdProvider: DeviceIdProviding,
        exportArtifactStore: ExportArtifactStoring,
        appVersionTracker: AppVersionRegistrationTracking,
        locationRuntimeContainer: LocationRuntimeContainer,
        onSignedIn: @escaping () async -> Void,
        familyContextCache: FamilyContextCache
    ) {
        self.coordinator = coordinator
        self.joinLinkHost = config.joinLinkHost
        self.authProvider = authProvider
        self.apiClient = apiClient
        self.deviceIdProvider = deviceIdProvider
        self.exportArtifactStore = exportArtifactStore
        self.appVersionTracker = appVersionTracker
        self.locationRuntimeContainer = locationRuntimeContainer
        self.onSignedIn = onSignedIn
        self.familyContextCache = familyContextCache
        // specs/009 §7. Built from the container's read-only seams rather than a second
        // CLLocationManager, so the authorization this reports is the one the capture stack uses.
        //
        // I31 fix (mirrors A25's Major 2 / the I26 pattern): `disclosureStore` used to be a
        // STANDALONE `UserDefaultsPermissionDisclosureStore()` built right here — a different
        // instance from anything `LocationRuntimeContainer.wipeLocalState()` could reach, so its
        // documented "part of the account-deletion local wipe" comment was a promise nothing kept.
        // Now it is `locationRuntimeContainer.permissionDisclosureStore` — the SAME instance the
        // container's own `wipeLocalState()` clears — so this view model and the wipe path can
        // never disagree about what has been acknowledged/declined.
        _permissionFlow = StateObject(wrappedValue: PermissionFlowViewModel(
            authorization: { [weak locationRuntimeContainer] in
                locationRuntimeContainer?.locationAuthorization ?? .notDetermined
            },
            requiresBackground: { [weak locationRuntimeContainer] in
                locationRuntimeContainer?.requiresBackgroundLocation ?? false
            },
            disclosureStore: locationRuntimeContainer.permissionDisclosureStore,
            requestForeground: { [weak locationRuntimeContainer] in
                locationRuntimeContainer?.requestForegroundAuthorization()
            },
            requestBackgroundUpgrade: { [weak locationRuntimeContainer] in
                locationRuntimeContainer?.requestBackgroundAuthorizationUpgrade()
            }
        ))
    }

    var body: some View {
        // specs/009 §7 — the banner sits ABOVE the screen content, so a device that is not
        // reporting says so on whatever screen the user is looking at, not only on one of them.
        VStack(spacing: 0) {
            PermissionBannerView(
                banner: permissionFlow.banner,
                reopensDisclosure: permissionFlow.bannerReopenKind != nil,
                onOpenSettings: { openSystemSettings() },
                onReopenDisclosure: { permissionFlow.reopenDisclosure() },
                onDismiss: { permissionFlow.dismissBanner() }
            )
            content
        }
        // The disclosure is a full-screen cover, not a sheet: it must be answered before the OS
        // prompt fires, and a swipe-to-dismiss sheet would let the user skip past the explanation
        // into a prompt they were never given context for.
        .fullScreenCover(
            item: Binding(
                get: { permissionFlow.disclosure },
                // Only reachable if SwiftUI dismisses the cover itself; treat that as "Not now"
                // rather than as consent, since the user has not read and accepted anything.
                set: { if $0 == nil { permissionFlow.declineDisclosure() } }
            )
        ) { kind in
            PermissionDisclosureScreen(
                kind: kind,
                onContinue: { permissionFlow.acknowledgeDisclosure() },
                onNotNow: { permissionFlow.declineDisclosure() }
            )
            .environment(\.theme, colorScheme == .dark ? .dark : .light)
            // The cover is presented outside the main hierarchy, so it does not inherit the back
            // action — but clear it explicitly for the same reason `GeofenceEditorView` does
            // (specs/004 §2.5): a back chevron here would navigate the app behind the cover.
            .environment(\.navBarBackAction, nil)
        }
    }

    /// specs/009 §7's "route into system settings" — the only way back once permission is denied,
    /// since iOS will not show its dialog a second time.
    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// specs/010-app-shell-and-screen-ux.md §1.1 (amended, row A37) — `AppLaunchResolver`'s
    /// `onConfirmedAuthFailure` seam, wired at both call sites below (cold-start restore and
    /// interactive sign-in). Deliberately the SAME two calls, in the SAME order, as `FindlyApp.
    /// swift`'s forced `onSignedOut` closure (009 §9's "second AUTH_TOKEN_EXPIRED" path) and
    /// `DeleteAccountViewModel.signOutForRetry()` — every session-ending path in this codebase
    /// wipes local state via the ONE `LocationRuntimeContainer.wipeLocalState()` method and then
    /// signs out, never a second wipe implementation (the I43 lesson). `coordinator.showSignIn()`
    /// is deliberately NOT called here: the caller already routes to `.signIn` from the
    /// `LaunchDestination` this closure's result feeds into.
    private func clearSessionOnConfirmedAuthFailure() async {
        await locationRuntimeContainer.wipeLocalState()
        try? authProvider.signOut()
    }

    private var content: some View {
        Group {
            switch coordinator.route {
            case .launching:
                // specs/004 §2.6 — the neutral splash shown until `.task` below resolves the real
                // route. Themed rather than blank so a restored session never flashes a sign-in
                // screen, and never flashes white either.
                LoadingStateView(message: "Findly")
            case .signIn:
                SignInScreen(
                    viewModel: SignInViewModel(authProvider: authProvider, onSignedIn: {
                        // specs/010-app-shell-and-screen-ux.md §1.1 — an interactive sign-in
                        // resolves through the EXACT SAME launch-resolution table a cold start
                        // does (below), rather than the pre-010 unconditional `.home`: a
                        // brand-new phone-auth signup has no profile yet.
                        Task {
                            let destination = await AppLaunchResolver.resolve(
                                apiClient: apiClient, isSignedIn: true, cache: familyContextCache,
                                onConfirmedAuthFailure: { await clearSessionOnConfirmedAuthFailure() }
                            )
                            coordinator.showPostSignIn(destination)
                        }
                        // specs/009-device-runtime.md §5 (I12) — device re-registration +
                        // push-notification registration on first launch after sign-in.
                        Task { await onSignedIn() }
                        // specs/009-device-runtime.md §6.2 (I11) — "first config sync after
                        // sign-in" is one of the five geofence re-registration triggers; see
                        // `LocationRuntimeContainer.onSignedIn()`'s doc for why this in-app
                        // callback (rather than the cold-start hook alone) is the trigger's home.
                        Task { await locationRuntimeContainer.onSignedIn() }
                    })
                )

            // MARK: - specs/010-app-shell-and-screen-ux.md §1/§6 (I34) — the Family Map is the
            // app's root; the retired Home hub's `.home` case is gone.

            case .liveMap:
                LiveMapScreen(
                    viewModel: LiveMapViewModel(apiClient: apiClient),
                    renderer: defaultMapRenderer,
                    familyContext: familyContextCache,
                    onSelectHistory: {
                        // 010 §1.2: History from the drawer targets the caller's OWN history —
                        // per-member history stays reachable only via map member selection (§3.5,
                        // I35), which this task does not implement.
                        coordinator.showHistory(userId: authProvider.currentUserId ?? "")
                    },
                    onSelectGeofences: { coordinator.showGeofences() },
                    onSelectDevices: { coordinator.showDeviceSettings(isParent: familyContextCache.isParent ?? false) },
                    onSelectFamily: { coordinator.showFamilyMembers() },
                    onSelectInviteSomeone: { coordinator.showCreateInvite() },
                    onSelectGroups: { coordinator.showGroupsList() },
                    onSelectPrivacySettings: { coordinator.showPrivacySettings() },
                    onLocateNow: { userId, displayName in
                        // specs/010-app-shell-and-screen-ux.md §3.5 (I35) — member selection's
                        // "Locate now" routes into the EXISTING Locate screen (001 §6, unchanged).
                        coordinator.showLocate(target: .user(userId), targetDisplayName: displayName)
                    },
                    onProfileDeadEnd: { variant in coordinator.showOnboarding(variant) }
                )

            // MARK: - specs/010-app-shell-and-screen-ux.md §2.2 (I34) — replaces the retired Home
            // hub's `.profileless`/`.familyless` branches. A root: no back, no drawer.

            case .onboarding(let variant):
                OnboardingScreen(
                    variant: variant,
                    prefillDisplayName: pendingOnboardingDisplayName,
                    onSelectCreateFamily: { name in
                        pendingOnboardingDisplayName = name
                        coordinator.showCreateFamily()
                    },
                    onSelectAcceptInvite: { name in
                        pendingOnboardingDisplayName = name
                        coordinator.showAcceptInvite()
                    },
                    onSelectCreateGroup: { name in
                        pendingGroupBootstrapDisplayName = name
                        groupBootstrapReturnsToOnboarding = true
                        coordinator.showCreateGroup()
                    },
                    onSelectJoinGroup: { name in
                        pendingGroupBootstrapDisplayName = name
                        groupBootstrapReturnsToOnboarding = true
                        coordinator.showGroupJoin()
                    },
                    onSelectGroups: { coordinator.showGroupsList() },
                    onSelectPrivacySettings: { coordinator.showPrivacySettings() }
                )
            case .history(let userId, let deviceId):
                HistoryScreen(
                    viewModel: HistoryViewModel(
                        apiClient: apiClient, userId: userId, deviceId: deviceId,
                        fromDate: Self.defaultFromDate(), toDate: Self.defaultToDate()
                    ),
                    onProfileDeadEnd: { variant in coordinator.showOnboarding(variant) }
                )
            case .geofences:
                GeofencesScreen(
                    viewModel: GeofencesViewModel(apiClient: apiClient),
                    onProfileDeadEnd: { variant in coordinator.showOnboarding(variant) }
                )
            case .locate(let target, let targetDisplayName):
                LocateScreen(
                    viewModel: LocateViewModel(apiClient: apiClient), target: target, targetDisplayName: targetDisplayName,
                    onProfileDeadEnd: { variant in coordinator.showOnboarding(variant) }
                )
            case .deviceSettings(let isParent):
                DeviceSettingsScreen(
                    viewModel: DeviceSettingsViewModel(apiClient: apiClient, isParent: isParent),
                    onProfileDeadEnd: { variant in coordinator.showOnboarding(variant) }
                )
            case .familyMembers:
                FamilyMembersScreen(
                    viewModel: FamilyMembersViewModel(apiClient: apiClient, familyContextCache: familyContextCache),
                    onProfileDeadEnd: { variant in coordinator.showOnboarding(variant) }
                )
            case .createInvite:
                // specs/007-public-join-links.md §1, specs/010-app-shell-and-screen-ux.md §5.1 —
                // same injected `joinLinkHost` instance `GroupDetailScreen` below already uses,
                // not the type's own `AppConfig.defaultJoinLinkHost` fallback (that default exists
                // only for previews/tests that don't wire a real config).
                CreateInviteScreen(viewModel: CreateInviteViewModel(apiClient: apiClient), joinLinkHost: joinLinkHost)
            case .acceptInvite(let prefillCode):
                AcceptInviteScreen(
                    viewModel: AcceptInviteViewModel(apiClient: apiClient),
                    prefillInviteCode: prefillCode,
                    prefillDisplayName: pendingOnboardingDisplayName,
                    // specs/010-app-shell-and-screen-ux.md §2.2/§5.2 — accept-invite is one of the
                    // four Onboarding bootstrap paths: on success, reset to the Family Map root
                    // (§1.1's post-bootstrap rule) rather than leaving the terminal "Welcome!"
                    // state on screen (§5.2's own retirement of that dead end — the invite
                    // create/accept UI polish itself stays I37's job; this is only the routing).
                    // I24 (001 §1.5.3, §4.1): also retries `onSignedIn` now that a profile exists —
                    // any device registration attempted before this point (e.g. at sign-in) hit
                    // `DeviceRegistrationError.profileNotYetBootstrapped` and was skipped.
                    onAccepted: {
                        coordinator.showRoot()
                        Task { await onSignedIn() }
                    }
                )

            // MARK: - I17 profile-bootstrap route (001 §1.5.3, §3.1) — see `CreateFamilyViewModel`'s
            // doc for why this is the client's only `POST /families` entry point.

            case .createFamily:
                CreateFamilyScreen(
                    viewModel: CreateFamilyViewModel(apiClient: apiClient),
                    prefillDisplayName: pendingOnboardingDisplayName,
                    onCreated: { _ in
                        // specs/010 §2.2 — reset to the Family Map root (was `showHome()`).
                        coordinator.showRoot()
                        // I24 — same re-registration retry as `.acceptInvite`'s `onAccepted` above.
                        Task { await onSignedIn() }
                    }
                )

            // MARK: - I5 groups routes (specs/004 §3.4) — unchanged flows (010 §6), except the
            // post-success destination when reached from Onboarding (010 §2.2) rather than the
            // ordinary `GroupsListScreen` entry point (`groupBootstrapReturnsToOnboarding` below).

            case .groupsList:
                GroupsListScreen(
                    viewModel: GroupsListViewModel(apiClient: apiClient),
                    onSelectGroup: { groupId in coordinator.showGroupDetail(groupId: groupId) },
                    onCreateGroup: {
                        // The ordinary (already-has-a-profile) entry point — never leak a stale
                        // prefill name/origin from an earlier onboarding visit. (Whether
                        // `displayName` is actually required is no longer decided here at all —
                        // see `CreateGroupViewModel.createGroup`'s doc, I17 review.)
                        pendingGroupBootstrapDisplayName = ""
                        groupBootstrapReturnsToOnboarding = false
                        coordinator.showCreateGroup()
                    },
                    onJoinGroup: {
                        pendingGroupBootstrapDisplayName = ""
                        groupBootstrapReturnsToOnboarding = false
                        coordinator.showGroupJoin()
                    }
                )
            case .createGroup:
                CreateGroupScreen(
                    viewModel: CreateGroupViewModel(apiClient: apiClient),
                    prefillDisplayName: pendingGroupBootstrapDisplayName,
                    onCreated: { group in
                        if groupBootstrapReturnsToOnboarding {
                            // specs/010 §2.2 — reached from Onboarding: reset to the Family Map
                            // root instead of the group's own detail screen. If this caller is
                            // STILL family-less (a groups-only user — creating a group never
                            // creates a family), the map's own 010 §2.1 routing rule bounces them
                            // straight back to Onboarding(family-less), which is the correct
                            // outcome, not a bug.
                            coordinator.showRoot()
                        } else {
                            // specs/004 §2.5: unwind the finished form OUT of the stack before
                            // pushing the new group's detail — otherwise back lands on a
                            // create-group form for a group that already exists.
                            coordinator.popTo(.groupsList)
                            coordinator.showGroupDetail(groupId: group.groupId)
                        }
                        // I24 — same re-registration retry as `.createFamily`'s `onCreated` above
                        // (create-group is also a 001 §1.5.3 profile-bootstrap path).
                        Task { await onSignedIn() }
                    }
                )
            case .groupDetail(let groupId):
                GroupDetailScreen(
                    viewModel: GroupDetailViewModel(apiClient: apiClient, groupId: groupId),
                    joinLinkHost: joinLinkHost,
                    onSelectMap: { coordinator.showGroupMap(groupId: groupId) },
                    // specs/004 §2.5: unwind to the groups list rather than pushing a second copy
                    // of it — pushing would leave this just-left group sitting behind it, so back
                    // would walk straight back into a group the user is no longer a member of.
                    onExit: { coordinator.popTo(.groupsList) }
                )
            case .groupJoin(let prefillCode):
                GroupJoinScreen(
                    viewModel: GroupJoinViewModel(apiClient: apiClient),
                    prefillCode: prefillCode,
                    prefillDisplayName: pendingGroupBootstrapDisplayName,
                    onJoined: { group in
                        if groupBootstrapReturnsToOnboarding {
                            // specs/010 §2.2 — same rationale as `.createGroup`'s `onCreated` above.
                            coordinator.showRoot()
                        } else {
                            // Same unwind rationale as `CreateGroupScreen`'s `onCreated` above.
                            // This also covers the cold-start deep-link arrival, where
                            // `.groupsList` was never visited: `popTo` rebuilds a minimal stack
                            // under it rather than leaving the user on a spent join form.
                            coordinator.popTo(.groupsList)
                            coordinator.showGroupDetail(groupId: group.groupId)
                        }
                        // I24 — same re-registration retry (join-group is also a 001 §1.5.3
                        // profile-bootstrap path).
                        Task { await onSignedIn() }
                    }
                )
            case .groupMap(let groupId):
                GroupMapScreen(
                    viewModel: GroupMapViewModel(apiClient: apiClient, groupId: groupId),
                    renderer: defaultMapRenderer,
                    // Same unwind rationale as `GroupDetailScreen`'s `onExit` above — this fires
                    // when the group has expired, so it must not stay reachable behind the list.
                    onExit: { coordinator.popTo(.groupsList) }
                )

            // MARK: - I8 privacy routes (specs/004 §3.6; specs/008-privacy-endpoints.md)

            case .privacySettings:
                PrivacySettingsScreen(
                    viewModel: PrivacySettingsViewModel(apiClient: apiClient),
                    onSelectExport: { coordinator.showExportData() },
                    onSelectDeleteAccount: { coordinator.showDeleteAccount() },
                    onSelectDeleteFamily: { coordinator.showDeleteFamily() }
                )
            case .exportData:
                ExportScreen(
                    viewModel: ExportViewModel(apiClient: apiClient, exportArtifactStore: exportArtifactStore),
                    onProfileDeadEnd: { variant in coordinator.showOnboarding(variant) }
                )
            case .deleteAccount:
                DeleteAccountScreen(
                    viewModel: DeleteAccountViewModel(
                        apiClient: apiClient, authProvider: authProvider,
                        deviceIdProvider: deviceIdProvider,
                        exportArtifactStore: exportArtifactStore,
                        appVersionTracker: appVersionTracker,
                        // Post-review (security review, High finding): the ONE consolidated
                        // LocationRuntimeContainer.wipeLocalState() — covers the fix queue,
                        // geofence-event queue, cached geofence config/ETag, cached device
                        // settings, AND unregisters this device's CLLocationManager geofences (that
                        // last part was unreachable from here entirely before this fix — see
                        // wipeLocalState()'s doc). The same closure FindlyApp's forced-sign-out path
                        // and DeleteAccountViewModel's own signOutForRetry() now call too.
                        wipeLocalState: { await locationRuntimeContainer.wipeLocalState() }
                    ),
                    // wipeLocalState() (called inside the view model's own local-wipe step) already
                    // stops monitoring/cancels the BG task as part of the consolidated wipe — no
                    // separate stop() call needed here any more.
                    onCompleted: { coordinator.showSignIn() }
                )
            case .deleteFamily:
                DeleteFamilyScreen(
                    viewModel: DeleteFamilyViewModel(apiClient: apiClient),
                    // specs/010-app-shell-and-screen-ux.md §1.1/§2.1 — deleting the family leaves
                    // the caller with a profile but no family (001 §13.3: role/familyId become
                    // null), i.e. exactly the family-less state — route straight to Onboarding's
                    // family-less variant rather than the Family Map root (which would 404
                    // FAMILY_NOT_FOUND on its very next load and bounce right back here anyway).
                    onCompleted: { coordinator.showOnboarding(.familyLess) }
                )
            }
        }
        // specs/004-ios-client.md §2.6 — resolve the launch route HERE, not in `FindlyApp.init()`.
        // This is the earliest point at which `UIApplication.shared` is guaranteed up, which is
        // what makes reading `currentUserId` (and therefore constructing `Auth.auth()`) safe: doing
        // it in `App.init()` made Firebase's own `protectedDataInitialization` fail its reflective
        // UIApplication lookup and return early, leaving `tokenManager` nil for the whole process
        // so the first APNs callback trapped. `resolveLaunch` is itself idempotent, since `.task`
        // can re-run on view-identity changes.
        //
        // The device/push registration below reads `currentUserId` too, so it moved here for the
        // same reason — it used to be a `Task` fired from `App.init()`.
        //
        // specs/010-app-shell-and-screen-ux.md §1.1 — the destination is no longer just
        // `isSignedIn`; `AppLaunchResolver` runs the `GET /families/me` probe (before any device
        // registration, and never for a signed-out caller) and resolves through the full
        // launch-resolution table, failing open to the Family Map on anything inconclusive.
        .task {
            let destination = await AppLaunchResolver.resolve(
                apiClient: apiClient, isSignedIn: authProvider.currentUserId != nil, cache: familyContextCache,
                onConfirmedAuthFailure: { await clearSessionOnConfirmedAuthFailure() }
            )
            coordinator.resolveLaunch(destination: destination)
            // specs/009 §7 — first evaluation of the disclosure/prompt/banner state. Deliberately
            // after the launch route resolves, so a signed-out user is asked to sign in before
            // being asked for their location: explaining family location-sharing to someone who has
            // no family yet is the wrong order.
            permissionFlow.refresh()
            await onSignedIn()
        }
        .environment(\.theme, colorScheme == .dark ? .dark : .light)
        // specs/004-ios-client.md §2.5 — the ONE back affordance decision for the whole app.
        // Non-nil exactly when the coordinator's stack has something to pop; every screen's own
        // `FindlyNavBar` picks this up from the environment and renders the button, so no screen
        // decides (or forgets) this for itself. iOS has no hardware back button — before this,
        // every screen reached via `showX()` was a dead end.
        .environment(\.navBarBackAction, coordinator.canGoBack ? { coordinator.pop() } : nil)
        // specs/009-device-runtime.md §3.4/§4 — the foreground opportunistic trigger + the
        // paused-device poll's "on every app foreground" requirement. `.active` fires on cold
        // launch too (harmless — `LocationSyncRunner.runOnce()` is idempotent-safe when there's
        // nothing queued, and `PausedDevicePoller.poll()` is a no-op unless something changed).
        // The single-parameter closure form (not the iOS 17+ two-parameter one) — this target's
        // deploymentTarget is iOS 16 (project.yml).
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            Task { await locationRuntimeContainer.onAppForeground() }
            // specs/009 §7 — permission MUST be re-checked on every foreground: the user can revoke
            // it from system settings at any time, and returning from that very screen is the most
            // likely moment for it to have changed.
            permissionFlow.refresh()
        }
        // specs/009 §7 — answering the OS dialog does not change scene phase, so without this the
        // banner and the deferred monitoring would both stay stale until the user next left the app
        // and came back.
        .onReceive(NotificationCenter.default.publisher(for: .findlyLocationAuthorizationChanged)) { _ in
            permissionFlow.refresh()
            locationRuntimeContainer.onAuthorizationChanged()
        }
    }

    private var defaultMapRenderer: any MapRendering {
        #if canImport(MapKit)
        MapKitRendering()
        #else
        ListMapRendering()
        #endif
    }

    private static func defaultFromDate() -> String {
        formattedUTCDate(Calendar(identifier: .gregorian).date(byAdding: .day, value: -7, to: Date()) ?? Date())
    }

    private static func defaultToDate() -> String {
        formattedUTCDate(Date())
    }

    private static func formattedUTCDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
