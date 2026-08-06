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
    // specs/009-device-runtime.md §5 (I12) — device re-registration + push-notification
    // registration, run once at cold launch (in `FindlyApp.init()`, if already signed in) and
    // again here once `SignInViewModel` reports a fresh interactive sign-in (a session that starts
    // at the sign-in screen never got the cold-launch call, since nobody was signed in yet then).
    private let onSignedIn: () async -> Void
    // I17 (001 §1.5.3) — the display name typed once on `HomeScreen`'s `.profileless` branch,
    // carried (still editable at the destination) to whichever of the four bootstrap paths the
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
        locationRuntimeContainer: LocationRuntimeContainer,
        onSignedIn: @escaping () async -> Void
    ) {
        self.coordinator = coordinator
        self.joinLinkHost = config.joinLinkHost
        self.authProvider = authProvider
        self.apiClient = apiClient
        self.deviceIdProvider = deviceIdProvider
        self.exportArtifactStore = exportArtifactStore
        self.locationRuntimeContainer = locationRuntimeContainer
        self.onSignedIn = onSignedIn
        // specs/009 §7. Built from the container's read-only seams rather than a second
        // CLLocationManager, so the authorization this reports is the one the capture stack uses.
        _permissionFlow = StateObject(wrappedValue: PermissionFlowViewModel(
            authorization: { [weak locationRuntimeContainer] in
                locationRuntimeContainer?.locationAuthorization ?? .notDetermined
            },
            requiresBackground: { [weak locationRuntimeContainer] in
                locationRuntimeContainer?.requiresBackgroundLocation ?? false
            },
            disclosureStore: UserDefaultsPermissionDisclosureStore(),
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
                onOpenSettings: { openSystemSettings() },
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
                        coordinator.showHome()
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
            case .home:
                HomeScreen(
                    viewModel: HomeViewModel(apiClient: apiClient),
                    onSelectMap: { coordinator.showLiveMap() },
                    onSelectHistory: { userId in coordinator.showHistory(userId: userId) },
                    onSelectGeofences: { coordinator.showGeofences() },
                    onSelectLocate: { target, name in coordinator.showLocate(target: target, targetDisplayName: name) },
                    onSelectDevices: { isParent in coordinator.showDeviceSettings(isParent: isParent) },
                    onSelectFamily: { coordinator.showFamilyMembers() },
                    onSelectInvite: { coordinator.showCreateInvite() },
                    onSelectGroups: { coordinator.showGroupsList() },
                    onSelectPrivacySettings: { coordinator.showPrivacySettings() },
                    // I17 (001 §1.5.3): the four profile-bootstrap paths off `.profileless` — stash
                    // the once-entered display name the same way `onCreateGroup`/`onJoinGroup`
                    // below stash `pendingGroupBootstrapDisplayName`.
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
                        coordinator.showCreateGroup()
                    },
                    onSelectJoinGroup: { name in
                        pendingGroupBootstrapDisplayName = name
                        coordinator.showGroupJoin()
                    }
                )
            case .liveMap:
                LiveMapScreen(viewModel: LiveMapViewModel(apiClient: apiClient), renderer: defaultMapRenderer)
            case .history(let userId, let deviceId):
                HistoryScreen(viewModel: HistoryViewModel(
                    apiClient: apiClient, userId: userId, deviceId: deviceId,
                    fromDate: Self.defaultFromDate(), toDate: Self.defaultToDate()
                ))
            case .geofences:
                GeofencesScreen(viewModel: GeofencesViewModel(apiClient: apiClient))
            case .locate(let target, let targetDisplayName):
                LocateScreen(viewModel: LocateViewModel(apiClient: apiClient), target: target, targetDisplayName: targetDisplayName)
            case .deviceSettings(let isParent):
                DeviceSettingsScreen(viewModel: DeviceSettingsViewModel(apiClient: apiClient, isParent: isParent))
            case .familyMembers:
                FamilyMembersScreen(viewModel: FamilyMembersViewModel(apiClient: apiClient))
            case .createInvite:
                CreateInviteScreen(viewModel: CreateInviteViewModel(apiClient: apiClient))
            case .acceptInvite(let prefillCode):
                AcceptInviteScreen(
                    viewModel: AcceptInviteViewModel(apiClient: apiClient),
                    prefillInviteCode: prefillCode,
                    prefillDisplayName: pendingOnboardingDisplayName,
                    // I24 (001 §1.5.3, §4.1) — accept-invite is one of the four profile-bootstrap
                    // endpoints, so any device registration attempted before this point (e.g. at
                    // sign-in) hit `DeviceRegistrationError.profileNotYetBootstrapped` and was
                    // skipped. Retry the SAME `onSignedIn` closure now that a profile exists,
                    // rather than waiting for the next cold start — it's idempotent (harmless if
                    // already registered for this app version).
                    onAccepted: { Task { await onSignedIn() } }
                )

            // MARK: - I17 profile-bootstrap route (001 §1.5.3, §3.1) — see `CreateFamilyViewModel`'s
            // doc for why this is the client's only `POST /families` entry point.

            case .createFamily:
                CreateFamilyScreen(
                    viewModel: CreateFamilyViewModel(apiClient: apiClient),
                    prefillDisplayName: pendingOnboardingDisplayName,
                    onCreated: { _ in
                        coordinator.showHome()
                        // I24 — same re-registration retry as `.acceptInvite`'s `onAccepted` above.
                        Task { await onSignedIn() }
                    }
                )

            // MARK: - I5 groups routes (specs/004 §3.4)

            case .groupsList:
                GroupsListScreen(
                    viewModel: GroupsListViewModel(apiClient: apiClient),
                    onSelectGroup: { groupId in coordinator.showGroupDetail(groupId: groupId) },
                    onCreateGroup: {
                        // The ordinary (already-has-a-profile) entry point — never leak a stale
                        // prefill name from an earlier profile-less visit. (Whether `displayName`
                        // is actually required is no longer decided here at all — see
                        // `CreateGroupViewModel.createGroup`'s doc, I17 review.)
                        pendingGroupBootstrapDisplayName = ""
                        coordinator.showCreateGroup()
                    },
                    onJoinGroup: {
                        pendingGroupBootstrapDisplayName = ""
                        coordinator.showGroupJoin()
                    }
                )
            case .createGroup:
                CreateGroupScreen(
                    viewModel: CreateGroupViewModel(apiClient: apiClient),
                    prefillDisplayName: pendingGroupBootstrapDisplayName,
                    // specs/004 §2.5: unwind the finished form OUT of the stack before pushing the
                    // new group's detail — otherwise back lands on a create-group form for a group
                    // that already exists, and submitting it again would create a duplicate.
                    onCreated: { group in
                        coordinator.popTo(.groupsList)
                        coordinator.showGroupDetail(groupId: group.groupId)
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
                    // Same unwind rationale as `CreateGroupScreen`'s `onCreated` above. This also
                    // covers the cold-start deep-link arrival, where `.groupsList` was never
                    // visited: `popTo` rebuilds a minimal stack under it rather than leaving the
                    // user on a spent join form with nowhere to go.
                    onJoined: { group in
                        coordinator.popTo(.groupsList)
                        coordinator.showGroupDetail(groupId: group.groupId)
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
                    viewModel: ExportViewModel(apiClient: apiClient, exportArtifactStore: exportArtifactStore)
                )
            case .deleteAccount:
                DeleteAccountScreen(
                    viewModel: DeleteAccountViewModel(
                        apiClient: apiClient, authProvider: authProvider,
                        deviceIdProvider: deviceIdProvider,
                        exportArtifactStore: exportArtifactStore,
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
                    onCompleted: { coordinator.showHome() }
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
        .task {
            coordinator.resolveLaunch(isSignedIn: authProvider.currentUserId != nil)
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
