import Foundation
import Observation
import SwiftData
import SwiftUI

@Observable
@MainActor
public final class AppViewModel {
    private enum StorageKeys {
        static let serverURL = "pve_native_server_url"
        static let activeProfileID = "pve_native_active_profile_id"
        static let savedServers = "pve_native_saved_servers"
        static let demoMode = "pve_native_demo_mode"
        static let autoRefresh = "pve_native_auto_refresh"
        static let appearanceMode = "pve_native_appearance_mode"
        static let accentTheme = "pve_native_accent_theme"
    }

    public let apiClient: APIClient
    public let modelContainer: ModelContainer
    public let keychainStore: KeychainStore
    public let telemetrySnapshotStore: TelemetrySnapshotStore
    public let discoveryService: BonjourDiscoveryService
    public let pairingService: PairingCryptoService
    public let realtimeClient: RealtimeEventsClient
    public let pushManager: PushNotificationManager

    private var pollingTask: Task<Void, Never>?
    private var updatesPollingTask: Task<Void, Never>?

    // MARK: - Connection, Onboarding & Appearance State
    public var serverBaseURL: String
    public var activeProfileID: UUID?
    public var savedServers: [SavedServerProfile] = []
    public var isDemoMode: Bool
    public var autoRefresh: Bool
    public var appearanceMode: AppearanceMode
    public var accentTheme: AccentTheme
    public var needsOnboarding: Bool = false
    public var showServerSettings: Bool = false
    public var showServerSetupWizard: Bool = false
    public var pendingOpenSetupWizard: Bool = false
    public var showUpdatesSheet: Bool = false
    public var isAppInBackground: Bool = false

    public var selectedTab: AppTab = .overview
    public var searchText: String = ""

    public var isInitialLoading: Bool = true
    public var isRefreshing: Bool = false
    public var connectionError: String?
    public var lastUpdated: Date?

    public var toast: ToastMessage?
    public var hapticSuccessTrigger: Int = 0
    public var hapticImpactTrigger: Int = 0

    // MARK: - Domain State
    public var user: AuthUser?
    public var pveOverview: PveOverview?
    public var selectedClusterNode: String?
    public var latestTelemetrySnapshot: TelemetryWidgetSnapshot?
    public var categories: [ServiceCategory] = []
    public var widgets: WidgetsMap?
    public var usersOverview: UsersOverview?
    public var opsOverview: OpsOverview?
    public var setupStatus: SetupStatusResponse?
    public var onboardingStatus: OnboardingStatusResponse?

    public var customServices: [CustomServiceConfig] = []
    public var incidents: [IncidentEvent] = []
    public var notificationChannels: NotificationChannelsResponse?
    public var yamlConfig: YAMLConfigResponse?
    public var lanDiscoveryItems: [DiscoveryServerItem] = []
    public var isLoadingDiscoveryLAN: Bool = false

    public var updatesOverview: UpdatesOverviewResponse?
    public var updatesSetupInfo: UpdatesSetupInfoResponse?
    public var isCheckingUpdates: Bool = false
    public var isStartingUpdateJob: Bool = false
    public var isLoadingUpdatesSetup: Bool = false

    public init(
        apiClient: APIClient = APIClient(),
        modelContainer: ModelContainer? = nil,
        keychainStore: KeychainStore = .shared,
        telemetrySnapshotStore: TelemetrySnapshotStore = .shared
    ) {
        self.apiClient = apiClient
        self.modelContainer = modelContainer ?? PVEModelContainerFactory.makeSharedContainer()
        self.keychainStore = keychainStore
        self.telemetrySnapshotStore = telemetrySnapshotStore
        self.discoveryService = BonjourDiscoveryService()
        self.pairingService = PairingCryptoService()
        self.realtimeClient = RealtimeEventsClient()
        self.pushManager = PushNotificationManager()

        let defaults = UserDefaults.standard
        let savedURL = APIClient.normalizeBaseURL(defaults.string(forKey: StorageKeys.serverURL) ?? "")
        let savedDemo = defaults.bool(forKey: StorageKeys.demoMode)
        let savedAutoRefresh = defaults.object(forKey: StorageKeys.autoRefresh) as? Bool ?? true
        let savedAppearance = AppearanceMode(rawValue: defaults.string(forKey: StorageKeys.appearanceMode) ?? "") ?? .system
        let savedAccent = AccentTheme(rawValue: defaults.string(forKey: StorageKeys.accentTheme) ?? "") ?? .cyan
        let savedActiveID = defaults.string(forKey: StorageKeys.activeProfileID).flatMap(UUID.init(uuidString:))

        self.serverBaseURL = savedURL
        self.activeProfileID = savedActiveID
        self.isDemoMode = savedDemo
        self.autoRefresh = savedAutoRefresh
        self.appearanceMode = savedAppearance
        self.accentTheme = savedAccent

        loadAndMigrateProfiles(legacyURL: savedURL, preferredActiveID: savedActiveID)

        if self.serverBaseURL.isEmpty && !savedDemo {
            self.isInitialLoading = false
            self.needsOnboarding = true
        } else {
            self.needsOnboarding = false
        }

        self.latestTelemetrySnapshot = telemetrySnapshotStore.load()

        if let activeID = activeServerProfile?.id {
            hydrateCachesFromSwiftData(for: activeID)
        }

        configureRealtimeAndPushHandlers()
    }

    // MARK: - Computed Properties

    public var activeServerProfile: SavedServerProfile? {
        if let activeProfileID,
           let match = savedServers.first(where: { $0.id == activeProfileID }) {
            return match
        }
        guard !serverBaseURL.isEmpty else { return nil }
        return savedServers.first(where: {
            $0.baseURL.caseInsensitiveCompare(serverBaseURL) == .orderedSame
        })
    }

    public var activeServerName: String {
        if isDemoMode { return "Mode Démo" }
        if let profile = activeServerProfile {
            return profile.name
        }
        return serverBaseURL.isEmpty ? "Aucun serveur" : Self.defaultServerName(for: serverBaseURL)
    }

    public var activeBearerToken: String? {
        guard let profileID = activeServerProfile?.id else { return nil }
        return keychainStore.readBearerToken(profileID: profileID)
    }

    public var hasActiveToken: Bool {
        guard let token = activeBearerToken else { return false }
        return !token.isEmpty
    }

    public var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    public var activeIncidentsCount: Int {
        incidents.filter(\.isActive).count
    }

    public var activeAlertBanners: [InAppAlertBanner] {
        pushManager.activeBannerQueue
    }

    public var activeTVBanner: InAppAlertBanner? {
        pushManager.activeTVBanner
    }

    public var realtimeState: RealtimeConnectionState {
        realtimeClient.connectionState
    }

    public var pendingRequestsCount: Int {
        (opsOverview?.seerrRequests ?? []).filter(\.isPending).count
    }

    public var availableUpdatesCount: Int {
        updatesOverview?.summary.updatesAvailable ?? 0
    }

    // MARK: - Appearance & Onboarding Controls

    public func setAppearanceMode(_ mode: AppearanceMode) {
        appearanceMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: StorageKeys.appearanceMode)
        if let activeID = activeServerProfile?.id {
            updateSwiftDataProfile(id: activeID) { entity in
                entity.appearancePreferenceRaw = mode.rawValue
            }
            if let idx = savedServers.firstIndex(where: { $0.id == activeID }) {
                savedServers[idx].appearancePreference = mode
                persistSavedServersToDefaults()
            }
        }
        hapticImpactTrigger += 1
    }

    public func setAccentTheme(_ theme: AccentTheme) {
        accentTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: StorageKeys.accentTheme)
        hapticImpactTrigger += 1
    }

    public func tintColor(for scheme: ColorScheme) -> Color {
        DesignTokens.accent(accentTheme, scheme)
    }

    public func relaunchOnboarding() {
        showServerSettings = false
        needsOnboarding = true
    }

    public func dismissOnboarding() {
        needsOnboarding = false
    }

    public func completeOnboarding(
        serverName: String,
        baseURL: String,
        bearerToken: String? = nil,
        usesTailscaleSSO: Bool = false
    ) async {
        await addOrSelectServer(
            name: serverName,
            baseURL: baseURL,
            bearerToken: bearerToken,
            usesTailscaleSSO: usesTailscaleSSO
        )
        needsOnboarding = false
    }

    // MARK: - Lifecycle, Real-Time & Polling

    public func start() {
        discoveryService.startPVEDiscovery()
        Task {
            await syncAPIClientToken()
            connectRealtimeIfNeeded()
        }

        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshAll(silent: false)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                if self.autoRefresh
                    && !self.isAppInBackground
                    && !self.showServerSettings
                    && !self.showServerSetupWizard
                    && !self.needsOnboarding {
                    await self.refreshAll(silent: true)
                }
            }
        }
    }

    public func handleScenePhaseChanged(isBackground: Bool) {
        isAppInBackground = isBackground
        if !isBackground {
            connectRealtimeIfNeeded()
            Task { await refreshAll(silent: true) }
        }
    }

    public func toggleAutoRefresh() {
        autoRefresh.toggle()
        UserDefaults.standard.set(autoRefresh, forKey: StorageKeys.autoRefresh)
        hapticImpactTrigger += 1
    }

    // MARK: - Connection & Server Profile Management

    public func configureConnection(baseURL: String, demoMode: Bool) async {
        let normalized = APIClient.normalizeBaseURL(baseURL)
        if serverBaseURL != normalized || isDemoMode != demoMode {
            resetDomainState()
        }
        self.serverBaseURL = normalized
        self.isDemoMode = demoMode
        self.connectionError = nil

        let defaults = UserDefaults.standard
        defaults.set(normalized, forKey: StorageKeys.serverURL)
        defaults.set(demoMode, forKey: StorageKeys.demoMode)

        if let matching = savedServers.first(where: {
            $0.baseURL.caseInsensitiveCompare(normalized) == .orderedSame
        }) {
            activeProfileID = matching.id
            defaults.set(matching.id.uuidString, forKey: StorageKeys.activeProfileID)
            hydrateCachesFromSwiftData(for: matching.id)
        } else if demoMode {
            needsOnboarding = false
        }

        showServerSettings = false
        needsOnboarding = false
        hapticSuccessTrigger += 1

        await syncAPIClientToken()
        connectRealtimeIfNeeded()
        await refreshAll(silent: false)
    }

    public func addOrSelectServer(name: String, baseURL: String) async {
        await addOrSelectServer(name: name, baseURL: baseURL, bearerToken: nil, usesTailscaleSSO: false)
    }

    public func addOrSelectServer(
        name: String,
        baseURL: String,
        bearerToken: String?,
        usesTailscaleSSO: Bool = false
    ) async {
        let normalized = APIClient.normalizeBaseURL(baseURL)
        guard !normalized.isEmpty else {
            showToast("L'URL du serveur est invalide.", isError: true)
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? Self.defaultServerName(for: normalized) : trimmedName

        let selectedProfile: SavedServerProfile
        if let existingIndex = savedServers.firstIndex(where: {
            $0.baseURL.caseInsensitiveCompare(normalized) == .orderedSame
        }) {
            if !trimmedName.isEmpty {
                savedServers[existingIndex].name = resolvedName
            }
            if usesTailscaleSSO {
                savedServers[existingIndex].usesTailscaleSSO = true
            }
            savedServers[existingIndex].lastConnectedAt = Date()
            let existing = savedServers.remove(at: existingIndex)
            savedServers.insert(existing, at: 0)
            selectedProfile = existing
        } else {
            let created = SavedServerProfile(
                name: resolvedName,
                baseURL: normalized,
                isDefault: savedServers.isEmpty,
                usesTailscaleSSO: usesTailscaleSSO,
                lastConnectedAt: Date(),
                appearancePreference: appearanceMode
            )
            savedServers.insert(created, at: 0)
            selectedProfile = created
        }

        if let token = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            try? keychainStore.saveBearerToken(token, profileID: selectedProfile.id)
        }

        activeProfileID = selectedProfile.id
        UserDefaults.standard.set(selectedProfile.id.uuidString, forKey: StorageKeys.activeProfileID)
        upsertSwiftDataProfile(selectedProfile, markDefault: true)
        persistSavedServersToDefaults()

        await configureConnection(baseURL: normalized, demoMode: false)
    }

    public func setActiveServer(_ profile: SavedServerProfile, bearerToken: String? = nil) async {
        await addOrSelectServer(
            name: profile.name,
            baseURL: profile.baseURL,
            bearerToken: bearerToken,
            usesTailscaleSSO: profile.usesTailscaleSSO
        )
    }

    public func saveBearerToken(_ token: String, for profileID: UUID? = nil) async {
        guard let targetID = profileID ?? activeServerProfile?.id else { return }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try keychainStore.deleteBearerToken(profileID: targetID)
            } else {
                try keychainStore.saveBearerToken(trimmed, profileID: targetID)
            }
            await syncAPIClientToken()
            connectRealtimeIfNeeded()
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func clearBearerToken(for profileID: UUID? = nil) async {
        await saveBearerToken("", for: profileID)
    }

    public func removeServer(id: UUID) {
        let removed = savedServers.first(where: { $0.id == id })
        savedServers.removeAll { $0.id == id }
        try? keychainStore.deleteAllSecrets(profileID: id)
        deleteSwiftDataProfile(id: id)
        persistSavedServersToDefaults()

        if let removed,
           !isDemoMode,
           removed.baseURL.caseInsensitiveCompare(serverBaseURL) == .orderedSame {
            realtimeClient.disconnect()
            serverBaseURL = ""
            activeProfileID = nil
            UserDefaults.standard.set("", forKey: StorageKeys.serverURL)
            UserDefaults.standard.removeObject(forKey: StorageKeys.activeProfileID)
            resetDomainState()
            if savedServers.isEmpty {
                needsOnboarding = true
            }
        }
        hapticImpactTrigger += 1
    }

    // MARK: - Deep Link Pairing (pvecenter://connect)

    public func openSetupWizard() {
        if showServerSettings {
            pendingOpenSetupWizard = true
            showServerSettings = false
        } else {
            showServerSetupWizard = true
        }
    }

    public static func parseConnectDeepLink(_ raw: String) -> (url: String, name: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }
        return parseConnectDeepLink(url: url)
    }

    public static func parseConnectDeepLink(url: URL) -> (url: String, name: String)? {
        guard let payload = parseConnectDeepLinkPayload(url: url) else { return nil }
        return (payload.url, payload.name)
    }

    public static func parseConnectDeepLinkPayload(url: URL) -> (url: String, name: String, token: String?)? {
        guard url.scheme?.lowercased() == "pvecenter" else { return nil }
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        guard host == "connect" || path == "/connect" else { return nil }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawTarget = components.queryItems?.first(where: { $0.name == "url" })?.value else {
            return nil
        }

        let normalized = APIClient.normalizeBaseURL(rawTarget)
        guard !normalized.isEmpty,
              let parsedTarget = URL(string: normalized),
              let scheme = parsedTarget.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let targetHost = parsedTarget.host,
              !targetHost.isEmpty else {
            return nil
        }

        let rawName = components.queryItems?.first(where: { $0.name == "name" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedName = rawName.isEmpty ? defaultServerName(for: normalized) : rawName
        let rawToken = components.queryItems?.first(where: { $0.name == "token" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedToken = (rawToken?.isEmpty == false) ? rawToken : nil
        return (normalized, resolvedName, resolvedToken)
    }

    public func handleIncomingURL(_ url: URL) async {
        guard let parsed = Self.parseConnectDeepLinkPayload(url: url) else {
            showToast("Lien d'appairage pvecenter:// invalide.", isError: true)
            return
        }

        await addOrSelectServer(name: parsed.name, baseURL: parsed.url, bearerToken: parsed.token)
        needsOnboarding = false

        do {
            let status = try await apiClient.fetchSetupStatus(baseURL: parsed.url, demoMode: false)
            self.setupStatus = status
            if !status.isConfigured {
                openSetupWizard()
                showToast("Serveur « \(parsed.name) » connecté — terminez la configuration.", isError: false)
            } else {
                showToast("Serveur « \(parsed.name) » appairé et connecté.", isError: false)
            }
        } catch {
            showToast("Serveur « \(parsed.name) » ajouté (\(error.localizedDescription)).", isError: true)
        }
    }

    // MARK: - Auth & Onboarding Endpoints

    public func testConnection(candidateURL: String) async throws -> AuthUser {
        try await apiClient.testConnection(baseURL: candidateURL, bearerToken: activeBearerToken)
    }

    public func testConnection(candidateURL: String, bearerToken: String?) async throws -> AuthUser {
        try await apiClient.testConnection(baseURL: candidateURL, bearerToken: bearerToken)
    }

    public func loginWithPIN(_ pin: String, deviceName: String? = nil) async -> Bool {
        guard isDemoMode || !serverBaseURL.isEmpty else { return false }
        do {
            let req = AuthLoginRequest(pin: pin, deviceName: deviceName)
            let response = try await apiClient.login(baseURL: serverBaseURL, demoMode: isDemoMode, payload: req)
            if !response.token.isEmpty {
                await saveBearerToken(response.token)
            }
            if let authUser = response.user {
                self.user = authUser
            }
            hapticSuccessTrigger += 1
            showToast("Authentification réussie.", isError: false)
            await refreshAll(silent: false)
            return true
        } catch {
            showToast(error.localizedDescription, isError: true)
            return false
        }
    }

    public func checkOnboardingStatus(candidateURL: String? = nil) async throws -> OnboardingStatusResponse {
        let targetURL = candidateURL.map(APIClient.normalizeBaseURL) ?? serverBaseURL
        let status = try await apiClient.fetchOnboardingStatus(
            baseURL: targetURL,
            bearerToken: activeBearerToken,
            demoMode: isDemoMode
        )
        self.onboardingStatus = status
        return status
    }

    public func submitOnboardingInit(
        candidateURL: String? = nil,
        request: OnboardingInitRequest
    ) async throws -> OnboardingInitResponse {
        let targetURL = candidateURL.map(APIClient.normalizeBaseURL) ?? serverBaseURL
        let response = try await apiClient.initOnboarding(
            baseURL: targetURL,
            bearerToken: activeBearerToken,
            demoMode: isDemoMode,
            payload: request
        )

        if !targetURL.isEmpty {
            await addOrSelectServer(
                name: request.serverName,
                baseURL: targetURL,
                bearerToken: response.apiToken,
                usesTailscaleSSO: request.tailscaleSsoEnabled ?? false
            )
            if let hash = response.configHash, let activeID = activeServerProfile?.id {
                updateSwiftDataProfile(id: activeID) { entity in
                    entity.configHash = hash
                }
            }
        }
        needsOnboarding = false
        hapticSuccessTrigger += 1
        showToast(response.message ?? "Serveur initialisé avec succès.", isError: false)
        await refreshAll(silent: false)
        return response
    }

    // MARK: - Setup Wizard

    public func fetchSetupStatus() async throws -> SetupStatusResponse {
        let status = try await apiClient.fetchSetupStatus(baseURL: serverBaseURL, demoMode: isDemoMode)
        self.setupStatus = status
        return status
    }

    public func testSetupService(_ request: ServiceTestRequest) async throws -> ServiceTestResponse {
        try await apiClient.testServiceConnection(baseURL: serverBaseURL, demoMode: isDemoMode, payload: request)
    }

    public func saveSetupConfig(_ request: SetupConfigUpdateRequest) async throws -> SetupConfigUpdateResponse {
        let response = try await apiClient.saveSetupConfig(baseURL: serverBaseURL, demoMode: isDemoMode, payload: request)
        hapticSuccessTrigger += 1
        showToast(response.message, isError: false)
        await refreshAll(silent: false)
        return response
    }

    // MARK: - Dashboard Full Refresh

    public func refreshAll(silent: Bool = false) async {
        guard isDemoMode || !serverBaseURL.isEmpty else {
            isInitialLoading = false
            return
        }

        if !silent && pveOverview == nil {
            isInitialLoading = true
        }
        isRefreshing = true
        defer {
            isInitialLoading = false
            isRefreshing = false
        }

        await syncAPIClientToken()

        do {
            let me = try await apiClient.fetchMe(baseURL: serverBaseURL, demoMode: isDemoMode)
            self.user = me
            self.connectionError = nil

            async let pveReq = apiClient.fetchPveOverview(
                baseURL: serverBaseURL,
                demoMode: isDemoMode,
                node: selectedClusterNode
            )
            async let svcReq = apiClient.fetchServices(baseURL: serverBaseURL, demoMode: isDemoMode)
            async let widReq = apiClient.fetchWidgets(baseURL: serverBaseURL, demoMode: isDemoMode)
            async let opsReq = apiClient.fetchOpsOverview(baseURL: serverBaseURL, demoMode: isDemoMode)
            async let usrReq = apiClient.fetchUsers(baseURL: serverBaseURL, demoMode: isDemoMode)
            async let setupReq = apiClient.fetchSetupStatus(baseURL: serverBaseURL, demoMode: isDemoMode)
            async let customReq = apiClient.fetchCustomServices(baseURL: serverBaseURL, demoMode: isDemoMode)
            async let incReq = apiClient.fetchIncidents(baseURL: serverBaseURL, demoMode: isDemoMode, activeOnly: false, limit: 50)
            async let updReq = apiClient.fetchUpdatesOverview(baseURL: serverBaseURL, demoMode: isDemoMode)

            let (pve, svc, wid, ops, usr, setup, custom, inc, upd) = await (
                try? pveReq,
                try? svcReq,
                try? widReq,
                try? opsReq,
                try? usrReq,
                try? setupReq,
                try? customReq,
                try? incReq,
                try? updReq
            )

            if let pve { self.pveOverview = pve }
            if let svc { self.categories = svc.categories }
            if let wid { self.widgets = wid }
            if let ops { self.opsOverview = ops }
            if let usr { self.usersOverview = usr }
            if let setup { self.setupStatus = setup }
            if let upd {
                self.updatesOverview = upd
                if upd.activeJob?.status == "running" {
                    startUpdateJobPollingIfNeeded()
                }
            }
            if let custom {
                self.customServices = custom
                if let activeID = activeServerProfile?.id {
                    persistCachedCustomServices(custom, for: activeID)
                }
            }
            if let inc {
                self.incidents = inc
                if let activeID = activeServerProfile?.id {
                    persistCachedIncidents(inc, for: activeID)
                }
            }

            self.lastUpdated = Date()
            persistTelemetrySnapshot()
            if let activeID = activeServerProfile?.id {
                updateSwiftDataProfile(id: activeID) { entity in
                    entity.lastConnectedAt = Date()
                    entity.usesTailscaleSSO = me.authMode?.lowercased().contains("tailscale") ?? entity.usesTailscaleSSO
                }
            }
        } catch {
            self.connectionError = error.localizedDescription
            if !silent {
                showToast(error.localizedDescription, isError: true)
            }
        }
    }

    public func selectClusterNode(_ node: String?) async {
        let trimmed = node?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (trimmed?.isEmpty == false) ? trimmed : nil
        guard selectedClusterNode != normalized else { return }
        selectedClusterNode = normalized
        hapticImpactTrigger += 1
        await refreshPveOverviewOnly()
    }

    public func refreshPveOverviewOnly() async {
        guard isDemoMode || !serverBaseURL.isEmpty else { return }
        do {
            let pve = try await apiClient.fetchPveOverview(
                baseURL: serverBaseURL,
                demoMode: isDemoMode,
                node: selectedClusterNode
            )
            self.pveOverview = pve
            self.lastUpdated = Date()
            persistTelemetrySnapshot()
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func refreshOpsOnly() async {
        guard isDemoMode || !serverBaseURL.isEmpty else { return }
        if let ops = try? await apiClient.fetchOpsOverview(baseURL: serverBaseURL, demoMode: isDemoMode) {
            self.opsOverview = ops
        }
    }

    public func refreshUsersOnly() async {
        guard isDemoMode || !serverBaseURL.isEmpty else { return }
        if let usr = try? await apiClient.fetchUsers(baseURL: serverBaseURL, demoMode: isDemoMode) {
            self.usersOverview = usr
        }
    }

    // MARK: - Unified Update Center Actions

    public func refreshUpdatesOnly() async {
        guard isDemoMode || !serverBaseURL.isEmpty else { return }
        if let upd = try? await apiClient.fetchUpdatesOverview(baseURL: serverBaseURL, demoMode: isDemoMode) {
            self.updatesOverview = upd
            if upd.activeJob?.status == "running" {
                startUpdateJobPollingIfNeeded()
            }
        }
    }

    public func checkUpdates() async {
        guard isDemoMode || !serverBaseURL.isEmpty else { return }
        isCheckingUpdates = true
        defer { isCheckingUpdates = false }
        do {
            let upd = try await apiClient.checkUpdates(baseURL: serverBaseURL, demoMode: isDemoMode)
            self.updatesOverview = upd
            hapticImpactTrigger += 1
            showToast("Inventaire des mises à jour actualisé.", isError: false)
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func runUpdates(
        targetIds: [String],
        includePanelSelf: Bool = true,
        autoremove: Bool = true
    ) async {
        guard isDemoMode || !serverBaseURL.isEmpty else { return }
        isStartingUpdateJob = true
        defer { isStartingUpdateJob = false }
        do {
            let req = RunUpdatesRequest(
                targetIds: targetIds,
                includePanelSelf: includePanelSelf,
                autoremove: autoremove
            )
            _ = try await apiClient.runUpdates(baseURL: serverBaseURL, demoMode: isDemoMode, request: req)
            hapticSuccessTrigger += 1
            showToast(
                targetIds.contains("all")
                    ? "Mise à jour globale lancée."
                    : "Mise à jour lancée (\(targetIds.count) cible(s)).",
                isError: false
            )
            await refreshUpdatesOnly()
            startUpdateJobPollingIfNeeded()
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func loadUpdatesSetupInfo() async {
        guard isDemoMode || !serverBaseURL.isEmpty else { return }
        isLoadingUpdatesSetup = true
        defer { isLoadingUpdatesSetup = false }
        do {
            self.updatesSetupInfo = try await apiClient.fetchUpdatesSetupInfo(
                baseURL: serverBaseURL,
                demoMode: isDemoMode
            )
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func rotateUpdatesSSHKey() async {
        guard isDemoMode || !serverBaseURL.isEmpty else { return }
        isLoadingUpdatesSetup = true
        defer { isLoadingUpdatesSetup = false }
        do {
            self.updatesSetupInfo = try await apiClient.rotateUpdatesSSHKey(
                baseURL: serverBaseURL,
                demoMode: isDemoMode
            )
            showToast("Nouvelle clé Ed25519 générée.", isError: false)
            await refreshUpdatesOnly()
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    private func startUpdateJobPollingIfNeeded() {
        guard updatesPollingTask == nil else { return }
        updatesPollingTask = Task { [weak self] in
            defer { Task { @MainActor in self?.updatesPollingTask = nil } }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(900))
                guard let self, self.isDemoMode || !self.serverBaseURL.isEmpty else { break }
                if let jobResp = try? await self.apiClient.fetchCurrentUpdateJob(
                    baseURL: self.serverBaseURL,
                    demoMode: self.isDemoMode
                ) {
                    if let current = self.updatesOverview {
                        self.updatesOverview = UpdatesOverviewResponse(
                            enabled: current.enabled,
                            sshConfigured: current.sshConfigured,
                            sshMessage: current.sshMessage,
                            sshHost: current.sshHost,
                            lastCheckedAt: current.lastCheckedAt,
                            summary: current.summary,
                            targets: current.targets,
                            activeJob: jobResp.activeJob,
                            recentJobs: jobResp.recentJobs
                        )
                    }
                    if jobResp.activeJob?.status != "running" {
                        await self.refreshUpdatesOnly()
                        break
                    }
                }
            }
        }
    }

    // MARK: - Custom Services Actions

    public func refreshCustomServices() async {
        guard isDemoMode || !serverBaseURL.isEmpty else { return }
        do {
            let list = try await apiClient.fetchCustomServices(baseURL: serverBaseURL, demoMode: isDemoMode)
            self.customServices = list
            if let activeID = activeServerProfile?.id {
                persistCachedCustomServices(list, for: activeID)
            }
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func createCustomService(_ service: CustomServiceConfig) async -> Bool {
        do {
            _ = try await apiClient.createCustomService(baseURL: serverBaseURL, demoMode: isDemoMode, service: service)
            hapticSuccessTrigger += 1
            showToast("Service « \(service.name) » ajouté.", isError: false)
            await refreshCustomServices()
            if let svc = try? await apiClient.fetchServices(baseURL: serverBaseURL, demoMode: isDemoMode) {
                self.categories = svc.categories
            }
            return true
        } catch {
            showToast(error.localizedDescription, isError: true)
            return false
        }
    }

    public func updateCustomService(id: String, service: CustomServiceConfig) async -> Bool {
        do {
            _ = try await apiClient.updateCustomService(
                baseURL: serverBaseURL,
                demoMode: isDemoMode,
                serviceId: id,
                service: service
            )
            hapticSuccessTrigger += 1
            showToast("Service « \(service.name) » mis à jour.", isError: false)
            await refreshCustomServices()
            return true
        } catch {
            showToast(error.localizedDescription, isError: true)
            return false
        }
    }

    public func deleteCustomService(id: String) async -> Bool {
        do {
            try await apiClient.deleteCustomService(baseURL: serverBaseURL, demoMode: isDemoMode, serviceId: id)
            hapticImpactTrigger += 1
            showToast("Service supprimé.", isError: false)
            await refreshCustomServices()
            return true
        } catch {
            showToast(error.localizedDescription, isError: true)
            return false
        }
    }

    public func reorderCustomServices(serviceIds: [String]) async {
        do {
            try await apiClient.reorderCustomServices(
                baseURL: serverBaseURL,
                demoMode: isDemoMode,
                serviceIds: serviceIds
            )
            await refreshCustomServices()
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func testCustomService(id: String, override: CustomServiceConfig? = nil) async -> CustomServiceTestResult? {
        do {
            let result = try await apiClient.testCustomService(
                baseURL: serverBaseURL,
                demoMode: isDemoMode,
                serviceId: id,
                override: override
            )
            if result.ok {
                hapticSuccessTrigger += 1
                showToast("\(result.message) (\(result.latencyMs) ms)", isError: false)
            } else {
                showToast(result.message, isError: true)
            }
            return result
        } catch {
            showToast(error.localizedDescription, isError: true)
            return nil
        }
    }

    // MARK: - Categorized Apps Actions

    public func updateCategoryService(id: String, payload: CategoryServiceUpdateRequest) async -> Bool {
        do {
            let res = try await apiClient.updateCategoryService(
                baseURL: serverBaseURL,
                demoMode: isDemoMode,
                serviceId: id,
                payload: payload
            )
            hapticSuccessTrigger += 1
            showToast("Application « \(res.service.name) » personnalisée.", isError: false)
            if let svc = try? await apiClient.fetchServices(baseURL: serverBaseURL, demoMode: isDemoMode) {
                self.categories = svc.categories
            }
            return true
        } catch {
            showToast(error.localizedDescription, isError: true)
            return false
        }
    }

    public func moveCategoryService(id: String, direction: String) async {
        do {
            try await apiClient.moveCategoryService(
                baseURL: serverBaseURL,
                demoMode: isDemoMode,
                serviceId: id,
                direction: direction
            )
            if let svc = try? await apiClient.fetchServices(baseURL: serverBaseURL, demoMode: isDemoMode) {
                self.categories = svc.categories
            }
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func testCategoryService(id: String, override: CategoryServiceTestRequest? = nil) async -> CategoryServiceTestResponse? {
        do {
            return try await apiClient.testCategoryService(
                baseURL: serverBaseURL,
                demoMode: isDemoMode,
                serviceId: id,
                override: override
            )
        } catch {
            showToast(error.localizedDescription, isError: true)
            return nil
        }
    }

    public func deleteCategoryService(id: String) async -> Bool {
        do {
            try await apiClient.deleteCategoryService(
                baseURL: serverBaseURL,
                demoMode: isDemoMode,
                serviceId: id
            )
            hapticImpactTrigger += 1
            showToast("Application retirée.", isError: false)
            if let svc = try? await apiClient.fetchServices(baseURL: serverBaseURL, demoMode: isDemoMode) {
                self.categories = svc.categories
            }
            return true
        } catch {
            showToast(error.localizedDescription, isError: true)
            return false
        }
    }

    // MARK: - Incidents & Alert Banners

    public func refreshIncidents(activeOnly: Bool = false) async {
        guard isDemoMode || !serverBaseURL.isEmpty else { return }
        if let list = try? await apiClient.fetchIncidents(
            baseURL: serverBaseURL,
            demoMode: isDemoMode,
            activeOnly: activeOnly,
            limit: 50
        ) {
            self.incidents = list
            if let activeID = activeServerProfile?.id {
                persistCachedIncidents(list, for: activeID)
            }
            persistTelemetrySnapshot()
        }
    }

    public func acknowledgeIncident(id: String) async {
        do {
            try await apiClient.acknowledgeIncident(baseURL: serverBaseURL, demoMode: isDemoMode, incidentId: id)
            hapticSuccessTrigger += 1
            showToast("Incident acquitté.", isError: false)
            await refreshIncidents()
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func muteServiceAlerts(serviceId: String, minutes: Int = 60) async {
        do {
            try await apiClient.muteServiceAlerts(
                baseURL: serverBaseURL,
                demoMode: isDemoMode,
                serviceId: serviceId,
                minutes: minutes
            )
            hapticImpactTrigger += 1
            showToast("Alertes mises en sourdine (\(minutes) min).", isError: false)
            await refreshCustomServices()
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func unmuteServiceAlerts(serviceId: String) async {
        do {
            try await apiClient.unmuteServiceAlerts(baseURL: serverBaseURL, demoMode: isDemoMode, serviceId: serviceId)
            hapticImpactTrigger += 1
            showToast("Sourdine levée.", isError: false)
            await refreshCustomServices()
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func dismissAlertBanner(id: String) {
        pushManager.dismissBanner(id: id)
    }

    // MARK: - Notification Channels & APNs

    public func refreshNotificationChannels() async {
        guard isDemoMode || !serverBaseURL.isEmpty else { return }
        do {
            notificationChannels = try await apiClient.fetchNotificationChannels(baseURL: serverBaseURL, demoMode: isDemoMode)
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func saveNotificationChannels(_ channels: NotificationChannelsResponse) async -> Bool {
        do {
            notificationChannels = try await apiClient.saveNotificationChannels(
                baseURL: serverBaseURL,
                demoMode: isDemoMode,
                channels: channels
            )
            hapticSuccessTrigger += 1
            showToast("Canaux de notification enregistrés.", isError: false)
            return true
        } catch {
            showToast(error.localizedDescription, isError: true)
            return false
        }
    }

    public func testNotificationChannel(channelId: String? = nil, channelType: String? = nil) async -> TestNotificationResult? {
        do {
            let result = try await apiClient.testNotification(
                baseURL: serverBaseURL,
                demoMode: isDemoMode,
                request: TestNotificationRequest(channelId: channelId, channelType: channelType)
            )
            if result.ok {
                hapticSuccessTrigger += 1
            }
            showToast(result.message ?? (result.ok ? "Test envoyé." : "Échec partiel de l'envoi."), isError: !result.ok)
            return result
        } catch {
            showToast(error.localizedDescription, isError: true)
            return nil
        }
    }

    public func requestPushAuthorization() async -> Bool {
        await pushManager.requestAuthorization()
    }

    public func handleRegisteredDeviceToken(_ data: Data) async {
        guard !isDemoMode, !serverBaseURL.isEmpty else { return }
        await pushManager.registerDeviceToken(
            data,
            apiClient: apiClient,
            baseURL: serverBaseURL,
            bearerToken: activeBearerToken
        )
    }

    // MARK: - Declarative YAML Config

    public func fetchYAMLConfig() async -> YAMLConfigResponse? {
        do {
            let response = try await apiClient.fetchConfigYAML(baseURL: serverBaseURL, demoMode: isDemoMode)
            self.yamlConfig = response
            return response
        } catch {
            showToast(error.localizedDescription, isError: true)
            return nil
        }
    }

    public func validateYAMLConfig(_ yaml: String) async -> YAMLValidationResponse? {
        do {
            return try await apiClient.validateConfigYAML(baseURL: serverBaseURL, demoMode: isDemoMode, yaml: yaml)
        } catch {
            showToast(error.localizedDescription, isError: true)
            return nil
        }
    }

    public func saveYAMLConfig(_ yaml: String) async -> YAMLValidationResponse? {
        do {
            let response = try await apiClient.saveConfigYAML(baseURL: serverBaseURL, demoMode: isDemoMode, yaml: yaml)
            if response.valid {
                hapticSuccessTrigger += 1
                showToast(response.message ?? "Configuration YAML appliquée.", isError: false)
                await refreshAll(silent: true)
            } else {
                showToast(response.errors.first ?? "YAML invalide.", isError: true)
            }
            return response
        } catch {
            showToast(error.localizedDescription, isError: true)
            return nil
        }
    }

    public func exportYAMLConfig() async -> String? {
        do {
            return try await apiClient.exportConfigYAML(baseURL: serverBaseURL, demoMode: isDemoMode)
        } catch {
            showToast(error.localizedDescription, isError: true)
            return nil
        }
    }

    // MARK: - Discovery & Apple TV Encrypted Pairing

    public func scanLANAndServerDiscovery() async {
        isLoadingDiscoveryLAN = true
        defer { isLoadingDiscoveryLAN = false }

        async let localBonjour = discoveryService.scanLANServices(timeoutSeconds: 2.5)
        let serverItems: [DiscoveryServerItem]
        if isDemoMode || !serverBaseURL.isEmpty {
            serverItems = (try? await apiClient.fetchLANDiscovery(baseURL: serverBaseURL, demoMode: isDemoMode)) ?? []
        } else {
            serverItems = []
        }

        let localItems = await localBonjour
        var merged: [DiscoveryServerItem] = []
        var seenKeys: Set<String> = []

        for item in localItems + serverItems {
            let key = "\(item.serviceType.lowercased())|\(item.host.lowercased())|\(item.port)"
            if seenKeys.insert(key).inserted {
                merged.append(item)
            }
        }
        lanDiscoveryItems = merged
    }

    public func fetchDiscoveryQR() async -> DiscoveryQRResponse? {
        guard isDemoMode || !serverBaseURL.isEmpty else { return nil }
        return try? await apiClient.fetchDiscoveryQR(baseURL: serverBaseURL, demoMode: isDemoMode)
    }

    public func applyReceivedPairingPayload(_ payload: PairingTransferPayload) async {
        await addOrSelectServer(
            name: payload.serverName,
            baseURL: payload.baseUrl,
            bearerToken: payload.apiToken
        )
        needsOnboarding = false
        hapticSuccessTrigger += 1
        showToast("Serveur « \(payload.serverName) » appairé de manière chiffrée.", isError: false)
    }

    public func pairAppleTV(target: DiscoveryServerItem? = nil, pin: String) async -> Bool {
        guard !serverBaseURL.isEmpty || isDemoMode else {
            showToast("Connectez d'abord un serveur sur cet appareil.", isError: true)
            return false
        }
        let payload = PairingTransferPayload(
            serverName: activeServerName,
            baseUrl: isDemoMode ? "https://panel.example.ts.net" : serverBaseURL,
            apiToken: activeBearerToken ?? "",
            configYamlSnippet: nil
        )
        let ok = await pairingService.sendPairingPayload(
            payload,
            pin: pin,
            localTarget: target,
            relayBaseURL: isDemoMode ? nil : serverBaseURL,
            apiClient: apiClient
        )
        if ok {
            hapticSuccessTrigger += 1
            showToast("Configuration envoyée à l'Apple TV.", isError: false)
        } else if let error = pairingService.lastError {
            showToast(error, isError: true)
        }
        return ok
    }

    // MARK: - Filtered Collections

    public var filteredResources: [PveResource] {
        let list = pveOverview?.resources ?? []
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return list }
        return list.filter {
            $0.name.lowercased().contains(q)
            || String($0.vmid).contains(q)
            || ($0.node?.lowercased().contains(q) == true)
            || $0.tags.contains { $0.lowercased().contains(q) }
        }
    }

    public var filteredCategories: [ServiceCategory] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return categories }
        return categories.compactMap { category in
            if category.name.lowercased().contains(q) {
                return category
            }
            let matching = category.services.filter {
                $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
            }
            return matching.isEmpty ? nil : ServiceCategory(name: category.name, services: matching)
        }
    }

    // MARK: - Smart Alerts

    public var smartAlerts: [SmartAlert] {
        var alerts: [SmartAlert] = []

        if let pve = pveOverview {
            if !pve.online {
                alerts.append(SmartAlert(
                    id: "pve-offline",
                    severity: .critical,
                    title: "Hôte Proxmox hors ligne",
                    subtitle: "L'API Proxmox VE ne répond pas sur \(pve.node.name).",
                    targetTab: .proxmox
                ))
            }

            if let drives = pve.externalStorage?.drives {
                let unhealthy = drives.filter { !$0.isHealthy }
                if !unhealthy.isEmpty {
                    alerts.append(SmartAlert(
                        id: "smart-warn",
                        severity: .critical,
                        title: "Alerte S.M.A.R.T. sur \(unhealthy.count) disque(s)",
                        subtitle: unhealthy.map(\.label).joined(separator: ", "),
                        targetTab: .storage
                    ))
                }
                let nearFullDrives = drives.filter { $0.usedPct >= 90 }
                if !nearFullDrives.isEmpty {
                    alerts.append(SmartAlert(
                        id: "drives-full",
                        severity: .warning,
                        title: "\(nearFullDrives.count) disque(s) ≥ 90 %",
                        subtitle: nearFullDrives.map { "\($0.label) (\(Int($0.usedPct)) %)" }.joined(separator: " • "),
                        targetTab: .storage
                    ))
                }
            }

            let highStorages = pve.node.storages.filter { $0.usedPct >= 80 }
            if !highStorages.isEmpty {
                alerts.append(SmartAlert(
                    id: "pve-storage-high",
                    severity: .warning,
                    title: "Datastore Proxmox ≥ 80 %",
                    subtitle: highStorages.map { "\($0.name) (\(Int($0.usedPct)) %)" }.joined(separator: ", "),
                    targetTab: .storage
                ))
            }
        }

        let activeIncidents = incidents.filter(\.isActive)
        for incident in activeIncidents.prefix(3) {
            alerts.append(SmartAlert(
                id: "incident-\(incident.id)",
                severity: incident.severity.lowercased() == "warning" ? .warning : .critical,
                title: incident.title,
                subtitle: incident.message.isEmpty ? incident.serviceName : incident.message,
                targetTab: .services
            ))
        }

        let offlineServices = categories.flatMap(\.services).filter { !$0.online }
        if !offlineServices.isEmpty && activeIncidents.isEmpty {
            alerts.append(SmartAlert(
                id: "services-offline",
                severity: .critical,
                title: "\(offlineServices.count) service(s) hors ligne",
                subtitle: offlineServices.map(\.name).joined(separator: ", "),
                targetTab: .services
            ))
        }

        let pendingRequests = (opsOverview?.seerrRequests ?? []).filter(\.isPending)
        if !pendingRequests.isEmpty {
            alerts.append(SmartAlert(
                id: "seerr-pending",
                severity: .info,
                title: "\(pendingRequests.count) demande(s) Jellyseerr en attente",
                subtitle: pendingRequests.prefix(2).map(\.title).joined(separator: " • "),
                targetTab: .operations
            ))
        }

        if let unsynced = usersOverview?.counts.unsyncedCount, unsynced > 0 {
            alerts.append(SmartAlert(
                id: "users-unsynced",
                severity: .info,
                title: "\(unsynced) compte(s) Jellyfin non importé(s)",
                subtitle: "Synchronisation disponible vers Jellyseerr en un toucher.",
                targetTab: .users
            ))
        }

        if availableUpdatesCount > 0 {
            alerts.append(SmartAlert(
                id: "updates-available",
                severity: .info,
                title: "\(availableUpdatesCount) cible(s) prêtes à être mises à jour",
                subtitle: "PVE Center, Proxmox VE, LXC/VMs & Docker Compose.",
                targetTab: .updates
            ))
        }

        return alerts
    }

    // MARK: - Existing Actions (PVE, Seerr, qBit, Users)

    public func executePveAction(resource: PveResource, action: PveAction) async {
        let targetNode: String? = {
            if let guestNode = resource.node?.trimmingCharacters(in: .whitespacesAndNewlines), !guestNode.isEmpty {
                return guestNode
            }
            if let selected = selectedClusterNode?.trimmingCharacters(in: .whitespacesAndNewlines),
               !selected.isEmpty,
               selected != "*",
               selected.lowercased() != "all" {
                return selected
            }
            return nil
        }()
        do {
            try await apiClient.performPveAction(
                baseURL: serverBaseURL,
                demoMode: isDemoMode,
                type: resource.type,
                vmid: resource.vmid,
                action: action,
                node: targetNode
            )
            hapticSuccessTrigger += 1
            showToast("Commande « \(action.shortLabel) » envoyée à \(resource.name).", isError: false)
            await refreshAll(silent: true)
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func decideSeerrRequest(id: Int, approve: Bool) async {
        do {
            try await apiClient.decideSeerrRequest(
                baseURL: serverBaseURL,
                demoMode: isDemoMode,
                requestId: id,
                approve: approve
            )
            hapticSuccessTrigger += 1
            showToast(approve ? "Demande approuvée." : "Demande refusée.", isError: false)
            await refreshOpsOnly()
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func toggleQbitSpeedMode() async {
        do {
            let enabled = try await apiClient.toggleQbitSpeedMode(baseURL: serverBaseURL, demoMode: isDemoMode)
            hapticImpactTrigger += 1
            showToast(enabled ? "Mode Tortue activé." : "Vitesse normale rétablie.", isError: false)
            await refreshOpsOnly()
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func controlTorrent(hash: String, pause: Bool) async {
        do {
            try await apiClient.controlTorrent(
                baseURL: serverBaseURL,
                demoMode: isDemoMode,
                hash: hash,
                pause: pause
            )
            hapticImpactTrigger += 1
            await refreshOpsOnly()
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func triggerMediaScan(target: String) async {
        do {
            try await apiClient.triggerMediaScan(baseURL: serverBaseURL, demoMode: isDemoMode, target: target)
            hapticSuccessTrigger += 1
            showToast("Scan \(target.capitalized) déclenché.", isError: false)
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func createUser(_ payload: CreateUserRequest) async -> Bool {
        do {
            try await apiClient.createUser(baseURL: serverBaseURL, demoMode: isDemoMode, payload: payload)
            hapticSuccessTrigger += 1
            showToast("Compte « \(payload.username) » créé.", isError: false)
            await refreshUsersOnly()
            return true
        } catch {
            showToast(error.localizedDescription, isError: true)
            return false
        }
    }

    public func syncMissingUsers(userIDs: [String]? = nil) async {
        do {
            let imported = try await apiClient.syncUsers(
                baseURL: serverBaseURL,
                demoMode: isDemoMode,
                payload: SyncUsersRequest(jellyfinUserIds: userIDs, autoApprove: true)
            )
            hapticSuccessTrigger += 1
            showToast("\(imported) compte(s) importé(s) vers Jellyseerr.", isError: false)
            await refreshUsersOnly()
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func updateUser(id: String, payload: UpdateUserRequest) async -> Bool {
        do {
            try await apiClient.updateUser(baseURL: serverBaseURL, demoMode: isDemoMode, jellyfinId: id, payload: payload)
            hapticSuccessTrigger += 1
            showToast("Permissions mises à jour.", isError: false)
            await refreshUsersOnly()
            return true
        } catch {
            showToast(error.localizedDescription, isError: true)
            return false
        }
    }

    public func resetPassword(id: String, newPassword: String) async -> Bool {
        do {
            try await apiClient.resetPassword(
                baseURL: serverBaseURL,
                demoMode: isDemoMode,
                jellyfinId: id,
                newPassword: newPassword
            )
            hapticSuccessTrigger += 1
            showToast("Mot de passe réinitialisé.", isError: false)
            return true
        } catch {
            showToast(error.localizedDescription, isError: true)
            return false
        }
    }

    public func deleteUser(id: String, name: String) async -> Bool {
        do {
            try await apiClient.deleteUser(baseURL: serverBaseURL, demoMode: isDemoMode, jellyfinId: id)
            hapticSuccessTrigger += 1
            showToast("Compte « \(name) » supprimé.", isError: false)
            await refreshUsersOnly()
            return true
        } catch {
            showToast(error.localizedDescription, isError: true)
            return false
        }
    }

    // MARK: - Toast Helper

    public func showToast(_ text: String, isError: Bool) {
        let message = ToastMessage(isError: isError, text: text)
        toast = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            if self?.toast?.id == message.id {
                self?.toast = nil
            }
        }
    }

    // MARK: - Private Realtime, Push & Persistence Wiring

    private func configureRealtimeAndPushHandlers() {
        pushManager.registerPushHandlers(
            onMuteService: { [weak self] serviceId, minutes in
                await self?.muteServiceAlerts(serviceId: serviceId, minutes: minutes)
            },
            onTestService: { [weak self] serviceId in
                _ = await self?.testCustomService(id: serviceId)
            },
            onOpenIncident: { [weak self] _ in
                self?.selectedTab = .services
            }
        )

        realtimeClient.onEvent = { [weak self] envelope in
            self?.handleRealtimeEvent(envelope)
        }
    }

    private func handleRealtimeEvent(_ envelope: RealtimeEventEnvelope) {
        switch envelope.eventType {
        case .configReloaded:
            if let hash = envelope.configHash, let activeID = activeServerProfile?.id {
                updateSwiftDataProfile(id: activeID) { entity in
                    entity.configHash = hash
                }
            }
            Task { await refreshAll(silent: true) }

        case .serviceStatusChanged:
            if let serviceId = envelope.serviceId,
               let idx = customServices.firstIndex(where: { $0.id == serviceId }) {
                if let status = envelope.status {
                    customServices[idx].status = status
                    customServices[idx].online = (status.lowercased() == "up")
                }
                if let latency = envelope.latencyMs {
                    customServices[idx].latencyMs = latency
                }
                if let msg = envelope.message {
                    customServices[idx].message = msg
                }
            }
            Task {
                if let svc = try? await apiClient.fetchServices(baseURL: serverBaseURL, demoMode: isDemoMode) {
                    self.categories = svc.categories
                }
                await refreshCustomServices()
            }

        case .alertTriggered, .alertResolved:
            pushManager.handleRealtimeEvent(envelope, isAppInBackground: isAppInBackground)
            Task {
                await refreshIncidents()
                await refreshCustomServices()
            }

        case .incidentAcknowledged:
            Task {
                await refreshIncidents()
            }

        case .pairingCompleted:
            Task {
                await pairingService.handleRealtimePairingCompleted(pin: envelope.pin)
            }

        case .updateJobProgress:
            Task {
                await refreshUpdatesOnly()
            }

        case .unknown:
            break
        }
    }

    private func syncAPIClientToken() async {
        if isDemoMode {
            await apiClient.setBearerToken(nil)
            return
        }
        await apiClient.setBearerToken(activeBearerToken)
    }

    private func connectRealtimeIfNeeded() {
        guard !isDemoMode, !serverBaseURL.isEmpty else {
            realtimeClient.disconnect()
            return
        }
        realtimeClient.connect(baseURL: serverBaseURL, bearerToken: activeBearerToken)
    }

    private func resetDomainState() {
        user = nil
        pveOverview = nil
        selectedClusterNode = nil
        categories = []
        widgets = nil
        usersOverview = nil
        opsOverview = nil
        setupStatus = nil
        onboardingStatus = nil
        customServices = []
        incidents = []
        notificationChannels = nil
        yamlConfig = nil
        updatesOverview = nil
        updatesSetupInfo = nil
        lastUpdated = nil
        connectionError = nil
    }

    private func persistTelemetrySnapshot() {
        guard let pve = pveOverview else { return }
        let activeIncidents = incidents.filter(\.isActive)
        let resolvedNodeName = pve.node.name.isEmpty
            ? (pve.selectedNode ?? selectedClusterNode ?? "pve")
            : pve.node.name
        let snapshot = TelemetryWidgetSnapshot(
            updatedAt: Date(),
            serverName: activeServerName,
            nodeName: resolvedNodeName,
            online: pve.online,
            cpuPct: pve.node.cpuPct,
            memPct: pve.node.memPct,
            runningGuests: pve.counts.running,
            totalGuests: pve.counts.total,
            activeIncidentsCount: activeIncidents.count,
            latestIncidentTitle: activeIncidents.first?.title
        )
        latestTelemetrySnapshot = snapshot
        telemetrySnapshotStore.save(snapshot)
    }

    private static func defaultServerName(for baseURL: String) -> String {
        if let host = URL(string: baseURL)?.host, !host.isEmpty {
            return host.split(separator: ".").first.map(String.init) ?? host
        }
        return baseURL.isEmpty ? "Serveur PVE" : baseURL
    }

    private func persistSavedServersToDefaults() {
        if let data = try? JSONEncoder().encode(savedServers) {
            UserDefaults.standard.set(data, forKey: StorageKeys.savedServers)
        }
    }

    private func loadAndMigrateProfiles(legacyURL: String, preferredActiveID: UUID?) {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<ServerProfileEntity>(
            sortBy: [SortDescriptor(\.lastConnectedAt, order: .reverse), SortDescriptor(\.addedAt, order: .reverse)]
        )
        let entities = (try? context.fetch(descriptor)) ?? []

        if !entities.isEmpty {
            self.savedServers = entities.map { $0.toSavedServerProfile() }
            if let preferred = preferredActiveID,
               let match = self.savedServers.first(where: { $0.id == preferred }) {
                self.serverBaseURL = match.baseURL
                self.activeProfileID = match.id
            } else if self.serverBaseURL.isEmpty,
                      let defaultEntity = entities.first(where: \.isDefault) ?? entities.first {
                self.serverBaseURL = defaultEntity.baseURLString
                self.activeProfileID = defaultEntity.id
            }
            persistSavedServersToDefaults()
            return
        }

        // Migrate from legacy UserDefaults savedServers or single URL into SwiftData once.
        let defaults = UserDefaults.standard
        var initialProfiles: [SavedServerProfile] = []
        if let data = defaults.data(forKey: StorageKeys.savedServers),
           let decoded = try? JSONDecoder().decode([SavedServerProfile].self, from: data) {
            initialProfiles = decoded
        } else if !legacyURL.isEmpty {
            initialProfiles = [
                SavedServerProfile(
                    name: Self.defaultServerName(for: legacyURL),
                    baseURL: legacyURL,
                    isDefault: true
                ),
            ]
        }

        self.savedServers = initialProfiles
        for (idx, profile) in initialProfiles.enumerated() {
            upsertSwiftDataProfile(profile, markDefault: idx == 0)
        }
        if self.activeProfileID == nil,
           let match = initialProfiles.first(where: { $0.baseURL.caseInsensitiveCompare(legacyURL) == .orderedSame }) ?? initialProfiles.first {
            self.activeProfileID = match.id
            defaults.set(match.id.uuidString, forKey: StorageKeys.activeProfileID)
        }
        persistSavedServersToDefaults()
    }

    private func upsertSwiftDataProfile(_ profile: SavedServerProfile, markDefault: Bool) {
        let context = modelContainer.mainContext
        let targetID = profile.id
        let descriptor = FetchDescriptor<ServerProfileEntity>(
            predicate: #Predicate { $0.id == targetID }
        )

        if markDefault {
            let all = (try? context.fetch(FetchDescriptor<ServerProfileEntity>())) ?? []
            for entity in all where entity.id != targetID {
                entity.isDefault = false
            }
        }

        if let existing = (try? context.fetch(descriptor))?.first {
            existing.name = profile.name
            existing.baseURLString = profile.baseURL
            existing.isDefault = markDefault ? true : profile.isDefault
            existing.usesTailscaleSSO = profile.usesTailscaleSSO
            existing.lastConnectedAt = profile.lastConnectedAt ?? existing.lastConnectedAt
            existing.configHash = profile.configHash ?? existing.configHash
            existing.appearancePreferenceRaw = profile.appearancePreference.rawValue
        } else {
            let entity = ServerProfileEntity(
                id: profile.id,
                name: profile.name,
                baseURLString: profile.baseURL,
                isDefault: markDefault ? true : profile.isDefault,
                usesTailscaleSSO: profile.usesTailscaleSSO,
                lastConnectedAt: profile.lastConnectedAt,
                configHash: profile.configHash,
                appearancePreferenceRaw: profile.appearancePreference.rawValue,
                addedAt: profile.addedAt
            )
            context.insert(entity)
        }
        try? context.save()
    }

    private func updateSwiftDataProfile(id: UUID, mutate: (ServerProfileEntity) -> Void) {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<ServerProfileEntity>(
            predicate: #Predicate { $0.id == id }
        )
        if let entity = (try? context.fetch(descriptor))?.first {
            mutate(entity)
            try? context.save()
        }
    }

    private func deleteSwiftDataProfile(id: UUID) {
        let context = modelContainer.mainContext
        let profileDesc = FetchDescriptor<ServerProfileEntity>(predicate: #Predicate { $0.id == id })
        if let entities = try? context.fetch(profileDesc) {
            for entity in entities { context.delete(entity) }
        }
        let incDesc = FetchDescriptor<CachedIncidentEntity>(predicate: #Predicate { $0.serverProfileID == id })
        if let incEntities = try? context.fetch(incDesc) {
            for entity in incEntities { context.delete(entity) }
        }
        let svcDesc = FetchDescriptor<CachedCustomServiceEntity>(predicate: #Predicate { $0.serverProfileID == id })
        if let svcEntities = try? context.fetch(svcDesc) {
            for entity in svcEntities { context.delete(entity) }
        }
        try? context.save()
    }

    private func hydrateCachesFromSwiftData(for profileID: UUID) {
        let context = modelContainer.mainContext
        let svcDesc = FetchDescriptor<CachedCustomServiceEntity>(
            predicate: #Predicate { $0.serverProfileID == profileID },
            sortBy: [SortDescriptor(\.order, order: .forward)]
        )
        if let cachedServices = try? context.fetch(svcDesc), !cachedServices.isEmpty {
            self.customServices = cachedServices.map { $0.toCustomServiceConfig() }
        }

        let incDesc = FetchDescriptor<CachedIncidentEntity>(
            predicate: #Predicate { $0.serverProfileID == profileID },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        if let cachedIncidents = try? context.fetch(incDesc), !cachedIncidents.isEmpty {
            self.incidents = cachedIncidents.map { $0.toIncidentEvent() }
        }
    }

    private func persistCachedCustomServices(_ list: [CustomServiceConfig], for profileID: UUID) {
        let context = modelContainer.mainContext
        let oldDesc = FetchDescriptor<CachedCustomServiceEntity>(
            predicate: #Predicate { $0.serverProfileID == profileID }
        )
        if let old = try? context.fetch(oldDesc) {
            for item in old { context.delete(item) }
        }
        for svc in list {
            context.insert(CachedCustomServiceEntity(serverProfileID: profileID, service: svc))
        }
        try? context.save()
    }

    private func persistCachedIncidents(_ list: [IncidentEvent], for profileID: UUID) {
        let context = modelContainer.mainContext
        let oldDesc = FetchDescriptor<CachedIncidentEntity>(
            predicate: #Predicate { $0.serverProfileID == profileID }
        )
        if let old = try? context.fetch(oldDesc) {
            for item in old { context.delete(item) }
        }
        for incident in list {
            context.insert(CachedIncidentEntity(serverProfileID: profileID, incident: incident))
        }
        try? context.save()
    }
}
