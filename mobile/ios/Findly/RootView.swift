import SwiftUI
import FindlyKit

/// The composition root — the ONLY place that resolves `.light`/`.dark` from the system
/// `colorScheme` and injects `\.theme` (specs/004-ios-client.md §2.2). Everything below this reads
/// `\.theme`, never `colorScheme` directly. Also the ONLY place that constructs the `AuthProviding`
/// implementation — `AppConfig.authMode` picks `StubAuthProvider` vs `FirebaseAuthProvider`
/// (specs/004 §4.1, §8); switching to real Firebase once H1/H2 land is a config change at this one
/// seam — and, as of I2, the single `FindlyAPIClient` instance every feature screen's view model is
/// constructed with.
struct RootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var coordinator: AppCoordinator

    private let authProvider: AuthProviding
    private let apiClient: FindlyAPIClient
    // specs/004-ios-client.md §3.5, specs/007-public-join-links.md §1 — threaded into
    // `GroupDetailScreen` for its share link/QR (`AppConfig.joinLinkHost`).
    private let joinLinkHost: String
    // specs/004-ios-client.md §3.6, specs/008-privacy-endpoints.md §4.4 — the local-state-wipe
    // dependencies `DeleteAccountViewModel` clears after a successful account deletion. Not wired
    // into device-registration/location-sync flows yet (I1 scaffolding, still not connected to the
    // UI layer by any task through I7) — a single shared instance here is the natural, minimal
    // integration point for I8's wipe requirement, and becomes the shared instance those flows use
    // once they land.
    private let deviceIdProvider: DeviceIdProviding
    private let fixQueue: FixQueue
    // specs/008-privacy-endpoints.md §3.1 — ONE shared instance between `ExportViewModel` (which
    // writes the artifact) and `DeleteAccountViewModel` (whose local wipe must remove it, rule 2)
    // — two independent stores would let the wipe clear an artifact `ExportScreen` never wrote to.
    // The real on-disk implementation (app-private storage + `.completeFileProtection` + backup
    // exclusion, specs/008 §3.1 rules 1/4) — never the in-memory test fake — is what a real device
    // build always gets here.
    private let exportArtifactStore: ExportArtifactStoring

    // specs/004-ios-client.md §4.1, §8 — AuthMode.stubLocal (default) matches the backend's
    // AUTH_MODE=insecure-local (specs/001 §2.3); AuthMode.firebase swaps in FirebaseAuthProvider,
    // the H1/H2 follow-up (real Firebase Auth SDK + GoogleService-Info.plist + Firebase console
    // phone-auth setup) — a config change only, no further code change at this seam.
    init(coordinator: AppCoordinator, config: AppConfig = AppConfig()) {
        self.coordinator = coordinator
        switch config.authMode {
        case .stubLocal:
            self.authProvider = StubAuthProvider(firebaseProjectId: config.firebaseProjectId)
        case .firebase:
            self.authProvider = FirebaseAuthProvider()
        }
        self.apiClient = URLSessionAPIClient(baseURL: config.baseURL, authProvider: authProvider)
        self.joinLinkHost = config.joinLinkHost
        self.deviceIdProvider = UserDefaultsDeviceIdProvider()
        self.fixQueue = FixQueue()
        self.exportArtifactStore = FileManagerExportArtifactStore()
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
