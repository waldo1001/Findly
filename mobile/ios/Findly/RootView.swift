import SwiftUI
import FindlyKit
import os

/// The composition root — the ONLY place that resolves `.light`/`.dark` from the system
/// `colorScheme` and injects `\.theme` (specs/004-ios-client.md §2.2). Everything below this reads
/// `\.theme`, never `colorScheme` directly. Also the ONLY place that constructs the `AuthProviding`
/// implementation — `AppConfig.authMode` picks `StubAuthProvider` vs `FirebaseAuthProvider`
/// (specs/004 §4.1, §8); switching to real Firebase once H1/H2 land is a config change at this one
/// seam — and, as of I2, the single `FindlyAPIClient` instance every feature screen's view model is
/// constructed with.
/// `@MainActor`-isolated (explicit, not left to inference) since `init` constructs
/// `LocationRuntimeContainer` — itself `@MainActor`-isolated (specs/009-device-runtime.md, I10) —
/// synchronously; SwiftUI already constructs `View`s and evaluates `Scene.body` on the main actor
/// in practice, so this makes that existing guarantee explicit rather than relying on inference.
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
    // `onReRegisterDevice`'s re-registration path read/clear — one shared instance, never a second
    // independently-constructed one, so a wipe and the live sync engine never disagree about
    // whether a deviceId exists.
    private let deviceIdProvider: DeviceIdProviding
    private let fixQueue: FixQueue
    // specs/009-device-runtime.md (I10) — the real capture/sync engine: durable SQLite-backed
    // queue, staged-authorization CoreLocation wiring, BGAppRefreshTask scheduling, the sync
    // runner. `fixQueue` above is set to `locationRuntimeContainer.fixQueue` (not a second,
    // separately-constructed `FixQueue`) so `DeleteAccountViewModel`'s wipe and the real
    // background-sync pipeline are always looking at the exact same durable store — two
    // independent `FixQueue`/`FixStoring` instances over the same on-disk file would each hold
    // their own stale view of "what's pending", the same class of bug 009 §2 exists to prevent one
    // layer down (see `FixStoring.swift`'s doc). Deliberately public-surfaced as a `let` (not
    // Environment-injected) since only `FindlyApp.swift`'s `BGAppRefreshTask` launch handler needs
    // to reach it, via `LocationRuntimeContainerHolder` — see that type's doc for why registration
    // (early, in `FindlyApp.init()`) and construction (here, once real dependencies exist) are
    // necessarily split across two points in the app's lifecycle.
    private let locationRuntimeContainer: LocationRuntimeContainer
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
        let apiClient = URLSessionAPIClient(baseURL: config.baseURL, authProvider: authProvider)
        self.apiClient = apiClient
        self.joinLinkHost = config.joinLinkHost
        let deviceIdProvider = UserDefaultsDeviceIdProvider()
        self.deviceIdProvider = deviceIdProvider
        self.exportArtifactStore = FileManagerExportArtifactStore()

        // specs/009-device-runtime.md §2 — the durable, on-disk queue (I10). Falls back to
        // in-memory only if the on-disk file genuinely can't be opened (e.g. a full disk) — a
        // fix-queue that silently loses history is better than one that crashes app launch.
        let fixStore: FixStoring
        if let store = try? SQLiteFixStore(url: Self.fixStoreDatabaseURL(), onOverflowDropped: Self.logOverflowDrop) {
            fixStore = store
        } else {
            fixStore = InMemoryFixStore(onOverflowDropped: Self.logOverflowDrop)
        }

        let authProviderRef = authProvider
        let deviceInfoProvider = SystemDeviceInfoProvider()
        let deviceRegistrationService = DeviceRegistrationService(
            apiClient: apiClient, deviceIdProvider: deviceIdProvider, deviceInfoProvider: deviceInfoProvider, authProvider: authProvider
        )
        let locationProvider = SystemLocationProvider()
        let coordinatorRef = coordinator
        let deviceIdClosure: () -> String? = { [weak authProviderRef] in
            guard let uid = authProviderRef?.currentUserId else { return nil }
            return deviceIdProvider.deviceId(forUserId: uid)
        }
        let container = LocationRuntimeContainer(
            apiClient: apiClient,
            deviceId: deviceIdClosure,
            locationProvider: locationProvider,
            backgroundScheduler: SystemBackgroundSyncScheduler(),
            fixStore: fixStore,
            stateStore: UserDefaultsDeviceSettingsStateStore(),
            lastQueuedFixAtStore: UserDefaultsLastQueuedFixAtStore(),
            isPermissionGranted: { [weak locationProvider] in locationProvider?.isAuthorized ?? false },
            // specs/009 §9: 404 DEVICE_NOT_FOUND -> stop the schedule, clear local device state,
            // re-run registration. This is also what self-heals the (pre-existing, not an I10
            // regression) gap that nothing yet calls DeviceRegistrationService on first launch
            // after sign-in: the very first sync attempt for a client-generated-but-never-
            // registered deviceId 404s once, registers here, then succeeds from then on.
            onReRegisterDevice: { [weak authProviderRef] in
                guard let uid = authProviderRef?.currentUserId else { return }
                deviceIdProvider.clearDeviceId(forUserId: uid)
                _ = try? await deviceRegistrationService.registerOrUpdate()
            },
            // specs/009 §9: a second AUTH_TOKEN_EXPIRED means signed-out - stop the runtime and
            // return to sign-in. Reads the container back through the holder (populated a few
            // lines below, but only ever CALLED once a real failure happens, long after that
            // assignment has run) rather than capturing `container` directly, which doesn't exist
            // yet at this point inside its own initializer argument list.
            onSignedOut: { [weak authProviderRef] in
                try? authProviderRef?.signOut()
                await LocationRuntimeContainerHolder.shared.container?.stop()
                await coordinatorRef.showSignIn()
            }
        )
        self.locationRuntimeContainer = container
        // The one and only FixQueue instance the app ever uses (see this property's doc comment
        // above for why a second, separately-constructed one would be a durability bug).
        self.fixQueue = container.fixQueue
        // Publishes this container to the holder `FindlyApp.init()`'s (already-registered, at
        // that point still dependency-less) BGAppRefreshTask launch handler reads lazily — see
        // `LocationRuntimeContainer`'s doc for why registration and construction are necessarily
        // split across two points in the app's lifecycle.
        LocationRuntimeContainerHolder.shared.container = container
        container.start()
    }

    /// specs/009-device-runtime.md §2 / docs/security-review-checklist.md — the fix-queue's
    /// 1 000-cap overflow log line: a **count only**, never coordinates/fixId/deviceId. `.debug`
    /// level matches the spec's "logged at debug level" wording exactly.
    private static let fixQueueLog = Logger(subsystem: "com.findly.ios", category: "FixQueue")
    private static func logOverflowDrop(_ droppedCount: Int) {
        fixQueueLog.debug("1000-fix cap reached, dropped \(droppedCount, privacy: .public) oldest fix(es)")
    }

    /// specs/009-device-runtime.md §2 — the durable fix-queue's on-disk location: app-private
    /// Application Support storage (never Documents, which is user-visible/exportable via Files.app
    /// — this is raw location history, not a user-facing document), created on first use.
    private static func fixStoreDatabaseURL() -> URL {
        let fileManager = FileManager.default
        let directory = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fileManager.temporaryDirectory
        return directory.appendingPathComponent("findly-fixqueue.sqlite")
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
