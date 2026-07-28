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
    // specs/004-ios-client.md §3.6, specs/008-privacy-endpoints.md §4.4 — the local-state-wipe
    // dependency `DeleteAccountViewModel` clears after a successful account deletion. As of I10,
    // this is also the SAME instance `LocationRuntimeContainer`'s `deviceId` closure and
    // `onReRegisterDevice`'s re-registration path read/clear (built once, in `FindlyApp.init()`).
    private let deviceIdProvider: DeviceIdProviding
    private let fixQueue: FixQueue
    // specs/009-device-runtime.md (I10) — the real capture/sync engine, built once in
    // `FindlyApp.init()` and passed in here (see this type's top doc for why it can no longer be
    // constructed in THIS init).
    private let locationRuntimeContainer: LocationRuntimeContainer
    // specs/008-privacy-endpoints.md §3.1 — ONE shared instance between `ExportViewModel` (which
    // writes the artifact) and `DeleteAccountViewModel` (whose local wipe must remove it, rule 2)
    // — two independent stores would let the wipe clear an artifact `ExportScreen` never wrote to.
    // The real on-disk implementation (app-private storage + `.completeFileProtection` + backup
    // exclusion, specs/008 §3.1 rules 1/4) — never the in-memory test fake — is what a real device
    // build always gets here.
    private let exportArtifactStore: ExportArtifactStoring

    init(
        coordinator: AppCoordinator,
        config: AppConfig,
        authProvider: AuthProviding,
        apiClient: FindlyAPIClient,
        deviceIdProvider: DeviceIdProviding,
        fixQueue: FixQueue,
        exportArtifactStore: ExportArtifactStoring,
        locationRuntimeContainer: LocationRuntimeContainer
    ) {
        self.coordinator = coordinator
        self.joinLinkHost = config.joinLinkHost
        self.authProvider = authProvider
        self.apiClient = apiClient
        self.deviceIdProvider = deviceIdProvider
        self.fixQueue = fixQueue
        self.exportArtifactStore = exportArtifactStore
        self.locationRuntimeContainer = locationRuntimeContainer
    }

    var body: some View {
        Group {
            switch coordinator.route {
            case .signIn:
                SignInScreen(
                    viewModel: SignInViewModel(authProvider: authProvider, onSignedIn: {
                        coordinator.showHome()
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
                        deviceIdProvider: deviceIdProvider, fixQueue: fixQueue,
                        exportArtifactStore: exportArtifactStore
                    ),
                    // specs/008-privacy-endpoints.md §3.1/§4.4 local wipe already clears fixQueue
                    // (the same shared instance locationRuntimeContainer uses, per this file's
                    // earlier doc comment) — stopping the runtime here additionally halts
                    // significant-location-change monitoring and cancels the scheduled
                    // BGAppRefreshTask, so a deleted account's device doesn't keep quietly
                    // capturing fixes into a freshly-emptied queue until the app is relaunched.
                    onCompleted: { locationRuntimeContainer.stop(); coordinator.showSignIn() }
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
