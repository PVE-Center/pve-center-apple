import Foundation

public enum APIError: LocalizedError, Sendable {
    case invalidBaseURL
    case unauthorized(String)
    case forbidden(String)
    case serverError(statusCode: Int, detail: String)
    case decodingError(String)
    case transportError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "L'URL du serveur est invalide. Vérifiez le format https://..."
        case .unauthorized(let detail):
            return detail
        case .forbidden(let detail):
            return detail
        case .serverError(_, let detail):
            return detail
        case .decodingError(let msg):
            return "Réponse serveur inattendue (\(msg))."
        case .transportError(let msg):
            return msg
        }
    }
}

private struct ErrorDetailBody: Codable {
    let detail: String?
}

public actor APIClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let demoStore: DemoDataStore
    private var bearerToken: String?

    public init(demoStore: DemoDataStore = .shared) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = dec

        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = enc

        self.demoStore = demoStore
    }

    public func setBearerToken(_ token: String?) {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bearerToken = (trimmed?.isEmpty == false) ? trimmed : nil
    }

    public func currentBearerToken() -> String? {
        bearerToken
    }

    public static func normalizeBaseURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let withScheme = trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://")
            ? trimmed
            : "https://\(trimmed)"
        return withScheme.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: - Auth & Health

    public func checkHealth(baseURL: String) async throws -> Bool {
        let normalized = Self.normalizeBaseURL(baseURL)
        let (_, http) = try await performRawRequest(path: "/api/health", method: "GET", bodyData: nil, baseURL: normalized)
        return (200..<300).contains(http.statusCode)
    }

    public func login(
        baseURL: String,
        demoMode: Bool,
        payload: AuthLoginRequest
    ) async throws -> AuthLoginResponse {
        if demoMode {
            return try await demoStore.login(payload)
        }
        return try await send(path: "/api/auth/login", method: "POST", body: payload, baseURL: baseURL)
    }

    public func testConnection(baseURL: String, bearerToken: String? = nil) async throws -> AuthUser {
        let normalized = Self.normalizeBaseURL(baseURL)
        return try await send(path: "/api/me", baseURL: normalized, bearerToken: bearerToken)
    }

    // MARK: - Onboarding

    public func fetchOnboardingStatus(
        baseURL: String,
        bearerToken: String? = nil,
        demoMode: Bool
    ) async throws -> OnboardingStatusResponse {
        if demoMode {
            return await demoStore.onboardingStatus()
        }
        return try await send(path: "/api/onboarding/status", baseURL: baseURL, bearerToken: bearerToken)
    }

    public func initOnboarding(
        baseURL: String,
        bearerToken: String? = nil,
        demoMode: Bool,
        payload: OnboardingInitRequest
    ) async throws -> OnboardingInitResponse {
        if demoMode {
            return await demoStore.initOnboarding(payload)
        }
        return try await send(
            path: "/api/onboarding/init",
            method: "POST",
            body: payload,
            baseURL: baseURL,
            bearerToken: bearerToken
        )
    }

    // MARK: - Core Dashboard Reads

    public func fetchMe(baseURL: String, demoMode: Bool) async throws -> AuthUser {
        if demoMode {
            return await demoStore.currentUser()
        }
        return try await send(path: "/api/me", baseURL: baseURL)
    }

    public func fetchPveOverview(
        baseURL: String,
        demoMode: Bool,
        node: String? = nil
    ) async throws -> PveOverview {
        let targetNode = normalizedNodeParam(node)
        if demoMode {
            return await demoStore.pveOverview(node: targetNode)
        }
        let path = pathWithNodeQuery("/api/pve/overview", node: targetNode)
        return try await send(path: path, baseURL: baseURL)
    }

    public func fetchServices(baseURL: String, demoMode: Bool) async throws -> ServicesResponse {
        if demoMode {
            let categories = await demoStore.servicesCategories()
            return ServicesResponse(categories: categories)
        }
        return try await send(path: "/api/services", baseURL: baseURL)
    }

    public func fetchWidgets(baseURL: String, demoMode: Bool) async throws -> WidgetsMap {
        if demoMode {
            return await demoStore.widgets()
        }
        return try await send(path: "/api/widgets/all", baseURL: baseURL)
    }

    public func fetchOpsOverview(baseURL: String, demoMode: Bool) async throws -> OpsOverview {
        if demoMode {
            return await demoStore.opsOverview()
        }
        return try await send(path: "/api/ops/overview", baseURL: baseURL)
    }

    public func fetchUsers(baseURL: String, demoMode: Bool) async throws -> UsersOverview {
        if demoMode {
            return await demoStore.usersOverview()
        }
        return try await send(path: "/api/users", baseURL: baseURL)
    }

    public func fetchSetupStatus(baseURL: String, demoMode: Bool) async throws -> SetupStatusResponse {
        if demoMode {
            return await demoStore.setupStatus()
        }
        return try await send(path: "/api/setup/status", baseURL: baseURL)
    }

    // MARK: - Custom Services

    public func fetchCustomServices(baseURL: String, demoMode: Bool) async throws -> [CustomServiceConfig] {
        if demoMode {
            return await demoStore.customServicesList()
        }
        let response: CustomServicesListResponse = try await send(path: "/api/custom-services", baseURL: baseURL)
        return response.services
    }

    public func createCustomService(
        baseURL: String,
        demoMode: Bool,
        service: CustomServiceConfig
    ) async throws -> CustomServiceConfig {
        if demoMode {
            return await demoStore.createCustomService(service)
        }
        let response: CustomServiceMutationResponse = try await send(
            path: "/api/custom-services",
            method: "POST",
            body: service,
            baseURL: baseURL
        )
        return response.service
    }

    public func updateCustomService(
        baseURL: String,
        demoMode: Bool,
        serviceId: String,
        service: CustomServiceConfig
    ) async throws -> CustomServiceConfig {
        if demoMode {
            return try await demoStore.updateCustomService(id: serviceId, service: service)
        }
        let response: CustomServiceMutationResponse = try await send(
            path: "/api/custom-services/\(escapePath(serviceId))",
            method: "PUT",
            body: service,
            baseURL: baseURL
        )
        return response.service
    }

    public func deleteCustomService(
        baseURL: String,
        demoMode: Bool,
        serviceId: String
    ) async throws {
        if demoMode {
            try await demoStore.deleteCustomService(id: serviceId)
            return
        }
        try await sendVoid(
            path: "/api/custom-services/\(escapePath(serviceId))",
            method: "DELETE",
            baseURL: baseURL
        )
    }

    public func reorderCustomServices(
        baseURL: String,
        demoMode: Bool,
        serviceIds: [String]
    ) async throws {
        if demoMode {
            await demoStore.reorderCustomServices(serviceIds: serviceIds)
            return
        }
        try await sendVoid(
            path: "/api/custom-services/reorder",
            method: "POST",
            body: CustomServicesReorderRequest(serviceIds: serviceIds),
            baseURL: baseURL
        )
    }

    public func testCustomService(
        baseURL: String,
        demoMode: Bool,
        serviceId: String,
        override: CustomServiceConfig? = nil
    ) async throws -> CustomServiceTestResult {
        if demoMode {
            return await demoStore.testCustomService(id: serviceId, override: override)
        }
        let encodedID = escapePath(serviceId)
        if let override {
            return try await send(
                path: "/api/custom-services/\(encodedID)/test",
                method: "POST",
                body: override,
                baseURL: baseURL
            )
        }
        return try await send(
            path: "/api/custom-services/\(encodedID)/test",
            method: "POST",
            baseURL: baseURL
        )
    }

    // MARK: - Categorized Apps Customization

    public func updateCategoryService(
        baseURL: String,
        demoMode: Bool,
        serviceId: String,
        payload: CategoryServiceUpdateRequest
    ) async throws -> CategoryServiceMutationResponse {
        if demoMode {
            return try await demoStore.updateCategoryService(id: serviceId, payload: payload)
        }
        return try await send(
            path: "/api/services/items/\(escapePath(serviceId))",
            method: "PUT",
            body: payload,
            baseURL: baseURL
        )
    }

    public func moveCategoryService(
        baseURL: String,
        demoMode: Bool,
        serviceId: String,
        direction: String
    ) async throws {
        if demoMode {
            await demoStore.moveCategoryService(id: serviceId, direction: direction)
            return
        }
        try await sendVoid(
            path: "/api/services/items/\(escapePath(serviceId))/move",
            method: "POST",
            body: CategoryServiceMoveRequest(direction: direction),
            baseURL: baseURL
        )
    }

    public func testCategoryService(
        baseURL: String,
        demoMode: Bool,
        serviceId: String,
        override: CategoryServiceTestRequest? = nil
    ) async throws -> CategoryServiceTestResponse {
        if demoMode {
            return await demoStore.testCategoryService(id: serviceId, override: override)
        }
        let encodedID = escapePath(serviceId)
        if let override {
            return try await send(
                path: "/api/services/items/\(encodedID)/test",
                method: "POST",
                body: override,
                baseURL: baseURL
            )
        }
        return try await send(
            path: "/api/services/items/\(encodedID)/test",
            method: "POST",
            baseURL: baseURL
        )
    }

    public func deleteCategoryService(
        baseURL: String,
        demoMode: Bool,
        serviceId: String
    ) async throws {
        if demoMode {
            try await demoStore.deleteCategoryService(id: serviceId)
            return
        }
        try await sendVoid(
            path: "/api/services/items/\(escapePath(serviceId))",
            method: "DELETE",
            baseURL: baseURL
        )
    }

    // MARK: - Incidents & Alert Actions

    public func fetchIncidents(
        baseURL: String,
        demoMode: Bool,
        activeOnly: Bool = false,
        limit: Int = 50
    ) async throws -> [IncidentEvent] {
        if demoMode {
            return await demoStore.incidentsList(activeOnly: activeOnly, limit: limit)
        }
        let query = "active_only=\(activeOnly ? "true" : "false")&limit=\(max(1, limit))"
        let response: IncidentsListResponse = try await send(path: "/api/incidents?\(query)", baseURL: baseURL)
        return response.incidents
    }

    public func acknowledgeIncident(
        baseURL: String,
        demoMode: Bool,
        incidentId: String
    ) async throws {
        if demoMode {
            try await demoStore.acknowledgeIncident(id: incidentId)
            return
        }
        try await sendVoid(
            path: "/api/incidents/\(escapePath(incidentId))/ack",
            method: "POST",
            baseURL: baseURL
        )
    }

    public func muteServiceAlerts(
        baseURL: String,
        demoMode: Bool,
        serviceId: String,
        minutes: Int = 60
    ) async throws {
        if demoMode {
            await demoStore.muteService(id: serviceId, minutes: minutes)
            return
        }
        try await sendVoid(
            path: "/api/incidents/services/\(escapePath(serviceId))/mute",
            method: "POST",
            body: MuteServiceRequest(minutes: minutes),
            baseURL: baseURL
        )
    }

    public func unmuteServiceAlerts(
        baseURL: String,
        demoMode: Bool,
        serviceId: String
    ) async throws {
        if demoMode {
            await demoStore.unmuteService(id: serviceId)
            return
        }
        try await sendVoid(
            path: "/api/incidents/services/\(escapePath(serviceId))/mute",
            method: "DELETE",
            baseURL: baseURL
        )
    }

    // MARK: - Notification Channels & APNs Devices

    public func fetchNotificationChannels(
        baseURL: String,
        demoMode: Bool
    ) async throws -> NotificationChannelsResponse {
        if demoMode {
            return await demoStore.notificationChannelsOverview()
        }
        return try await send(path: "/api/notifications/channels", baseURL: baseURL)
    }

    public func saveNotificationChannels(
        baseURL: String,
        demoMode: Bool,
        channels: NotificationChannelsResponse
    ) async throws -> NotificationChannelsResponse {
        if demoMode {
            return await demoStore.saveNotificationChannels(channels)
        }
        return try await send(
            path: "/api/notifications/channels",
            method: "PUT",
            body: channels,
            baseURL: baseURL
        )
    }

    public func testNotification(
        baseURL: String,
        demoMode: Bool,
        request: TestNotificationRequest
    ) async throws -> TestNotificationResult {
        if demoMode {
            return await demoStore.testNotification(request)
        }
        return try await send(
            path: "/api/notifications/test",
            method: "POST",
            body: request,
            baseURL: baseURL
        )
    }

    public func registerAPNsDevice(
        baseURL: String,
        bearerToken: String? = nil,
        demoMode: Bool,
        payload: APNsDeviceRegisterRequest
    ) async throws {
        if demoMode {
            await demoStore.registerAPNsDevice(payload)
            return
        }
        try await sendVoid(
            path: "/api/notifications/devices",
            method: "POST",
            body: payload,
            baseURL: baseURL,
            bearerToken: bearerToken
        )
    }

    public func unregisterAPNsDevice(
        baseURL: String,
        bearerToken: String? = nil,
        demoMode: Bool,
        deviceToken: String
    ) async throws {
        if demoMode {
            await demoStore.unregisterAPNsDevice(deviceToken)
            return
        }
        try await sendVoid(
            path: "/api/notifications/devices/\(escapePath(deviceToken))",
            method: "DELETE",
            baseURL: baseURL,
            bearerToken: bearerToken
        )
    }

    // MARK: - Declarative YAML Config

    public func fetchConfigYAML(baseURL: String, demoMode: Bool) async throws -> YAMLConfigResponse {
        if demoMode {
            return await demoStore.fetchConfigYAML()
        }
        return try await send(path: "/api/config/yaml", baseURL: baseURL)
    }

    public func validateConfigYAML(
        baseURL: String,
        demoMode: Bool,
        yaml: String
    ) async throws -> YAMLValidationResponse {
        if demoMode {
            return await demoStore.validateConfigYAML(yaml)
        }
        return try await send(
            path: "/api/config/validate",
            method: "POST",
            body: YAMLConfigUpdateRequest(yaml: yaml),
            baseURL: baseURL
        )
    }

    public func saveConfigYAML(
        baseURL: String,
        demoMode: Bool,
        yaml: String
    ) async throws -> YAMLValidationResponse {
        if demoMode {
            return await demoStore.saveConfigYAML(yaml)
        }
        return try await send(
            path: "/api/config/yaml",
            method: "PUT",
            body: YAMLConfigUpdateRequest(yaml: yaml),
            baseURL: baseURL
        )
    }

    public func exportConfigYAML(baseURL: String, demoMode: Bool) async throws -> String {
        if demoMode {
            return await demoStore.exportConfigYAML()
        }
        let (data, _) = try await performRawRequest(path: "/api/config/export", method: "GET", bodyData: nil, baseURL: baseURL)
        if let text = String(data: data, encoding: .utf8) {
            // Support JSON envelope fallback if backend wraps yaml in JSON.
            if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"),
               let decoded = try? decoder.decode(YAMLConfigResponse.self, from: data) {
                return decoded.yaml
            }
            return text
        }
        throw APIError.decodingError("Contenu YAML illisible.")
    }

    // MARK: - Discovery & Pairing Relay

    public func fetchLANDiscovery(baseURL: String, demoMode: Bool) async throws -> [DiscoveryServerItem] {
        if demoMode {
            return await demoStore.lanDiscoveryServices()
        }
        let response: LANDiscoveryResponse = try await send(path: "/api/discovery/lan", baseURL: baseURL)
        return response.services
    }

    public func fetchDiscoveryQR(baseURL: String, demoMode: Bool) async throws -> DiscoveryQRResponse {
        if demoMode {
            return await demoStore.discoveryQR(baseURL: baseURL)
        }
        return try await send(path: "/api/discovery/qr", baseURL: baseURL)
    }

    public func createPairingSession(
        baseURL: String,
        publicKey: String,
        deviceName: String,
        demoMode: Bool = false
    ) async throws -> PairingSessionInfo {
        if demoMode {
            return await demoStore.createDemoPairingSession(publicKey: publicKey, deviceName: deviceName)
        }
        return try await send(
            path: "/api/pairing/sessions",
            method: "POST",
            body: CreatePairingSessionRequest(publicKey: publicKey, deviceName: deviceName),
            baseURL: baseURL
        )
    }

    public func fetchPairingSession(
        baseURL: String,
        pin: String,
        demoMode: Bool = false
    ) async throws -> PairingSessionInfo {
        if demoMode {
            return try await demoStore.fetchDemoPairingSession(pin: pin)
        }
        return try await send(path: "/api/pairing/sessions/\(escapePath(pin))", baseURL: baseURL)
    }

    public func completePairingSession(
        baseURL: String,
        pin: String,
        payload: PairingCompletePayload,
        demoMode: Bool = false
    ) async throws {
        if demoMode {
            try await demoStore.completeDemoPairingSession(pin: pin, bundle: payload)
            return
        }
        try await sendVoid(
            path: "/api/pairing/sessions/\(escapePath(pin))/complete",
            method: "POST",
            body: payload,
            baseURL: baseURL
        )
    }

    public func fetchPairingPayload(
        baseURL: String,
        pin: String,
        demoMode: Bool = false
    ) async throws -> EncryptedPairingBundle? {
        if demoMode {
            return await demoStore.fetchDemoPairingPayload(pin: pin)
        }
        let path = "/api/pairing/sessions/\(escapePath(pin))/payload"
        let (data, http) = try await performRawRequest(
            path: path,
            method: "GET",
            bodyData: nil,
            baseURL: baseURL,
            allowedStatuses: [200, 202, 204, 425]
        )
        if http.statusCode == 202 || http.statusCode == 204 || http.statusCode == 425 || data.isEmpty {
            return nil
        }
        if let bundle = try? decoder.decode(EncryptedPairingBundle.self, from: data),
           !bundle.ciphertext.isEmpty {
            return bundle
        }
        return nil
    }

    // MARK: - Existing Mutations (Proxmox, Operations, Users, Setup)

    public func performPveAction(
        baseURL: String,
        demoMode: Bool,
        type: PveResourceType,
        vmid: Int,
        action: PveAction,
        node: String? = nil
    ) async throws {
        let targetNode = normalizedNodeParam(node)
        if demoMode {
            try await demoStore.performPveAction(type: type, vmid: vmid, action: action, node: targetNode)
            return
        }
        let path = pathWithNodeQuery("/api/pve/\(type.rawValue)/\(vmid)/\(action.rawValue)", node: targetNode)
        let _: ActionOKResponse = try await send(
            path: path,
            method: "POST",
            baseURL: baseURL
        )
    }

    public func decideSeerrRequest(
        baseURL: String,
        demoMode: Bool,
        requestId: Int,
        approve: Bool
    ) async throws {
        if demoMode {
            try await demoStore.decideSeerrRequest(id: requestId, approve: approve)
            return
        }
        let decision = approve ? "approve" : "decline"
        let _: ActionOKResponse = try await send(
            path: "/api/ops/seerr/\(requestId)/\(decision)",
            method: "POST",
            baseURL: baseURL
        )
    }

    public func toggleQbitSpeedMode(baseURL: String, demoMode: Bool) async throws -> Bool {
        if demoMode {
            return await demoStore.toggleQbitSpeedMode()
        }
        let res: ActionOKResponse = try await send(
            path: "/api/ops/qbit/toggle-speed-mode",
            method: "POST",
            baseURL: baseURL
        )
        return res.altSpeedEnabled ?? false
    }

    public func controlTorrent(
        baseURL: String,
        demoMode: Bool,
        hash: String,
        pause: Bool
    ) async throws {
        if demoMode {
            try await demoStore.controlTorrent(hash: hash, pause: pause)
            return
        }
        let action = pause ? "pause" : "resume"
        let _: ActionOKResponse = try await send(
            path: "/api/ops/qbit/torrent/\(escapePath(hash))/\(action)",
            method: "POST",
            baseURL: baseURL
        )
    }

    public func triggerMediaScan(
        baseURL: String,
        demoMode: Bool,
        target: String
    ) async throws {
        if demoMode { return }
        let _: ActionOKResponse = try await send(
            path: "/api/ops/media/scan/\(escapePath(target))",
            method: "POST",
            baseURL: baseURL
        )
    }

    public func createUser(
        baseURL: String,
        demoMode: Bool,
        payload: CreateUserRequest
    ) async throws {
        if demoMode {
            _ = try await demoStore.createUser(payload)
            return
        }
        let _: ActionOKResponse = try await send(
            path: "/api/users",
            method: "POST",
            body: payload,
            baseURL: baseURL
        )
    }

    public func syncUsers(
        baseURL: String,
        demoMode: Bool,
        payload: SyncUsersRequest
    ) async throws -> Int {
        if demoMode {
            return await demoStore.syncUsers(payload)
        }
        let res: SyncUsersResponse = try await send(
            path: "/api/users/sync",
            method: "POST",
            body: payload,
            baseURL: baseURL
        )
        return res.importedCount
    }

    public func updateUser(
        baseURL: String,
        demoMode: Bool,
        jellyfinId: String,
        payload: UpdateUserRequest
    ) async throws {
        if demoMode {
            try await demoStore.updateUser(id: jellyfinId, req: payload)
            return
        }
        let _: ActionOKResponse = try await send(
            path: "/api/users/\(escapePath(jellyfinId))",
            method: "PATCH",
            body: payload,
            baseURL: baseURL
        )
    }

    public func resetPassword(
        baseURL: String,
        demoMode: Bool,
        jellyfinId: String,
        newPassword: String
    ) async throws {
        if demoMode { return }
        let _: ActionOKResponse = try await send(
            path: "/api/users/\(escapePath(jellyfinId))/password",
            method: "POST",
            body: ResetPasswordRequest(newPassword: newPassword),
            baseURL: baseURL
        )
    }

    public func deleteUser(
        baseURL: String,
        demoMode: Bool,
        jellyfinId: String
    ) async throws {
        if demoMode {
            try await demoStore.deleteUser(id: jellyfinId)
            return
        }
        let _: ActionOKResponse = try await send(
            path: "/api/users/\(escapePath(jellyfinId))",
            method: "DELETE",
            baseURL: baseURL
        )
    }

    // MARK: - Setup Wizard

    public func testServiceConnection(
        baseURL: String,
        demoMode: Bool,
        payload: ServiceTestRequest
    ) async throws -> ServiceTestResponse {
        if demoMode {
            return await demoStore.testServiceConnection(payload)
        }
        return try await send(
            path: "/api/setup/test-service",
            method: "POST",
            body: payload,
            baseURL: baseURL
        )
    }

    public func saveSetupConfig(
        baseURL: String,
        demoMode: Bool,
        payload: SetupConfigUpdateRequest
    ) async throws -> SetupConfigUpdateResponse {
        if demoMode {
            return await demoStore.saveSetupConfig(payload)
        }
        return try await send(
            path: "/api/setup/config",
            method: "PUT",
            body: payload,
            baseURL: baseURL
        )
    }

    // MARK: - Core HTTP Transport

    private func normalizedNodeParam(_ node: String?) -> String? {
        guard let trimmed = node?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func pathWithNodeQuery(_ basePath: String, node: String?) -> String {
        guard let node else { return basePath }
        var components = URLComponents()
        components.path = basePath
        components.queryItems = [URLQueryItem(name: "node", value: node)]
        return components.string ?? basePath
    }

    private func escapePath(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? component
    }

    private func send<ResponseType: Decodable>(
        path: String,
        method: String = "GET",
        baseURL: String,
        bearerToken: String? = nil
    ) async throws -> ResponseType {
        try await sendRequest(path: path, method: method, bodyData: nil, baseURL: baseURL, bearerToken: bearerToken)
    }

    private func send<BodyType: Encodable, ResponseType: Decodable>(
        path: String,
        method: String = "POST",
        body: BodyType,
        baseURL: String,
        bearerToken: String? = nil
    ) async throws -> ResponseType {
        let data = try encoder.encode(body)
        return try await sendRequest(path: path, method: method, bodyData: data, baseURL: baseURL, bearerToken: bearerToken)
    }

    private func sendVoid(
        path: String,
        method: String,
        baseURL: String,
        bearerToken: String? = nil
    ) async throws {
        _ = try await performRawRequest(
            path: path,
            method: method,
            bodyData: nil,
            baseURL: baseURL,
            bearerToken: bearerToken
        )
    }

    private func sendVoid<BodyType: Encodable>(
        path: String,
        method: String,
        body: BodyType,
        baseURL: String,
        bearerToken: String? = nil
    ) async throws {
        let data = try encoder.encode(body)
        _ = try await performRawRequest(
            path: path,
            method: method,
            bodyData: data,
            baseURL: baseURL,
            bearerToken: bearerToken
        )
    }

    private func sendRequest<ResponseType: Decodable>(
        path: String,
        method: String,
        bodyData: Data?,
        baseURL: String,
        bearerToken: String?
    ) async throws -> ResponseType {
        let (data, _) = try await performRawRequest(
            path: path,
            method: method,
            bodyData: bodyData,
            baseURL: baseURL,
            bearerToken: bearerToken
        )
        do {
            return try decoder.decode(ResponseType.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    private func performRawRequest(
        path: String,
        method: String,
        bodyData: Data?,
        baseURL: String,
        bearerToken overrideToken: String? = nil,
        allowedStatuses: Set<Int>? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let normalized = Self.normalizeBaseURL(baseURL)
        guard !normalized.isEmpty, let url = URL(string: "\(normalized)\(path)") else {
            throw APIError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = overrideToken ?? self.bearerToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transportError("Connexion impossible au serveur (\(error.localizedDescription)).")
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transportError("Réponse réseau invalide.")
        }

        if let allowedStatuses, allowedStatuses.contains(http.statusCode) {
            return (data, http)
        }

        if http.statusCode == 401 {
            let errBody = try? decoder.decode(ErrorDetailBody.self, from: data)
            throw APIError.unauthorized(errBody?.detail ?? "Jeton Bearer requis ou expiré (401).")
        }

        if http.statusCode == 403 {
            let errBody = try? decoder.decode(ErrorDetailBody.self, from: data)
            throw APIError.forbidden(errBody?.detail ?? "Accès refusé par Tailscale SSO (403).")
        }

        if http.statusCode >= 400 {
            let errBody = try? decoder.decode(ErrorDetailBody.self, from: data)
            let detail = errBody?.detail ?? "Erreur serveur HTTP \(http.statusCode)."
            throw APIError.serverError(statusCode: http.statusCode, detail: detail)
        }

        return (data, http)
    }
}
