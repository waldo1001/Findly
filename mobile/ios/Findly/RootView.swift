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
    }

    var body: some View {
        Group {
            switch coordinator.route {
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
                    onSelectPrivacySettings: { coordinator.showPrivacySettings() }
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
                AcceptInviteScreen(viewModel: AcceptInviteViewModel(apiClient: apiClient), prefillInviteCode: prefillCode)

            // MARK: - I5 groups routes (specs/004 §3.4)

            case .groupsList:
                GroupsListScreen(
                    viewModel: GroupsListViewModel(apiClient: apiClient),
                    onSelectGroup: { groupId in coordinator.showGroupDetail(groupId: groupId) },
                    onCreateGroup: { coordinator.showCreateGroup() },
                    onJoinGroup: { coordinator.showGroupJoin() }
                )
            case .createGroup:
                CreateGroupScreen(
                    viewModel: CreateGroupViewModel(apiClient: apiClient),
                    onCreated: { group in coordinator.showGroupDetail(groupId: group.groupId) }
                )
            case .groupDetail(let groupId):
                GroupDetailScreen(
                    viewModel: GroupDetailViewModel(apiClient: apiClient, groupId: groupId),
                    joinLinkHost: joinLinkHost,
                    onSelectMap: { coordinator.showGroupMap(groupId: groupId) },
                    onExit: { coordinator.showGroupsList() }
                )
            case .groupJoin(let prefillCode):
                GroupJoinScreen(
                    viewModel: GroupJoinViewModel(apiClient: apiClient),
                    prefillCode: prefillCode,
                    onJoined: { group in coordinator.showGroupDetail(groupId: group.groupId) }
                )
            case .groupMap(let groupId):
                GroupMapScreen(
                    viewModel: GroupMapViewModel(apiClient: apiClient, groupId: groupId),
                    renderer: defaultMapRenderer,
                    onExit: { coordinator.showGroupsList() }
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
        .environment(\.theme, colorScheme == .dark ? .dark : .light)
        // specs/009-device-runtime.md §3.4/§4 — the foreground opportunistic trigger + the
        // paused-device poll's "on every app foreground" requirement. `.active` fires on cold
        // launch too (harmless — `LocationSyncRunner.runOnce()` is idempotent-safe when there's
        // nothing queued, and `PausedDevicePoller.poll()` is a no-op unless something changed).
        // The single-parameter closure form (not the iOS 17+ two-parameter one) — this target's
        // deploymentTarget is iOS 16 (project.yml).
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            Task { await locationRuntimeContainer.onAppForeground() }
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
