import Foundation
@preconcurrency import SwiftData

/// Persisted server profile storing connection metadata, appearance preference, and config hash.
/// Sensitive secrets (API tokens, pairing secrets) are stored separately in `KeychainStore` keyed by `id`.
@Model
public final class ServerProfileEntity {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var baseURLString: String
    public var isDefault: Bool
    public var usesTailscaleSSO: Bool
    public var lastConnectedAt: Date?
    public var configHash: String?
    public var appearancePreferenceRaw: String
    public var addedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        baseURLString: String,
        isDefault: Bool = false,
        usesTailscaleSSO: Bool = false,
        lastConnectedAt: Date? = nil,
        configHash: String? = nil,
        appearancePreferenceRaw: String = AppearanceMode.system.rawValue,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.baseURLString = baseURLString
        self.isDefault = isDefault
        self.usesTailscaleSSO = usesTailscaleSSO
        self.lastConnectedAt = lastConnectedAt
        self.configHash = configHash
        self.appearancePreferenceRaw = appearancePreferenceRaw
        self.addedAt = addedAt
    }

    public var appearancePreference: AppearanceMode {
        get { AppearanceMode(rawValue: appearancePreferenceRaw) ?? .system }
        set { appearancePreferenceRaw = newValue.rawValue }
    }

    public func toSavedServerProfile() -> SavedServerProfile {
        SavedServerProfile(
            id: id,
            name: name,
            baseURL: baseURLString,
            addedAt: addedAt,
            isDefault: isDefault,
            usesTailscaleSSO: usesTailscaleSSO,
            lastConnectedAt: lastConnectedAt,
            configHash: configHash,
            appearancePreference: appearancePreference
        )
    }
}

/// Offline SwiftData cache of recent incident alerts per server profile.
@Model
public final class CachedIncidentEntity {
    @Attribute(.unique) public var cacheKey: String
    public var id: String
    public var serverProfileID: UUID
    public var serviceId: String
    public var serviceName: String
    public var severity: String
    public var title: String
    public var message: String
    public var startedAt: String
    public var resolvedAt: String?
    public var acknowledged: Bool
    public var acknowledgedAt: String?
    public var cachedAt: Date

    public init(
        serverProfileID: UUID,
        incident: IncidentEvent,
        cachedAt: Date = Date()
    ) {
        self.cacheKey = "\(serverProfileID.uuidString.lowercased()):\(incident.id)"
        self.id = incident.id
        self.serverProfileID = serverProfileID
        self.serviceId = incident.serviceId
        self.serviceName = incident.serviceName
        self.severity = incident.severity
        self.title = incident.title
        self.message = incident.message
        self.startedAt = incident.startedAt
        self.resolvedAt = incident.resolvedAt
        self.acknowledged = incident.acknowledged
        self.acknowledgedAt = incident.acknowledgedAt
        self.cachedAt = cachedAt
    }

    public func toIncidentEvent() -> IncidentEvent {
        IncidentEvent(
            id: id,
            serviceId: serviceId,
            serviceName: serviceName,
            severity: severity,
            title: title,
            message: message,
            startedAt: startedAt,
            resolvedAt: resolvedAt,
            acknowledged: acknowledged,
            acknowledgedAt: acknowledgedAt
        )
    }
}

/// Offline SwiftData cache of monitored custom services per server profile.
@Model
public final class CachedCustomServiceEntity {
    @Attribute(.unique) public var cacheKey: String
    public var serverProfileID: UUID
    public var serviceId: String
    public var name: String
    public var serviceDescription: String
    public var category: String
    public var icon: String
    public var protocolRaw: String
    public var url: String?
    public var order: Int
    public var enabled: Bool
    public var status: String?
    public var latencyMs: Int?
    public var payloadJSON: Data?
    public var cachedAt: Date

    public init(
        serverProfileID: UUID,
        service: CustomServiceConfig,
        cachedAt: Date = Date()
    ) {
        self.cacheKey = "\(serverProfileID.uuidString.lowercased()):\(service.id)"
        self.serverProfileID = serverProfileID
        self.serviceId = service.id
        self.name = service.name
        self.serviceDescription = service.description
        self.category = service.category
        self.icon = service.icon
        self.protocolRaw = service.`protocol`.rawValue
        self.url = service.url
        self.order = service.order
        self.enabled = service.enabled
        self.status = service.status
        self.latencyMs = service.latencyMs
        self.payloadJSON = try? JSONEncoder().encode(service)
        self.cachedAt = cachedAt
    }

    public func toCustomServiceConfig() -> CustomServiceConfig {
        if let payloadJSON,
           let decoded = try? JSONDecoder().decode(CustomServiceConfig.self, from: payloadJSON) {
            return decoded
        }
        return CustomServiceConfig(
            id: serviceId,
            name: name,
            description: serviceDescription,
            category: category,
            icon: icon,
            protocol: CustomServiceProtocol(rawValue: protocolRaw) ?? .httpRest,
            url: url,
            order: order,
            enabled: enabled,
            status: status,
            latencyMs: latencyMs
        )
    }
}

/// Cross-platform `ModelContainer` factory supporting iOS, macOS, and tvOS cleanly.
public enum PVEModelContainerFactory {
    public static var schema: Schema {
        Schema([
            ServerProfileEntity.self,
            CachedIncidentEntity.self,
            CachedCustomServiceEntity.self,
        ])
    }

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [config])
        }

        #if os(tvOS)
        // tvOS local disk persistence uses Caches directory because Application Support is restricted.
        if let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let storeURL = cachesDir.appendingPathComponent("PVECenter-SwiftData.store")
            let config = ModelConfiguration(schema: schema, url: storeURL)
            return try ModelContainer(for: schema, configurations: [config])
        }
        #endif

        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [config])
    }

    public static func makeSharedContainer() -> ModelContainer {
        do {
            return try makeContainer(inMemory: false)
        } catch {
            // Safe fallback prevents launch crash if local store migration or sandbox fails.
            return (try? makeContainer(inMemory: true))
                ?? {
                    fatalError("Unable to initialize in-memory SwiftData container: \(error)")
                }()
        }
    }
}
