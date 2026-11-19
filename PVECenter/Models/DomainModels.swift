import Foundation

// MARK: - Auth & Navigation

public struct AuthUser: Codable, Sendable, Equatable {
    public let login: String
    public let name: String
    public let profilePic: String?
    public let authMode: String?

    public init(login: String, name: String, profilePic: String? = nil, authMode: String? = nil) {
        self.login = login
        self.name = name
        self.profilePic = profilePic
        self.authMode = authMode
    }
}

public enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case overview
    case proxmox
    case storage
    case services
    case operations
    case users

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: "Poste"
        case .proxmox: "Machines"
        case .storage: "Stockage"
        case .services: "Services"
        case .operations: "Activité"
        case .users: "Comptes"
        }
    }

    public var tvTitle: String {
        switch self {
        case .overview: "Poste"
        case .proxmox: "PVE"
        case .storage: "Disques"
        case .services: "Apps"
        case .operations: "Activité"
        case .users: "Comptes"
        }
    }

    public var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .proxmox: "server.rack"
        case .storage: "internaldrive.fill"
        case .services: "app.connected.to.app.below.fill"
        case .operations: "bolt.circle.fill"
        case .users: "person.2.fill"
        }
    }

    /// 5 onglets maximum en largeur compacte iPhone pour éviter le repli "Plus" (`tab-bars.md`).
    public static var compactTabs: [AppTab] {
        [.overview, .proxmox, .storage, .operations, .users]
    }
}

// MARK: - Proxmox & Storage

public struct StorageInfo: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let type: String
    public let active: Bool
    public let usedBytes: Int64
    public let totalBytes: Int64
    public let usedPct: Double
}

public struct NodeSummary: Codable, Sendable, Equatable {
    public let name: String
    public let cpuPct: Double
    public let cpuModel: String
    public let cpuThreads: Int
    public let loadavg: [String]
    public let memUsedBytes: Int64
    public let memTotalBytes: Int64
    public let memPct: Double
    public let swapUsedBytes: Int64
    public let swapTotalBytes: Int64
    public let rootfsUsedBytes: Int64
    public let rootfsTotalBytes: Int64
    public let uptimeSeconds: Int
    public let uptimeHuman: String
    public let pveVersion: String
    public let storages: [StorageInfo]
}

public struct PveCounts: Codable, Sendable, Equatable {
    public let total: Int
    public let running: Int
    public let stopped: Int
    public let lxc: Int
    public let qemu: Int
}

public enum PveResourceType: String, Codable, Sendable, Equatable {
    case lxc
    case qemu

    public var badgeLabel: String {
        switch self {
        case .lxc: "LXC"
        case .qemu: "VM"
        }
    }

    public var symbolName: String {
        switch self {
        case .lxc: "shippingbox.fill"
        case .qemu: "desktopcomputer"
        }
    }
}

public struct ClusterNode: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let status: String
    public let online: Bool
    public let cpuPct: Double
    public let cpus: Int
    public let memUsedBytes: Int64
    public let memTotalBytes: Int64
    public let memPct: Double
    public let uptimeSeconds: Int
    public let uptimeHuman: String

    public init(
        name: String,
        status: String = "online",
        online: Bool = true,
        cpuPct: Double = 0,
        cpus: Int = 0,
        memUsedBytes: Int64 = 0,
        memTotalBytes: Int64 = 0,
        memPct: Double = 0,
        uptimeSeconds: Int = 0,
        uptimeHuman: String = "—"
    ) {
        self.name = name
        self.status = status
        self.online = online
        self.cpuPct = cpuPct
        self.cpus = cpus
        self.memUsedBytes = memUsedBytes
        self.memTotalBytes = memTotalBytes
        self.memPct = memPct
        self.uptimeSeconds = uptimeSeconds
        self.uptimeHuman = uptimeHuman
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case status
        case online
        case cpuPct
        case cpus
        case memUsedBytes
        case memTotalBytes
        case memPct
        case uptimeSeconds
        case uptimeHuman
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        let decodedStatus = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        self.status = decodedStatus
        self.online = try container.decodeIfPresent(Bool.self, forKey: .online)
            ?? (decodedStatus.lowercased() == "online")
        self.cpuPct = try container.decodeIfPresent(Double.self, forKey: .cpuPct) ?? 0
        self.cpus = try container.decodeIfPresent(Int.self, forKey: .cpus) ?? 0
        self.memUsedBytes = try container.decodeIfPresent(Int64.self, forKey: .memUsedBytes) ?? 0
        self.memTotalBytes = try container.decodeIfPresent(Int64.self, forKey: .memTotalBytes) ?? 0
        self.memPct = try container.decodeIfPresent(Double.self, forKey: .memPct) ?? 0
        self.uptimeSeconds = try container.decodeIfPresent(Int.self, forKey: .uptimeSeconds) ?? 0
        self.uptimeHuman = try container.decodeIfPresent(String.self, forKey: .uptimeHuman) ?? "—"
    }
}

public struct PveResource: Codable, Sendable, Equatable, Identifiable {
    public var id: String {
        if let node, !node.isEmpty {
            return "\(node)-\(type.rawValue)-\(vmid)"
        }
        return "\(type.rawValue)-\(vmid)"
    }
    public let vmid: Int
    public let node: String?
    public var name: String
    public let type: PveResourceType
    public var status: String
    public var cpuPct: Double
    public var cpus: Int
    public var memUsedBytes: Int64
    public var memTotalBytes: Int64
    public var memPct: Double
    public var diskUsedBytes: Int64
    public var diskTotalBytes: Int64
    public var uptimeSeconds: Int
    public var uptimeHuman: String
    public var tags: [String]
    public let isSelf: Bool

    public var isRunning: Bool {
        status.lowercased() == "running"
    }

    public init(
        vmid: Int,
        node: String? = nil,
        name: String,
        type: PveResourceType,
        status: String,
        cpuPct: Double,
        cpus: Int,
        memUsedBytes: Int64,
        memTotalBytes: Int64,
        memPct: Double,
        diskUsedBytes: Int64,
        diskTotalBytes: Int64,
        uptimeSeconds: Int,
        uptimeHuman: String,
        tags: [String] = [],
        isSelf: Bool = false
    ) {
        self.vmid = vmid
        self.node = node
        self.name = name
        self.type = type
        self.status = status
        self.cpuPct = cpuPct
        self.cpus = cpus
        self.memUsedBytes = memUsedBytes
        self.memTotalBytes = memTotalBytes
        self.memPct = memPct
        self.diskUsedBytes = diskUsedBytes
        self.diskTotalBytes = diskTotalBytes
        self.uptimeSeconds = uptimeSeconds
        self.uptimeHuman = uptimeHuman
        self.tags = tags
        self.isSelf = isSelf
    }

    private enum CodingKeys: String, CodingKey {
        case vmid
        case node
        case name
        case type
        case status
        case cpuPct
        case cpus
        case memUsedBytes
        case memTotalBytes
        case memPct
        case diskUsedBytes
        case diskTotalBytes
        case uptimeSeconds
        case uptimeHuman
        case tags
        case isSelf
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.vmid = try container.decode(Int.self, forKey: .vmid)
        let rawNode = try container.decodeIfPresent(String.self, forKey: .node)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.node = (rawNode?.isEmpty == false) ? rawNode : nil
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "guest-\(self.vmid)"
        self.type = try container.decode(PveResourceType.self, forKey: .type)
        self.status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        self.cpuPct = try container.decodeIfPresent(Double.self, forKey: .cpuPct) ?? 0
        self.cpus = try container.decodeIfPresent(Int.self, forKey: .cpus) ?? 1
        self.memUsedBytes = try container.decodeIfPresent(Int64.self, forKey: .memUsedBytes) ?? 0
        self.memTotalBytes = try container.decodeIfPresent(Int64.self, forKey: .memTotalBytes) ?? 0
        self.memPct = try container.decodeIfPresent(Double.self, forKey: .memPct) ?? 0
        self.diskUsedBytes = try container.decodeIfPresent(Int64.self, forKey: .diskUsedBytes) ?? 0
        self.diskTotalBytes = try container.decodeIfPresent(Int64.self, forKey: .diskTotalBytes) ?? 0
        self.uptimeSeconds = try container.decodeIfPresent(Int.self, forKey: .uptimeSeconds) ?? 0
        self.uptimeHuman = try container.decodeIfPresent(String.self, forKey: .uptimeHuman) ?? "—"
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.isSelf = try container.decodeIfPresent(Bool.self, forKey: .isSelf) ?? false
    }
}

public enum PveAction: String, CaseIterable, Codable, Sendable, Identifiable {
    case start
    case shutdown
    case reboot
    case stop

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .start: "Démarrer"
        case .shutdown: "Éteindre (ACPI)"
        case .reboot: "Redémarrer"
        case .stop: "Forcer l'arrêt"
        }
    }

    public var shortLabel: String {
        switch self {
        case .start: "Démarrer"
        case .shutdown: "Éteindre"
        case .reboot: "Reboot"
        case .stop: "Stop"
        }
    }

    public var systemImage: String {
        switch self {
        case .start: "play.fill"
        case .shutdown: "power"
        case .reboot: "arrow.clockwise"
        case .stop: "stop.fill"
        }
    }

    public var isDestructive: Bool {
        self == .stop || self == .shutdown
    }

    public var warningMessage: String {
        switch self {
        case .start:
            return "Cette ressource va être démarrée sur le nœud Proxmox."
        case .shutdown:
            return "Un arrêt propre (ACPI) va être envoyé à cette machine."
        case .reboot:
            return "La machine va redémarrer immédiatement et interrompre brièvement ses services."
        case .stop:
            return "Attention : l'arrêt forcé coupe l'alimentation instantanément (risque de perte de données non écrites)."
        }
    }
}

public struct MergerfsPoolInfo: Codable, Sendable, Equatable {
    public let name: String
    public let mount: String
    public let fstype: String
    public let policy: String
    public let drivesCount: Int
    public let available: Bool
    public let totalBytes: Int64
    public let usedBytes: Int64
    public let availBytes: Int64
    public let usedPct: Double
}

public struct PhysicalDriveInfo: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(devpath)-\(mount)" }
    public let mount: String
    public let label: String
    public let wwn: String
    public let devpath: String
    public let model: String
    public let vendor: String
    public let serial: String
    public let type: String
    public let rpm: String
    public let health: String
    public let sizeBytes: Int64
    public let totalBytes: Int64
    public let usedBytes: Int64
    public let availBytes: Int64
    public let usedPct: Double

    public var isHealthy: Bool {
        health.uppercased() == "PASSED" || health.uppercased() == "OK"
    }
}

public struct SystemSsdInfo: Codable, Sendable, Equatable {
    public let devpath: String
    public let model: String
    public let serial: String
    public let health: String
    public let sizeBytes: Int64
}

public struct ExternalStorageOverview: Codable, Sendable, Equatable {
    public let pool: MergerfsPoolInfo
    public let drives: [PhysicalDriveInfo]
    public let systemSsd: SystemSsdInfo?
}

public struct PveOverview: Codable, Sendable, Equatable {
    public let online: Bool
    public let node: NodeSummary
    public let counts: PveCounts
    public let resources: [PveResource]
    public let externalStorage: ExternalStorageOverview?
    public let selectedNode: String?
    public let failoverActive: Bool?
    public let clusterNodes: [ClusterNode]?

    public init(
        online: Bool,
        node: NodeSummary,
        counts: PveCounts,
        resources: [PveResource],
        externalStorage: ExternalStorageOverview? = nil,
        selectedNode: String? = nil,
        failoverActive: Bool? = nil,
        clusterNodes: [ClusterNode]? = nil
    ) {
        self.online = online
        self.node = node
        self.counts = counts
        self.resources = resources
        self.externalStorage = externalStorage
        self.selectedNode = selectedNode
        self.failoverActive = failoverActive
        self.clusterNodes = clusterNodes
    }

    private enum CodingKeys: String, CodingKey {
        case online
        case node
        case counts
        case resources
        case externalStorage
        case selectedNode
        case failoverActive
        case clusterNodes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.online = try container.decodeIfPresent(Bool.self, forKey: .online) ?? false
        self.node = try container.decode(NodeSummary.self, forKey: .node)
        self.counts = try container.decode(PveCounts.self, forKey: .counts)
        self.resources = try container.decodeIfPresent([PveResource].self, forKey: .resources) ?? []
        self.externalStorage = try container.decodeIfPresent(ExternalStorageOverview.self, forKey: .externalStorage)
        let rawSelected = try container.decodeIfPresent(String.self, forKey: .selectedNode)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.selectedNode = (rawSelected?.isEmpty == false) ? rawSelected : nil
        self.failoverActive = try container.decodeIfPresent(Bool.self, forKey: .failoverActive)
        self.clusterNodes = try container.decodeIfPresent([ClusterNode].self, forKey: .clusterNodes)
    }
}

// MARK: - Services & Widgets

public struct ServiceItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let url: String
    public let pingUrl: String?
    public let icon: String
    public let widget: String?
    public let online: Bool
    public let latencyMs: Double?
    public let statusCode: Int?
    public let protocolType: String?
    public let metrics: [String: JSONValue]?
    public let isCustom: Bool?

    public init(
        id: String,
        name: String,
        description: String,
        url: String,
        pingUrl: String? = nil,
        icon: String,
        widget: String? = nil,
        online: Bool,
        latencyMs: Double? = nil,
        statusCode: Int? = nil,
        protocolType: String? = nil,
        metrics: [String: JSONValue]? = nil,
        isCustom: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.url = url
        self.pingUrl = pingUrl
        self.icon = icon
        self.widget = widget
        self.online = online
        self.latencyMs = latencyMs
        self.statusCode = statusCode
        self.protocolType = protocolType
        self.metrics = metrics
        self.isCustom = isCustom
    }
}

public struct ServiceCategory: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let services: [ServiceItem]
}

public struct ServicesResponse: Codable, Sendable, Equatable {
    public let categories: [ServiceCategory]
    public let customServices: [CustomServiceConfig]?

    public init(categories: [ServiceCategory], customServices: [CustomServiceConfig]? = nil) {
        self.categories = categories
        self.customServices = customServices
    }
}

public struct CategoryServiceUpdateRequest: Codable, Sendable, Equatable {
    public var name: String?
    public var description: String?
    public var url: String?
    public var pingUrl: String?
    public var icon: String?
    public var widget: String?
    public var category: String?

    public init(
        name: String? = nil,
        description: String? = nil,
        url: String? = nil,
        pingUrl: String? = nil,
        icon: String? = nil,
        widget: String? = nil,
        category: String? = nil
    ) {
        self.name = name
        self.description = description
        self.url = url
        self.pingUrl = pingUrl
        self.icon = icon
        self.widget = widget
        self.category = category
    }
}

public struct CategoryServiceMoveRequest: Codable, Sendable, Equatable {
    public let direction: String

    public init(direction: String) {
        self.direction = direction
    }
}

public struct CategoryServiceTestRequest: Codable, Sendable, Equatable {
    public var url: String?
    public var pingUrl: String?

    public init(url: String? = nil, pingUrl: String? = nil) {
        self.url = url
        self.pingUrl = pingUrl
    }
}

public struct CategoryServiceTestResponse: Codable, Sendable, Equatable {
    public let ok: Bool
    public let serviceId: String
    public let online: Bool
    public let statusCode: Int?
    public let latencyMs: Int?
    public let message: String

    public init(
        ok: Bool,
        serviceId: String,
        online: Bool,
        statusCode: Int? = nil,
        latencyMs: Int? = nil,
        message: String
    ) {
        self.ok = ok
        self.serviceId = serviceId
        self.online = online
        self.statusCode = statusCode
        self.latencyMs = latencyMs
        self.message = message
    }
}

public struct CategoryServiceMutationResponse: Codable, Sendable, Equatable {
    public let ok: Bool
    public let category: String
    public let service: ServiceItem

    public init(ok: Bool, category: String, service: ServiceItem) {
        self.ok = ok
        self.category = category
        self.service = service
    }
}

public struct JellyfinStream: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(user)-\(title)-\(device)" }
    public let user: String
    public let title: String
    public let device: String
    public let playMethod: String
    public let isPaused: Bool
}

public struct JellyfinWidget: Codable, Sendable, Equatable {
    public let status: String
    public let activeStreamsCount: Int?
    public let activeStreams: [JellyfinStream]?
    public let moviesCount: Int?
    public let seriesCount: Int?
    public let episodesCount: Int?
}

public struct PlexWidget: Codable, Sendable, Equatable {
    public let status: String
    public let activeStreamsCount: Int?
    public let librariesCount: Int?
    public let libraries: [String]?
    public let version: String?
}

public struct UpcomingItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(title)-\(date)" }
    public let title: String
    public let date: String
}

public struct RadarrWidget: Codable, Sendable, Equatable {
    public let status: String
    public let moviesTotal: Int?
    public let moviesDownloaded: Int?
    public let moviesMissing: Int?
    public let queueCount: Int?
    public let upcoming: [UpcomingItem]?
}

public struct SonarrWidget: Codable, Sendable, Equatable {
    public let status: String
    public let seriesTotal: Int?
    public let episodesDownloaded: Int?
    public let queueCount: Int?
    public let upcoming: [UpcomingItem]?
}

public struct ProwlarrWidget: Codable, Sendable, Equatable {
    public let status: String
    public let indexersEnabled: Int?
    public let indexersTotal: Int?
    public let queries: Int?
    public let grabs: Int?
}

public struct QbittorrentWidget: Codable, Sendable, Equatable {
    public let status: String
    public let dlSpeedBytes: Int64?
    public let upSpeedBytes: Int64?
    public let dlTotalBytes: Int64?
    public let upTotalBytes: Int64?
    public let downloadingCount: Int?
    public let seedingCount: Int?
    public let torrentsTotal: Int?
}

public struct WidgetsMap: Codable, Sendable, Equatable {
    public let jellyfin: JellyfinWidget?
    public let plex: PlexWidget?
    public let radarr: RadarrWidget?
    public let sonarr: SonarrWidget?
    public let prowlarr: ProwlarrWidget?
    public let qbittorrent: QbittorrentWidget?
}

// MARK: - Users (Jellyfin <-> Jellyseerr)

public struct JellyfinLibrary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
}

public struct UnifiedUser: Codable, Sendable, Equatable, Identifiable {
    public var id: String { jellyfinId }
    public let jellyfinId: String
    public var name: String
    public var isAdmin: Bool
    public let isProtected: Bool?
    public var isDisabled: Bool
    public var enableAllFolders: Bool
    public var enabledFolders: [String]
    public var enableDownloading: Bool
    public var maxActiveSessions: Int
    public var lastActivity: String?
    public var inJellyseerr: Bool
    public var jellyseerrId: Int?
    public var requestCount: Int
    public var autoApprove: Bool
}

public struct UsersCounts: Codable, Sendable, Equatable {
    public let totalJellyfin: Int
    public let syncedJellyseerr: Int
    public let unsyncedCount: Int
    public let disabledCount: Int
}

public struct UsersOverview: Codable, Sendable, Equatable {
    public let counts: UsersCounts
    public let libraries: [JellyfinLibrary]
    public let users: [UnifiedUser]
}

public struct CreateUserRequest: Codable, Sendable {
    public let username: String
    public let password: String
    public let syncJellyseerr: Bool
    public let autoApprove: Bool
    public let enableAllFolders: Bool
    public let enabledFolders: [String]
    public let enableDownloading: Bool
    public let maxActiveSessions: Int
}

public struct UpdateUserRequest: Codable, Sendable {
    public var isDisabled: Bool?
    public var isAdmin: Bool?
    public var enableAllFolders: Bool?
    public var enabledFolders: [String]?
    public var enableDownloading: Bool?
    public var maxActiveSessions: Int?
    public var autoApprove: Bool?
}

public struct ResetPasswordRequest: Codable, Sendable {
    public let newPassword: String
}

public struct SyncUsersRequest: Codable, Sendable {
    public let jellyfinUserIds: [String]?
    public let autoApprove: Bool
}

public struct SyncUsersResponse: Codable, Sendable {
    public let ok: Bool
    public let importedCount: Int
}

public struct ActionOKResponse: Codable, Sendable {
    public let ok: Bool
    public let message: String?
    public let altSpeedEnabled: Bool?
}

// MARK: - Operations & Alerts

public struct PveTaskItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(upid)-\(starttime)" }
    public let upid: String
    public let type: String
    public let vmid: String
    public let user: String
    public let status: String
    public let starttime: Int
    public let endtime: Int
    public let durationSec: Int?

    public var isSuccess: Bool {
        status.uppercased() == "OK"
    }
}

public struct SeerrRequestItem: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public var status: Int
    public let mediaType: String
    public let title: String
    public let requestedBy: String
    public let createdAt: String
    public let mediaStatus: Int

    public var isPending: Bool { status == 1 }

    public var statusLabel: String {
        switch status {
        case 1: "En attente"
        case 2: "Approuvée"
        case 3: "Refusée"
        default: "Traitée"
        }
    }
}

public struct QbitTorrentItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String { hash }
    public let hash: String
    public let name: String
    public var state: String
    public let progressPct: Double
    public let dlspeed: Int64
    public let upspeed: Int64
    public let size: Int64
    public let eta: Int

    public var isPaused: Bool {
        state.lowercased().contains("paused") || state.lowercased().contains("stopped")
    }
}

public struct QbitControlOverview: Codable, Sendable, Equatable {
    public let available: Bool
    public var altSpeedEnabled: Bool
    public var torrents: [QbitTorrentItem]
}

public struct OpsOverview: Codable, Sendable, Equatable {
    public let pveTasks: [PveTaskItem]
    public let seerrRequests: [SeerrRequestItem]
    public let qbitControl: QbitControlOverview
}

public struct SmartAlert: Identifiable, Equatable, Sendable {
    public enum Severity: String, Sendable {
        case critical
        case warning
        case info
    }

    public let id: String
    public let severity: Severity
    public let title: String
    public let subtitle: String
    public let targetTab: AppTab
}

public struct ToastMessage: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let isError: Bool
    public let text: String
}

// MARK: - Multi-Server & Setup

public enum AppearanceMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "Système"
        case .light: "Clair"
        case .dark: "Sombre"
        }
    }

    public var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }
}

public enum AccentTheme: String, CaseIterable, Codable, Sendable, Identifiable {
    case cyan
    case cider
    case indigo
    case emerald
    case amber
    case purple

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cyan: "Cyan PVE"
        case .cider: "Cider Ruby"
        case .indigo: "Indigo Studio"
        case .emerald: "Émeraude"
        case .amber: "Ambre Proxmox"
        case .purple: "Améthyste"
        }
    }
}

public struct SavedServerProfile: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var baseURL: String
    public var addedAt: Date
    public var isDefault: Bool
    public var usesTailscaleSSO: Bool
    public var lastConnectedAt: Date?
    public var configHash: String?
    public var appearancePreference: AppearanceMode

    public init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        addedAt: Date = Date(),
        isDefault: Bool = false,
        usesTailscaleSSO: Bool = false,
        lastConnectedAt: Date? = nil,
        configHash: String? = nil,
        appearancePreference: AppearanceMode = .system
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.addedAt = addedAt
        self.isDefault = isDefault
        self.usesTailscaleSSO = usesTailscaleSSO
        self.lastConnectedAt = lastConnectedAt
        self.configHash = configHash
        self.appearancePreference = appearancePreference
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case baseURL
        case addedAt
        case isDefault
        case usesTailscaleSSO
        case lastConnectedAt
        case configHash
        case appearancePreference
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.baseURL = try container.decode(String.self, forKey: .baseURL)
        self.addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        self.isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        self.usesTailscaleSSO = try container.decodeIfPresent(Bool.self, forKey: .usesTailscaleSSO) ?? false
        self.lastConnectedAt = try container.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
        self.configHash = try container.decodeIfPresent(String.self, forKey: .configHash)
        self.appearancePreference = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearancePreference) ?? .system
    }
}

public struct SetupEnvConfig: Codable, Sendable, Equatable {
    public var devAuthBypass: Bool
    public var allowedTailscaleUsers: String
    public var protectedOwnerUsername: String
    public var pveHost: String
    public var pveNode: String
    public var pveTokenId: String
    public var pveTokenSecretSet: Bool
    public var pveVerifySsl: Bool
    public var panelSelfVmid: Int
    public var jellyfinUrl: String
    public var jellyfinApiKeySet: Bool
    public var jellyseerrUrl: String
    public var jellyseerrApiKeySet: Bool
    public var plexUrl: String
    public var plexTokenSet: Bool
    public var radarrUrl: String
    public var radarrApiKeySet: Bool
    public var sonarrUrl: String
    public var sonarrApiKeySet: Bool
    public var prowlarrUrl: String
    public var prowlarrApiKeySet: Bool
    public var qbitUrl: String
    public var qbitUsername: String
    public var qbitPasswordSet: Bool

    public init(
        devAuthBypass: Bool = false,
        allowedTailscaleUsers: String = "",
        protectedOwnerUsername: String = "admin",
        pveHost: String = "",
        pveNode: String = "pve",
        pveTokenId: String = "",
        pveTokenSecretSet: Bool = false,
        pveVerifySsl: Bool = false,
        panelSelfVmid: Int = 116,
        jellyfinUrl: String = "",
        jellyfinApiKeySet: Bool = false,
        jellyseerrUrl: String = "",
        jellyseerrApiKeySet: Bool = false,
        plexUrl: String = "",
        plexTokenSet: Bool = false,
        radarrUrl: String = "",
        radarrApiKeySet: Bool = false,
        sonarrUrl: String = "",
        sonarrApiKeySet: Bool = false,
        prowlarrUrl: String = "",
        prowlarrApiKeySet: Bool = false,
        qbitUrl: String = "",
        qbitUsername: String = "",
        qbitPasswordSet: Bool = false
    ) {
        self.devAuthBypass = devAuthBypass
        self.allowedTailscaleUsers = allowedTailscaleUsers
        self.protectedOwnerUsername = protectedOwnerUsername
        self.pveHost = pveHost
        self.pveNode = pveNode
        self.pveTokenId = pveTokenId
        self.pveTokenSecretSet = pveTokenSecretSet
        self.pveVerifySsl = pveVerifySsl
        self.panelSelfVmid = panelSelfVmid
        self.jellyfinUrl = jellyfinUrl
        self.jellyfinApiKeySet = jellyfinApiKeySet
        self.jellyseerrUrl = jellyseerrUrl
        self.jellyseerrApiKeySet = jellyseerrApiKeySet
        self.plexUrl = plexUrl
        self.plexTokenSet = plexTokenSet
        self.radarrUrl = radarrUrl
        self.radarrApiKeySet = radarrApiKeySet
        self.sonarrUrl = sonarrUrl
        self.sonarrApiKeySet = sonarrApiKeySet
        self.prowlarrUrl = prowlarrUrl
        self.prowlarrApiKeySet = prowlarrApiKeySet
        self.qbitUrl = qbitUrl
        self.qbitUsername = qbitUsername
        self.qbitPasswordSet = qbitPasswordSet
    }
}

public struct SetupServiceConfig: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var description: String?
    public var url: String
    public var pingUrl: String?
    public var icon: String?
    public var widget: String?

    public init(
        id: String,
        name: String,
        description: String? = nil,
        url: String,
        pingUrl: String? = nil,
        icon: String? = nil,
        widget: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.url = url
        self.pingUrl = pingUrl
        self.icon = icon
        self.widget = widget
    }
}

public struct SetupCategoryConfig: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var services: [SetupServiceConfig]

    public init(name: String, services: [SetupServiceConfig]) {
        self.name = name
        self.services = services
    }
}

public struct StorageMountConfig: Codable, Sendable, Equatable, Identifiable {
    public var id: String { subpath }
    public var mount: String?
    public var subpath: String
    public var wwn: String?
    public var label: String?

    public init(mount: String? = nil, subpath: String, wwn: String? = nil, label: String? = nil) {
        self.mount = mount
        self.subpath = subpath
        self.wwn = wwn
        self.label = label
    }
}

public struct SetupStatusResponse: Codable, Sendable, Equatable {
    public let isConfigured: Bool
    public let tailscaleUrl: String
    public let pairingDeepLink: String
    public let env: SetupEnvConfig
    public let categories: [SetupCategoryConfig]?
    public let storageMounts: [StorageMountConfig]?

    public init(
        isConfigured: Bool,
        tailscaleUrl: String,
        pairingDeepLink: String,
        env: SetupEnvConfig,
        categories: [SetupCategoryConfig]? = nil,
        storageMounts: [StorageMountConfig]? = nil
    ) {
        self.isConfigured = isConfigured
        self.tailscaleUrl = tailscaleUrl
        self.pairingDeepLink = pairingDeepLink
        self.env = env
        self.categories = categories
        self.storageMounts = storageMounts
    }
}

public struct ServiceTestRequest: Codable, Sendable {
    public let service: String
    public let url: String
    public let node: String?
    public let tokenId: String?
    public let secret: String?
    public let username: String?
    public let verifySsl: Bool?

    public init(
        service: String,
        url: String,
        node: String? = nil,
        tokenId: String? = nil,
        secret: String? = nil,
        username: String? = nil,
        verifySsl: Bool? = nil
    ) {
        self.service = service
        self.url = url
        self.node = node
        self.tokenId = tokenId
        self.secret = secret
        self.username = username
        self.verifySsl = verifySsl
    }
}

public struct ServiceTestResponse: Codable, Sendable, Equatable {
    public let ok: Bool
    public let service: String
    public let message: String
    public let latencyMs: Double?

    public init(ok: Bool, service: String, message: String, latencyMs: Double? = nil) {
        self.ok = ok
        self.service = service
        self.message = message
        self.latencyMs = latencyMs
    }
}

public struct SetupEnvUpdate: Codable, Sendable {
    public var devAuthBypass: Bool?
    public var allowedTailscaleUsers: String?
    public var protectedOwnerUsername: String?
    public var pveHost: String?
    public var pveNode: String?
    public var pveTokenId: String?
    public var pveTokenSecret: String?
    public var pveVerifySsl: Bool?
    public var panelSelfVmid: Int?
    public var jellyfinUrl: String?
    public var jellyfinApiKey: String?
    public var jellyseerrUrl: String?
    public var jellyseerrApiKey: String?
    public var plexUrl: String?
    public var plexToken: String?
    public var radarrUrl: String?
    public var radarrApiKey: String?
    public var sonarrUrl: String?
    public var sonarrApiKey: String?
    public var prowlarrUrl: String?
    public var prowlarrApiKey: String?
    public var qbitUrl: String?
    public var qbitUsername: String?
    public var qbitPassword: String?

    public init(
        devAuthBypass: Bool? = nil,
        allowedTailscaleUsers: String? = nil,
        protectedOwnerUsername: String? = nil,
        pveHost: String? = nil,
        pveNode: String? = nil,
        pveTokenId: String? = nil,
        pveTokenSecret: String? = nil,
        pveVerifySsl: Bool? = nil,
        panelSelfVmid: Int? = nil,
        jellyfinUrl: String? = nil,
        jellyfinApiKey: String? = nil,
        jellyseerrUrl: String? = nil,
        jellyseerrApiKey: String? = nil,
        plexUrl: String? = nil,
        plexToken: String? = nil,
        radarrUrl: String? = nil,
        radarrApiKey: String? = nil,
        sonarrUrl: String? = nil,
        sonarrApiKey: String? = nil,
        prowlarrUrl: String? = nil,
        prowlarrApiKey: String? = nil,
        qbitUrl: String? = nil,
        qbitUsername: String? = nil,
        qbitPassword: String? = nil
    ) {
        self.devAuthBypass = devAuthBypass
        self.allowedTailscaleUsers = allowedTailscaleUsers
        self.protectedOwnerUsername = protectedOwnerUsername
        self.pveHost = pveHost
        self.pveNode = pveNode
        self.pveTokenId = pveTokenId
        self.pveTokenSecret = pveTokenSecret
        self.pveVerifySsl = pveVerifySsl
        self.panelSelfVmid = panelSelfVmid
        self.jellyfinUrl = jellyfinUrl
        self.jellyfinApiKey = jellyfinApiKey
        self.jellyseerrUrl = jellyseerrUrl
        self.jellyseerrApiKey = jellyseerrApiKey
        self.plexUrl = plexUrl
        self.plexToken = plexToken
        self.radarrUrl = radarrUrl
        self.radarrApiKey = radarrApiKey
        self.sonarrUrl = sonarrUrl
        self.sonarrApiKey = sonarrApiKey
        self.prowlarrUrl = prowlarrUrl
        self.prowlarrApiKey = prowlarrApiKey
        self.qbitUrl = qbitUrl
        self.qbitUsername = qbitUsername
        self.qbitPassword = qbitPassword
    }
}

public struct SetupConfigUpdateRequest: Codable, Sendable {
    public var env: SetupEnvUpdate?
    public var categories: [SetupCategoryConfig]?
    public var storageMounts: [StorageMountConfig]?

    public init(
        env: SetupEnvUpdate? = nil,
        categories: [SetupCategoryConfig]? = nil,
        storageMounts: [StorageMountConfig]? = nil
    ) {
        self.env = env
        self.categories = categories
        self.storageMounts = storageMounts
    }
}

public struct SetupConfigUpdateResponse: Codable, Sendable, Equatable {
    public let ok: Bool
    public let isConfigured: Bool
    public let message: String

    public init(ok: Bool, isConfigured: Bool, message: String) {
        self.ok = ok
        self.isConfigured = isConfigured
        self.message = message
    }
}

// MARK: - Dynamic JSON Helper

/// Type-safe `Sendable` JSON value used for dynamic service metrics and real-time event payloads.
public enum JSONValue: Codable, Sendable, Equatable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    public var stringValue: String? {
        switch self {
        case .string(let v): v
        case .int(let v): String(v)
        case .double(let v): String(v)
        case .bool(let v): v ? "true" : "false"
        default: nil
        }
    }

    public var intValue: Int? {
        switch self {
        case .int(let v): v
        case .double(let v): Int(v)
        case .string(let v): Int(v)
        default: nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let v): v
        case .int(let v): Double(v)
        case .string(let v): Double(v)
        default: nil
        }
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let v): v
        case .int(let v): v != 0
        case .string(let v):
            switch v.lowercased() {
            case "true", "1", "yes": true
            case "false", "0", "no": false
            default: nil
            }
        default: nil
        }
    }

    public var displayString: String {
        switch self {
        case .string(let v): v
        case .int(let v): String(v)
        case .double(let v): String(format: "%.2f", v)
        case .bool(let v): v ? "Oui" : "Non"
        case .array(let arr): "[\(arr.count)]"
        case .object(let obj): "{\(obj.count)}"
        case .null: "—"
        }
    }
}

private enum FlexibleJSONDecode {
    static func stringID<K: CodingKey>(from container: KeyedDecodingContainer<K>, key: K) throws -> String {
        if let value = try? container.decode(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? container.decode(Int64.self, forKey: key) {
            return String(value)
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Expected String or Integer identifier."
        )
    }
}

// MARK: - Discovery (Bonjour & LAN)

public struct DiscoveryServerItem: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public var name: String
    public var serviceType: String
    public var host: String
    public var port: Int
    public var isHttps: Bool
    public var publicUrl: String?
    public var version: String?
    public var txt: [String: String]
    public var suggestedProtocol: CustomServiceProtocol?
    public var isLocalBonjour: Bool

    public init(
        id: String,
        name: String,
        serviceType: String,
        host: String,
        port: Int,
        isHttps: Bool = false,
        publicUrl: String? = nil,
        version: String? = nil,
        txt: [String: String] = [:],
        suggestedProtocol: CustomServiceProtocol? = nil,
        isLocalBonjour: Bool = false
    ) {
        self.id = id
        self.name = name
        self.serviceType = serviceType
        self.host = host
        self.port = port
        self.isHttps = isHttps
        self.publicUrl = publicUrl
        self.version = version
        self.txt = txt
        self.suggestedProtocol = suggestedProtocol
        self.isLocalBonjour = isLocalBonjour
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case serviceType
        case host
        case port
        case isHttps
        case https
        case publicUrl
        case version
        case txt
        case suggestedProtocol
        case isLocalBonjour
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        self.id = decodedID
        self.name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Serveur"
        self.serviceType = (try? container.decodeIfPresent(String.self, forKey: .serviceType)) ?? "_http._tcp"
        self.host = (try? container.decodeIfPresent(String.self, forKey: .host)) ?? ""
        self.port = (try? container.decodeIfPresent(Int.self, forKey: .port)) ?? 80
        let txtMap = (try? container.decodeIfPresent([String: String].self, forKey: .txt)) ?? [:]
        self.txt = txtMap

        let httpsFromKey = try? container.decodeIfPresent(Bool.self, forKey: .isHttps)
        let httpsFromShortKey = try? container.decodeIfPresent(Bool.self, forKey: .https)
        let txtHttps = (txtMap["https"] ?? "").lowercased()
        self.isHttps = httpsFromKey ?? httpsFromShortKey ?? (txtHttps == "true" || txtHttps == "1" || port == 443)

        let rawPublicURL = (try? container.decodeIfPresent(String.self, forKey: .publicUrl))
            ?? txtMap["publicUrl"]
            ?? txtMap["public_url"]
        self.publicUrl = (rawPublicURL?.isEmpty == false) ? rawPublicURL : nil
        self.version = (try? container.decodeIfPresent(String.self, forKey: .version)) ?? txtMap["version"]
        self.suggestedProtocol = try? container.decodeIfPresent(CustomServiceProtocol.self, forKey: .suggestedProtocol)
        self.isLocalBonjour = (try? container.decodeIfPresent(Bool.self, forKey: .isLocalBonjour)) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(serviceType, forKey: .serviceType)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(isHttps, forKey: .isHttps)
        try container.encodeIfPresent(publicUrl, forKey: .publicUrl)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encode(txt, forKey: .txt)
        try container.encodeIfPresent(suggestedProtocol, forKey: .suggestedProtocol)
        try container.encode(isLocalBonjour, forKey: .isLocalBonjour)
    }

    public var isPVECenterServer: Bool {
        serviceType.lowercased().contains("_pvecenter._tcp")
    }

    public var isPairingReceiver: Bool {
        serviceType.lowercased().contains("_pvepair._tcp")
    }

    public var resolvedBaseUrl: String {
        if let publicUrl, !publicUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return publicUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        }
        guard !host.isEmpty else { return "" }
        let formattedHost = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        let scheme = isHttps ? "https" : "http"
        if (isHttps && port == 443) || (!isHttps && port == 80) {
            return "\(scheme)://\(formattedHost)"
        }
        return "\(scheme)://\(formattedHost):\(port)"
    }
}

public struct LANDiscoveryResponse: Codable, Sendable, Equatable {
    public let services: [DiscoveryServerItem]

    public init(services: [DiscoveryServerItem]) {
        self.services = services
    }

    private enum CodingKeys: String, CodingKey {
        case services
        case items
    }

    public init(from decoder: Decoder) throws {
        if let singleArray = try? [DiscoveryServerItem](from: decoder) {
            self.services = singleArray
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try? container.decodeIfPresent([DiscoveryServerItem].self, forKey: .services) {
            self.services = list
        } else if let list = try? container.decodeIfPresent([DiscoveryServerItem].self, forKey: .items) {
            self.services = list
        } else {
            self.services = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(services, forKey: .services)
    }
}

public struct DiscoveryQRResponse: Codable, Sendable, Equatable {
    public let deepLink: String
    public let onboardingLink: String?
    public let publicUrl: String?
    public let svgDataUrl: String?
    public let svgDataUrlOrText: String?
    public let serverId: String?
    public let serverName: String?
    public let mdnsServiceType: String?
    public let lanIp: String?
    public let port: Int?

    public var qrPayloadText: String {
        svgDataUrlOrText ?? svgDataUrl ?? deepLink
    }

    public init(
        deepLink: String,
        onboardingLink: String? = nil,
        publicUrl: String? = nil,
        svgDataUrl: String? = nil,
        svgDataUrlOrText: String? = nil,
        serverId: String? = nil,
        serverName: String? = nil,
        mdnsServiceType: String? = nil,
        lanIp: String? = nil,
        port: Int? = nil
    ) {
        self.deepLink = deepLink
        self.onboardingLink = onboardingLink
        self.publicUrl = publicUrl
        self.svgDataUrl = svgDataUrl
        self.svgDataUrlOrText = svgDataUrlOrText ?? svgDataUrl
        self.serverId = serverId
        self.serverName = serverName
        self.mdnsServiceType = mdnsServiceType
        self.lanIp = lanIp
        self.port = port
    }
}

// MARK: - Custom Services & Alert Policies

public enum CustomServiceProtocol: String, CaseIterable, Codable, Sendable, Identifiable {
    case httpRest = "http_rest"
    case tcpPort = "tcp_port"
    case icmpPing = "icmp_ping"
    case jsonMetrics = "json_metrics"
    case webhookIngest = "webhook_ingest"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .httpRest: "HTTP / REST"
        case .tcpPort: "Port TCP"
        case .icmpPing: "Ping ICMP"
        case .jsonMetrics: "Métriques JSON"
        case .webhookIngest: "Webhook entrant"
        }
    }

    public var systemImage: String {
        switch self {
        case .httpRest: "globe"
        case .tcpPort: "network"
        case .icmpPing: "waveform.path.ecg"
        case .jsonMetrics: "chart.bar.doc.horizontal"
        case .webhookIngest: "tray.and.arrow.down.fill"
        }
    }
}

public enum CustomServiceAuthType: String, CaseIterable, Codable, Sendable, Identifiable {
    case none = "none"
    case bearer = "bearer"
    case basic = "basic"
    case header = "header"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: "Aucune"
        case .bearer: "Bearer Token"
        case .basic: "Basic Auth"
        case .header: "En-tête personnalisé"
        }
    }
}

public struct AlertPolicyConfig: Codable, Sendable, Equatable, Hashable {
    public var enabled: Bool
    public var consecutiveFailures: Int
    public var cooldownSeconds: Int

    public init(
        enabled: Bool = true,
        consecutiveFailures: Int = 3,
        cooldownSeconds: Int = 300
    ) {
        self.enabled = enabled
        self.consecutiveFailures = consecutiveFailures
        self.cooldownSeconds = cooldownSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case consecutiveFailures
        case cooldownSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.consecutiveFailures = try container.decodeIfPresent(Int.self, forKey: .consecutiveFailures) ?? 3
        self.cooldownSeconds = try container.decodeIfPresent(Int.self, forKey: .cooldownSeconds) ?? 300
    }
}

public struct CustomServiceConfig: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var description: String
    public var category: String
    public var icon: String
    public var `protocol`: CustomServiceProtocol
    public var host: String?
    public var port: Int?
    public var url: String?
    public var healthUrl: String?
    public var internalUrl: String?
    public var authType: CustomServiceAuthType
    public var authToken: String?
    public var authHeaderName: String?
    public var jsonMetricPath: String?
    public var expectedStatus: Int?
    public var refreshIntervalSeconds: Int?
    public var verifySsl: Bool
    public var webhookTtlSeconds: Int
    public var order: Int
    public var enabled: Bool
    public var alertPolicy: AlertPolicyConfig

    // Optional live runtime health fields attached by GET /api/custom-services
    public var authTokenSet: Bool?
    public var status: String?
    public var online: Bool?
    public var latencyMs: Int?
    public var httpStatus: Int?
    public var statusCode: Int?
    public var message: String?
    public var metrics: [String: JSONValue]?
    public var consecutiveFailures: Int?
    public var lastCheckAt: String?
    public var lastTransitionAt: String?
    public var lastAlertAt: String?
    public var mutedUntil: String?
    public var lastError: String?

    public var serviceProtocol: CustomServiceProtocol {
        get { `protocol` }
        set { `protocol` = newValue }
    }

    public var isOnline: Bool {
        online ?? (status?.lowercased() == "up")
    }

    public var resolvedStatusCode: Int? {
        httpStatus ?? statusCode
    }

    public init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        description: String = "",
        category: String = "Services",
        icon: String = "server",
        protocol: CustomServiceProtocol = .httpRest,
        host: String? = nil,
        port: Int? = nil,
        url: String? = nil,
        healthUrl: String? = nil,
        internalUrl: String? = nil,
        authType: CustomServiceAuthType = .none,
        authToken: String? = nil,
        authHeaderName: String? = nil,
        jsonMetricPath: String? = nil,
        expectedStatus: Int? = 200,
        refreshIntervalSeconds: Int? = nil,
        verifySsl: Bool = true,
        webhookTtlSeconds: Int = 300,
        order: Int = 0,
        enabled: Bool = true,
        alertPolicy: AlertPolicyConfig = AlertPolicyConfig(),
        authTokenSet: Bool? = nil,
        status: String? = nil,
        online: Bool? = nil,
        latencyMs: Int? = nil,
        httpStatus: Int? = nil,
        statusCode: Int? = nil,
        message: String? = nil,
        metrics: [String: JSONValue]? = nil,
        consecutiveFailures: Int? = nil,
        lastCheckAt: String? = nil,
        lastTransitionAt: String? = nil,
        lastAlertAt: String? = nil,
        mutedUntil: String? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.icon = icon
        self.`protocol` = `protocol`
        self.host = host
        self.port = port
        self.url = url
        self.healthUrl = healthUrl
        self.internalUrl = internalUrl
        self.authType = authType
        self.authToken = authToken
        self.authHeaderName = authHeaderName
        self.jsonMetricPath = jsonMetricPath
        self.expectedStatus = expectedStatus
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.verifySsl = verifySsl
        self.webhookTtlSeconds = webhookTtlSeconds
        self.order = order
        self.enabled = enabled
        self.alertPolicy = alertPolicy
        self.authTokenSet = authTokenSet
        self.status = status
        self.online = online
        self.latencyMs = latencyMs
        self.httpStatus = httpStatus ?? statusCode
        self.statusCode = statusCode ?? httpStatus
        self.message = message
        self.metrics = metrics
        self.consecutiveFailures = consecutiveFailures
        self.lastCheckAt = lastCheckAt
        self.lastTransitionAt = lastTransitionAt
        self.lastAlertAt = lastAlertAt
        self.mutedUntil = mutedUntil
        self.lastError = lastError
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, category, icon
        case `protocol`
        case host, port, url, healthUrl, internalUrl
        case authType, authToken, authTokenSet, authHeaderName
        case jsonMetricPath, expectedStatus, refreshIntervalSeconds, verifySsl, webhookTtlSeconds
        case order, enabled, alertPolicy
        case status, online, latencyMs, httpStatus, statusCode, message, metrics
        case consecutiveFailures, lastCheckAt, lastTransitionAt, lastAlertAt, mutedUntil, lastError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Services"
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "server"
        self.`protocol` = try container.decodeIfPresent(CustomServiceProtocol.self, forKey: .`protocol`) ?? .httpRest
        self.host = try container.decodeIfPresent(String.self, forKey: .host)
        self.port = try container.decodeIfPresent(Int.self, forKey: .port)
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
        self.healthUrl = try container.decodeIfPresent(String.self, forKey: .healthUrl)
        self.internalUrl = try container.decodeIfPresent(String.self, forKey: .internalUrl)
        self.authType = try container.decodeIfPresent(CustomServiceAuthType.self, forKey: .authType) ?? .none
        self.authToken = try container.decodeIfPresent(String.self, forKey: .authToken)
        self.authTokenSet = try container.decodeIfPresent(Bool.self, forKey: .authTokenSet)
        self.authHeaderName = try container.decodeIfPresent(String.self, forKey: .authHeaderName)
        self.jsonMetricPath = try container.decodeIfPresent(String.self, forKey: .jsonMetricPath)
        self.expectedStatus = try container.decodeIfPresent(Int.self, forKey: .expectedStatus)
        self.refreshIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .refreshIntervalSeconds)
        self.verifySsl = try container.decodeIfPresent(Bool.self, forKey: .verifySsl) ?? true
        self.webhookTtlSeconds = try container.decodeIfPresent(Int.self, forKey: .webhookTtlSeconds) ?? 300
        self.order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.alertPolicy = try container.decodeIfPresent(AlertPolicyConfig.self, forKey: .alertPolicy) ?? AlertPolicyConfig()
        self.status = try container.decodeIfPresent(String.self, forKey: .status)
        self.online = try container.decodeIfPresent(Bool.self, forKey: .online)
        self.latencyMs = try container.decodeIfPresent(Int.self, forKey: .latencyMs)
        let hs = try container.decodeIfPresent(Int.self, forKey: .httpStatus)
        let sc = try container.decodeIfPresent(Int.self, forKey: .statusCode)
        self.httpStatus = hs ?? sc
        self.statusCode = sc ?? hs
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
        self.metrics = try container.decodeIfPresent([String: JSONValue].self, forKey: .metrics)
        self.consecutiveFailures = try container.decodeIfPresent(Int.self, forKey: .consecutiveFailures)
        self.lastCheckAt = try container.decodeIfPresent(String.self, forKey: .lastCheckAt)
        self.lastTransitionAt = try container.decodeIfPresent(String.self, forKey: .lastTransitionAt)
        self.lastAlertAt = try container.decodeIfPresent(String.self, forKey: .lastAlertAt)
        self.mutedUntil = try container.decodeIfPresent(String.self, forKey: .mutedUntil)
        self.lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }
}

public struct CustomServicesListResponse: Codable, Sendable, Equatable {
    public let services: [CustomServiceConfig]

    public init(services: [CustomServiceConfig]) {
        self.services = services
    }

    private enum CodingKeys: String, CodingKey {
        case services
        case items
    }

    public init(from decoder: Decoder) throws {
        if let direct = try? [CustomServiceConfig](from: decoder) {
            self.services = direct
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.services = (try? container.decodeIfPresent([CustomServiceConfig].self, forKey: .services))
            ?? (try? container.decodeIfPresent([CustomServiceConfig].self, forKey: .items))
            ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(services, forKey: .services)
    }
}

public struct CustomServiceTestResult: Codable, Sendable, Equatable {
    public let ok: Bool
    public let status: String
    public let latencyMs: Int
    public let httpStatus: Int?
    public let message: String
    public let metrics: [String: JSONValue]?

    public init(
        ok: Bool,
        status: String,
        latencyMs: Int,
        httpStatus: Int? = nil,
        message: String,
        metrics: [String: JSONValue]? = nil
    ) {
        self.ok = ok
        self.status = status
        self.latencyMs = latencyMs
        self.httpStatus = httpStatus
        self.message = message
        self.metrics = metrics
    }
}

public struct CustomServiceMutationResponse: Codable, Sendable, Equatable {
    public let ok: Bool
    public let service: CustomServiceConfig

    public init(ok: Bool = true, service: CustomServiceConfig) {
        self.ok = ok
        self.service = service
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case service
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let svc = try? container.decode(CustomServiceConfig.self, forKey: .service) {
            self.ok = (try? container.decodeIfPresent(Bool.self, forKey: .ok)) ?? true
            self.service = svc
            return
        }
        self.ok = true
        self.service = try CustomServiceConfig(from: decoder)
    }
}

public struct CustomServicesReorderRequest: Codable, Sendable, Equatable {
    public let serviceIds: [String]

    public init(serviceIds: [String]) {
        self.serviceIds = serviceIds
    }
}

// MARK: - Incidents & Alert Actions

public struct IncidentEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let serviceId: String
    public let serviceName: String
    public let severity: String
    public let title: String
    public let message: String
    public let startedAt: String
    public var resolvedAt: String?
    public var acknowledged: Bool
    public var acknowledgedAt: String?

    public var isActive: Bool {
        resolvedAt == nil || resolvedAt?.isEmpty == true
    }

    public init(
        id: String,
        serviceId: String,
        serviceName: String,
        severity: String,
        title: String,
        message: String,
        startedAt: String,
        resolvedAt: String? = nil,
        acknowledged: Bool = false,
        acknowledgedAt: String? = nil
    ) {
        self.id = id
        self.serviceId = serviceId
        self.serviceName = serviceName
        self.severity = severity
        self.title = title
        self.message = message
        self.startedAt = startedAt
        self.resolvedAt = resolvedAt
        self.acknowledged = acknowledged
        self.acknowledgedAt = acknowledgedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, serviceId, serviceName, severity, title, message
        case startedAt, resolvedAt, acknowledged, acknowledgedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try FlexibleJSONDecode.stringID(from: container, key: .id)
        self.serviceId = try container.decode(String.self, forKey: .serviceId)
        self.serviceName = (try? container.decodeIfPresent(String.self, forKey: .serviceName)) ?? self.serviceId
        self.severity = (try? container.decodeIfPresent(String.self, forKey: .severity)) ?? "critical"
        self.title = try container.decode(String.self, forKey: .title)
        self.message = (try? container.decodeIfPresent(String.self, forKey: .message)) ?? ""
        self.startedAt = try container.decode(String.self, forKey: .startedAt)
        self.resolvedAt = try container.decodeIfPresent(String.self, forKey: .resolvedAt)
        self.acknowledged = try container.decodeIfPresent(Bool.self, forKey: .acknowledged) ?? false
        self.acknowledgedAt = try container.decodeIfPresent(String.self, forKey: .acknowledgedAt)
    }
}

public struct IncidentsListResponse: Codable, Sendable, Equatable {
    public let incidents: [IncidentEvent]

    public init(incidents: [IncidentEvent]) {
        self.incidents = incidents
    }

    private enum CodingKeys: String, CodingKey {
        case incidents
        case items
    }

    public init(from decoder: Decoder) throws {
        if let direct = try? [IncidentEvent](from: decoder) {
            self.incidents = direct
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.incidents = (try? container.decodeIfPresent([IncidentEvent].self, forKey: .incidents))
            ?? (try? container.decodeIfPresent([IncidentEvent].self, forKey: .items))
            ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(incidents, forKey: .incidents)
    }
}

public struct MuteServiceRequest: Codable, Sendable, Equatable {
    public let minutes: Int

    public init(minutes: Int = 60) {
        self.minutes = minutes
    }
}

// MARK: - Notification Channels & APNs

public struct APNsConfigSummary: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var teamId: String
    public var keyId: String
    public var bundleId: String
    public var privateKeyPath: String
    public var useSandbox: Bool
    public var keyConfigured: Bool
    public var privateKeyExists: Bool
    public var registeredDevicesCount: Int

    public init(
        enabled: Bool = false,
        teamId: String = "",
        keyId: String = "",
        bundleId: String = "io.ac.pvepanel.app",
        privateKeyPath: String = "/app/config/AuthKey.p8",
        useSandbox: Bool = true,
        keyConfigured: Bool = false,
        privateKeyExists: Bool = false,
        registeredDevicesCount: Int = 0
    ) {
        self.enabled = enabled
        self.teamId = teamId
        self.keyId = keyId
        self.bundleId = bundleId
        self.privateKeyPath = privateKeyPath
        self.useSandbox = useSandbox
        self.keyConfigured = keyConfigured
        self.privateKeyExists = privateKeyExists
        self.registeredDevicesCount = registeredDevicesCount
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, teamId, keyId, bundleId, privateKeyPath, useSandbox
        case keyConfigured, privateKeyConfigured, configured
        case privateKeyExists, registeredDevicesCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.teamId = try container.decodeIfPresent(String.self, forKey: .teamId) ?? ""
        self.keyId = try container.decodeIfPresent(String.self, forKey: .keyId) ?? ""
        self.bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId) ?? "io.ac.pvepanel.app"
        self.privateKeyPath = try container.decodeIfPresent(String.self, forKey: .privateKeyPath) ?? "/app/config/AuthKey.p8"
        self.useSandbox = try container.decodeIfPresent(Bool.self, forKey: .useSandbox) ?? true
        let kc = try? container.decodeIfPresent(Bool.self, forKey: .keyConfigured)
        let pkc = try? container.decodeIfPresent(Bool.self, forKey: .privateKeyConfigured)
        let cfg = try? container.decodeIfPresent(Bool.self, forKey: .configured)
        let pke = try? container.decodeIfPresent(Bool.self, forKey: .privateKeyExists)
        self.privateKeyExists = pke ?? kc ?? pkc ?? false
        self.keyConfigured = kc ?? pkc ?? cfg ?? pke ?? false
        self.registeredDevicesCount = try container.decodeIfPresent(Int.self, forKey: .registeredDevicesCount) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(teamId, forKey: .teamId)
        try container.encode(keyId, forKey: .keyId)
        try container.encode(bundleId, forKey: .bundleId)
        try container.encode(privateKeyPath, forKey: .privateKeyPath)
        try container.encode(useSandbox, forKey: .useSandbox)
        try container.encode(keyConfigured, forKey: .keyConfigured)
        try container.encode(privateKeyExists, forKey: .privateKeyExists)
        try container.encode(registeredDevicesCount, forKey: .registeredDevicesCount)
    }
}

public struct NotificationChannelConfig: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var type: String
    public var enabled: Bool
    public var url: String?
    public var botToken: String?
    public var botTokenSet: Bool?
    public var chatId: String?
    public var headers: [String: String]?
    public var notifyOnDown: Bool
    public var notifyOnRecovery: Bool
    public var includeDetails: Bool

    public init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        type: String,
        enabled: Bool = true,
        url: String? = nil,
        botToken: String? = nil,
        botTokenSet: Bool? = nil,
        chatId: String? = nil,
        headers: [String: String]? = nil,
        notifyOnDown: Bool = true,
        notifyOnRecovery: Bool = true,
        includeDetails: Bool = true
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.enabled = enabled
        self.url = url
        self.botToken = botToken
        self.botTokenSet = botTokenSet
        self.chatId = chatId
        self.headers = headers
        self.notifyOnDown = notifyOnDown
        self.notifyOnRecovery = notifyOnRecovery
        self.includeDetails = includeDetails
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, type, enabled, url, botToken, botTokenSet, chatId, headers
        case notifyOnDown, notifyOnRecovery, includeDetails
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.type = try container.decode(String.self, forKey: .type)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
        self.botToken = try container.decodeIfPresent(String.self, forKey: .botToken)
        self.botTokenSet = try container.decodeIfPresent(Bool.self, forKey: .botTokenSet)
        self.chatId = try container.decodeIfPresent(String.self, forKey: .chatId)
        self.headers = try container.decodeIfPresent([String: String].self, forKey: .headers)
        self.notifyOnDown = try container.decodeIfPresent(Bool.self, forKey: .notifyOnDown) ?? true
        self.notifyOnRecovery = try container.decodeIfPresent(Bool.self, forKey: .notifyOnRecovery) ?? true
        self.includeDetails = try container.decodeIfPresent(Bool.self, forKey: .includeDetails) ?? true
    }
}

public struct NotificationChannelsResponse: Codable, Sendable, Equatable {
    public var apns: APNsConfigSummary
    public var webhooks: [NotificationChannelConfig]

    public init(apns: APNsConfigSummary = APNsConfigSummary(), webhooks: [NotificationChannelConfig] = []) {
        self.apns = apns
        self.webhooks = webhooks
    }
}

public struct TestNotificationRequest: Codable, Sendable, Equatable {
    public var channelId: String?
    public var channelType: String?

    public init(channelId: String? = nil, channelType: String? = nil) {
        self.channelId = channelId
        self.channelType = channelType
    }
}

public struct TestNotificationChannelResult: Codable, Sendable, Equatable, Identifiable {
    public var id: String { channelId ?? "\(channelType)-\(name ?? "default")" }
    public let channelId: String?
    public let channelType: String
    public let name: String?
    public let ok: Bool
    public let skipped: Bool?
    public let httpStatus: Int?
    public let message: String

    public init(
        channelId: String? = nil,
        channelType: String,
        name: String? = nil,
        ok: Bool,
        skipped: Bool? = nil,
        httpStatus: Int? = nil,
        message: String
    ) {
        self.channelId = channelId
        self.channelType = channelType
        self.name = name
        self.ok = ok
        self.skipped = skipped
        self.httpStatus = httpStatus
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case channelId, channelType, name, channelName, ok, skipped, httpStatus, message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.channelId = try container.decodeIfPresent(String.self, forKey: .channelId)
        self.channelType = try container.decodeIfPresent(String.self, forKey: .channelType) ?? "unknown"
        let n = try? container.decodeIfPresent(String.self, forKey: .name)
        let cn = try? container.decodeIfPresent(String.self, forKey: .channelName)
        self.name = n ?? cn
        self.ok = try container.decode(Bool.self, forKey: .ok)
        self.skipped = try container.decodeIfPresent(Bool.self, forKey: .skipped)
        self.httpStatus = try container.decodeIfPresent(Int.self, forKey: .httpStatus)
        self.message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(channelId, forKey: .channelId)
        try container.encode(channelType, forKey: .channelType)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(ok, forKey: .ok)
        try container.encodeIfPresent(skipped, forKey: .skipped)
        try container.encodeIfPresent(httpStatus, forKey: .httpStatus)
        try container.encode(message, forKey: .message)
    }
}

public struct TestNotificationResult: Codable, Sendable, Equatable {
    public let ok: Bool
    public let results: [TestNotificationChannelResult]
    public let message: String?

    public init(ok: Bool, results: [TestNotificationChannelResult] = [], message: String? = nil) {
        self.ok = ok
        self.results = results
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case ok, results, message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        self.results = try container.decodeIfPresent([TestNotificationChannelResult].self, forKey: .results) ?? []
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
    }
}

public struct APNsDeviceRegisterRequest: Codable, Sendable, Equatable {
    public let deviceToken: String
    public let platform: String
    public let deviceName: String
    public let appVersion: String
    public let environment: String

    public init(
        deviceToken: String,
        platform: String,
        deviceName: String,
        appVersion: String,
        environment: String
    ) {
        self.deviceToken = deviceToken
        self.platform = platform
        self.deviceName = deviceName
        self.appVersion = appVersion
        self.environment = environment
    }
}

// MARK: - Declarative YAML Config

public struct YAMLConfigResponse: Codable, Sendable, Equatable {
    public let yaml: String
    public let hash: String
    public let parsedSummary: [String: JSONValue]?

    public init(yaml: String, hash: String, parsedSummary: [String: JSONValue]? = nil) {
        self.yaml = yaml
        self.hash = hash
        self.parsedSummary = parsedSummary
    }

    private enum CodingKeys: String, CodingKey {
        case yaml, rawYaml, content
        case hash, configHash
        case parsedSummary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let y = try? container.decodeIfPresent(String.self, forKey: .yaml)
        let ry = try? container.decodeIfPresent(String.self, forKey: .rawYaml)
        let c = try? container.decodeIfPresent(String.self, forKey: .content)
        self.yaml = y ?? ry ?? c ?? ""

        let h = try? container.decodeIfPresent(String.self, forKey: .hash)
        let ch = try? container.decodeIfPresent(String.self, forKey: .configHash)
        self.hash = h ?? ch ?? ""

        self.parsedSummary = try container.decodeIfPresent([String: JSONValue].self, forKey: .parsedSummary)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(yaml, forKey: .yaml)
        try container.encode(hash, forKey: .hash)
        try container.encodeIfPresent(parsedSummary, forKey: .parsedSummary)
    }
}

public struct YAMLValidationResponse: Codable, Sendable, Equatable {
    public let valid: Bool
    public let errors: [String]
    public let warnings: [String]
    public let hash: String?
    public let message: String?

    public init(
        valid: Bool,
        errors: [String] = [],
        warnings: [String] = [],
        hash: String? = nil,
        message: String? = nil
    ) {
        self.valid = valid
        self.errors = errors
        self.warnings = warnings
        self.hash = hash
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case valid, ok, errors, warnings, hash, configHash, message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let v = try? container.decodeIfPresent(Bool.self, forKey: .valid)
        let ok = try? container.decodeIfPresent(Bool.self, forKey: .ok)
        self.valid = v ?? ok ?? false
        self.errors = try container.decodeIfPresent([String].self, forKey: .errors) ?? []
        self.warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        let h = try? container.decodeIfPresent(String.self, forKey: .hash)
        let ch = try? container.decodeIfPresent(String.self, forKey: .configHash)
        self.hash = h ?? ch
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(valid, forKey: .valid)
        try container.encode(errors, forKey: .errors)
        try container.encode(warnings, forKey: .warnings)
        try container.encodeIfPresent(hash, forKey: .hash)
        try container.encodeIfPresent(message, forKey: .message)
    }
}

public struct YAMLConfigUpdateRequest: Codable, Sendable, Equatable {
    public let yaml: String

    public init(yaml: String) {
        self.yaml = yaml
    }
}

// MARK: - Auth & Onboarding

public struct AuthLoginRequest: Codable, Sendable, Equatable {
    public var pin: String?
    public var token: String?
    public var deviceName: String?

    public init(pin: String? = nil, token: String? = nil, deviceName: String? = nil) {
        self.pin = pin
        self.token = token
        self.deviceName = deviceName
    }
}

public struct AuthLoginResponse: Codable, Sendable, Equatable {
    public let ok: Bool
    public let token: String
    public let tokenType: String
    public let expiresAt: String?
    public let user: AuthUser?

    public init(
        ok: Bool = true,
        token: String,
        tokenType: String = "bearer",
        expiresAt: String? = nil,
        user: AuthUser? = nil
    ) {
        self.ok = ok
        self.token = token
        self.tokenType = tokenType
        self.expiresAt = expiresAt
        self.user = user
    }

    private enum CodingKeys: String, CodingKey {
        case ok, token, accessToken, sessionToken, tokenType, expiresAt, user
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? true
        let t = try? container.decodeIfPresent(String.self, forKey: .token)
        let at = try? container.decodeIfPresent(String.self, forKey: .accessToken)
        let st = try? container.decodeIfPresent(String.self, forKey: .sessionToken)
        self.token = t ?? at ?? st ?? ""
        self.tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType) ?? "bearer"
        self.expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt)
        self.user = try container.decodeIfPresent(AuthUser.self, forKey: .user)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ok, forKey: .ok)
        try container.encode(token, forKey: .token)
        try container.encode(tokenType, forKey: .tokenType)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try container.encodeIfPresent(user, forKey: .user)
    }
}

public struct OnboardingStatusResponse: Codable, Sendable, Equatable {
    public let isConfigured: Bool
    public let needsOnboarding: Bool?
    public let configExists: Bool
    public let isSynthesized: Bool?
    public let hasApiTokens: Bool
    public let hasAdminPin: Bool
    public let apiTokensCount: Int?
    public let pinConfigured: Bool?
    public let serverId: String?
    public let serverName: String?
    public let publicUrl: String?
    public let tailscaleSsoEnabled: Bool
    public let mdnsEnabled: Bool
    public let authMethods: [String]?

    public init(
        isConfigured: Bool,
        needsOnboarding: Bool? = nil,
        configExists: Bool = false,
        isSynthesized: Bool? = nil,
        hasApiTokens: Bool = false,
        hasAdminPin: Bool = false,
        apiTokensCount: Int? = nil,
        pinConfigured: Bool? = nil,
        serverId: String? = nil,
        serverName: String? = nil,
        publicUrl: String? = nil,
        tailscaleSsoEnabled: Bool = false,
        mdnsEnabled: Bool = true,
        authMethods: [String]? = nil
    ) {
        self.isConfigured = isConfigured
        self.needsOnboarding = needsOnboarding
        self.configExists = configExists
        self.isSynthesized = isSynthesized
        self.hasApiTokens = hasApiTokens
        self.hasAdminPin = hasAdminPin
        self.apiTokensCount = apiTokensCount
        self.pinConfigured = pinConfigured
        self.serverId = serverId
        self.serverName = serverName
        self.publicUrl = publicUrl
        self.tailscaleSsoEnabled = tailscaleSsoEnabled
        self.mdnsEnabled = mdnsEnabled
        self.authMethods = authMethods
    }

    private enum CodingKeys: String, CodingKey {
        case isConfigured, configured, needsOnboarding, configExists, isSynthesized
        case hasApiTokens, hasAdminPin, apiTokensCount, pinConfigured
        case serverId, serverName, publicUrl
        case tailscaleSsoEnabled, mdnsEnabled, authMethods
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ic = try? container.decodeIfPresent(Bool.self, forKey: .isConfigured)
        let cfg = try? container.decodeIfPresent(Bool.self, forKey: .configured)
        self.isConfigured = ic ?? cfg ?? false
        self.needsOnboarding = try container.decodeIfPresent(Bool.self, forKey: .needsOnboarding)
        self.configExists = try container.decodeIfPresent(Bool.self, forKey: .configExists) ?? self.isConfigured
        self.isSynthesized = try container.decodeIfPresent(Bool.self, forKey: .isSynthesized)

        let tokensCount = try container.decodeIfPresent(Int.self, forKey: .apiTokensCount)
        let legacyTokens = try container.decodeIfPresent(Bool.self, forKey: .hasApiTokens)
        self.apiTokensCount = tokensCount
        self.hasApiTokens = legacyTokens ?? ((tokensCount ?? 0) > 0)

        let pinCfg = try container.decodeIfPresent(Bool.self, forKey: .pinConfigured)
        let legacyPin = try container.decodeIfPresent(Bool.self, forKey: .hasAdminPin)
        self.pinConfigured = pinCfg
        self.hasAdminPin = legacyPin ?? pinCfg ?? false

        self.serverId = try container.decodeIfPresent(String.self, forKey: .serverId)
        self.serverName = try container.decodeIfPresent(String.self, forKey: .serverName)
        self.publicUrl = try container.decodeIfPresent(String.self, forKey: .publicUrl)
        self.tailscaleSsoEnabled = try container.decodeIfPresent(Bool.self, forKey: .tailscaleSsoEnabled) ?? false
        self.mdnsEnabled = try container.decodeIfPresent(Bool.self, forKey: .mdnsEnabled) ?? true
        self.authMethods = try container.decodeIfPresent([String].self, forKey: .authMethods)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isConfigured, forKey: .isConfigured)
        try container.encodeIfPresent(needsOnboarding, forKey: .needsOnboarding)
        try container.encode(configExists, forKey: .configExists)
        try container.encodeIfPresent(isSynthesized, forKey: .isSynthesized)
        try container.encode(hasApiTokens, forKey: .hasApiTokens)
        try container.encode(hasAdminPin, forKey: .hasAdminPin)
        try container.encodeIfPresent(apiTokensCount, forKey: .apiTokensCount)
        try container.encodeIfPresent(pinConfigured, forKey: .pinConfigured)
        try container.encodeIfPresent(serverId, forKey: .serverId)
        try container.encodeIfPresent(serverName, forKey: .serverName)
        try container.encodeIfPresent(publicUrl, forKey: .publicUrl)
        try container.encode(tailscaleSsoEnabled, forKey: .tailscaleSsoEnabled)
        try container.encode(mdnsEnabled, forKey: .mdnsEnabled)
        try container.encodeIfPresent(authMethods, forKey: .authMethods)
    }
}

public struct OnboardingInitRequest: Codable, Sendable, Equatable {
    public var serverName: String
    public var publicUrl: String?
    public var tokenName: String?
    public var adminPin: String?
    public var tailscaleSsoEnabled: Bool?
    public var allowedTailscaleUsers: String?
    public var mdnsEnabled: Bool?
    public var pveHost: String?
    public var pveNode: String?
    public var pveTokenId: String?
    public var pveTokenSecret: String?
    public var pveVerifySsl: Bool?
    public var customServices: [CustomServiceConfig]?
    public var webhooks: [NotificationChannelConfig]?

    public init(
        serverName: String,
        publicUrl: String? = nil,
        tokenName: String? = "iOS / Apple App",
        adminPin: String? = nil,
        tailscaleSsoEnabled: Bool? = true,
        allowedTailscaleUsers: String? = nil,
        mdnsEnabled: Bool? = true,
        pveHost: String? = nil,
        pveNode: String? = nil,
        pveTokenId: String? = nil,
        pveTokenSecret: String? = nil,
        pveVerifySsl: Bool? = false,
        customServices: [CustomServiceConfig]? = nil,
        webhooks: [NotificationChannelConfig]? = nil
    ) {
        self.serverName = serverName
        self.publicUrl = publicUrl
        self.tokenName = tokenName
        self.adminPin = adminPin
        self.tailscaleSsoEnabled = tailscaleSsoEnabled
        self.allowedTailscaleUsers = allowedTailscaleUsers
        self.mdnsEnabled = mdnsEnabled
        self.pveHost = pveHost
        self.pveNode = pveNode
        self.pveTokenId = pveTokenId
        self.pveTokenSecret = pveTokenSecret
        self.pveVerifySsl = pveVerifySsl
        self.customServices = customServices
        self.webhooks = webhooks
    }

    private struct ProxmoxNestedPayload: Codable, Sendable {
        var host: String?
        var defaultNode: String?
        var tokenId: String?
        var tokenSecret: String?
        var verifySsl: Bool?
    }

    private struct NotificationsNestedPayload: Codable, Sendable {
        var webhooks: [NotificationChannelConfig]
    }

    private enum CodingKeys: String, CodingKey {
        case serverName, publicUrl, tokenName, adminPin
        case tailscaleSsoEnabled, allowedTailscaleUsers, mdnsEnabled
        case proxmox, notifications, customServices
        case pveHost, pveNode, pveTokenId, pveTokenSecret, pveVerifySsl, webhooks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.serverName = try container.decode(String.self, forKey: .serverName)
        self.publicUrl = try container.decodeIfPresent(String.self, forKey: .publicUrl)
        self.tokenName = try container.decodeIfPresent(String.self, forKey: .tokenName)
        self.adminPin = try container.decodeIfPresent(String.self, forKey: .adminPin)
        self.tailscaleSsoEnabled = try container.decodeIfPresent(Bool.self, forKey: .tailscaleSsoEnabled)
        self.allowedTailscaleUsers = try container.decodeIfPresent(String.self, forKey: .allowedTailscaleUsers)
        self.mdnsEnabled = try container.decodeIfPresent(Bool.self, forKey: .mdnsEnabled)
        self.customServices = try container.decodeIfPresent([CustomServiceConfig].self, forKey: .customServices)

        let nestedProxmox = try container.decodeIfPresent(ProxmoxNestedPayload.self, forKey: .proxmox)
        let flatHost = try container.decodeIfPresent(String.self, forKey: .pveHost)
        let flatNode = try container.decodeIfPresent(String.self, forKey: .pveNode)
        let flatTokenId = try container.decodeIfPresent(String.self, forKey: .pveTokenId)
        let flatSecret = try container.decodeIfPresent(String.self, forKey: .pveTokenSecret)
        let flatVerifySsl = try container.decodeIfPresent(Bool.self, forKey: .pveVerifySsl)
        self.pveHost = nestedProxmox?.host ?? flatHost
        self.pveNode = nestedProxmox?.defaultNode ?? flatNode
        self.pveTokenId = nestedProxmox?.tokenId ?? flatTokenId
        self.pveTokenSecret = nestedProxmox?.tokenSecret ?? flatSecret
        self.pveVerifySsl = nestedProxmox?.verifySsl ?? flatVerifySsl

        let nestedNotifications = try container.decodeIfPresent(NotificationsNestedPayload.self, forKey: .notifications)
        let flatWebhooks = try container.decodeIfPresent([NotificationChannelConfig].self, forKey: .webhooks)
        self.webhooks = nestedNotifications?.webhooks ?? flatWebhooks
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(serverName, forKey: .serverName)
        try container.encodeIfPresent(publicUrl, forKey: .publicUrl)
        try container.encodeIfPresent(tokenName, forKey: .tokenName)
        try container.encodeIfPresent(adminPin, forKey: .adminPin)
        try container.encodeIfPresent(tailscaleSsoEnabled, forKey: .tailscaleSsoEnabled)
        try container.encodeIfPresent(allowedTailscaleUsers, forKey: .allowedTailscaleUsers)
        try container.encodeIfPresent(mdnsEnabled, forKey: .mdnsEnabled)
        try container.encodeIfPresent(customServices, forKey: .customServices)

        let trimmedHost = pveHost?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNode = pveNode?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTokenId = pveTokenId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = pveTokenSecret?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasProxmoxFields = [trimmedHost, trimmedNode, trimmedTokenId, trimmedSecret]
            .contains { $0?.isEmpty == false } || pveVerifySsl != nil

        if hasProxmoxFields {
            let proxmoxPayload = ProxmoxNestedPayload(
                host: (trimmedHost?.isEmpty == false) ? trimmedHost : nil,
                defaultNode: (trimmedNode?.isEmpty == false) ? trimmedNode : nil,
                tokenId: (trimmedTokenId?.isEmpty == false) ? trimmedTokenId : nil,
                tokenSecret: (trimmedSecret?.isEmpty == false) ? trimmedSecret : nil,
                verifySsl: pveVerifySsl
            )
            try container.encode(proxmoxPayload, forKey: .proxmox)
        }

        if let webhooks, !webhooks.isEmpty {
            try container.encode(NotificationsNestedPayload(webhooks: webhooks), forKey: .notifications)
        }
    }
}

public struct OnboardingInitResponse: Codable, Sendable, Equatable {
    public let ok: Bool
    public let isConfigured: Bool?
    public let serverName: String?
    public let apiToken: String?
    public let tokenId: String?
    public let tokenName: String?
    public let serverId: String?
    public let configHash: String?
    public let configPath: String?
    public let message: String?

    public init(
        ok: Bool,
        isConfigured: Bool? = nil,
        serverName: String? = nil,
        apiToken: String? = nil,
        tokenId: String? = nil,
        tokenName: String? = nil,
        serverId: String? = nil,
        configHash: String? = nil,
        configPath: String? = nil,
        message: String? = nil
    ) {
        self.ok = ok
        self.isConfigured = isConfigured
        self.serverName = serverName
        self.apiToken = apiToken
        self.tokenId = tokenId
        self.tokenName = tokenName
        self.serverId = serverId
        self.configHash = configHash
        self.configPath = configPath
        self.message = message
    }
}

// MARK: - Encrypted Pairing (iPhone <-> Apple TV)

public struct CreatePairingSessionRequest: Codable, Sendable, Equatable {
    public let publicKey: String
    public let deviceName: String

    public init(publicKey: String, deviceName: String) {
        self.publicKey = publicKey
        self.deviceName = deviceName
    }
}

public struct PairingSessionInfo: Codable, Sendable, Equatable {
    public let pin: String
    public let sessionId: String
    public let publicKey: String
    public let deviceName: String
    public let expiresAt: String
    public let completed: Bool

    public init(
        pin: String,
        sessionId: String,
        publicKey: String = "",
        deviceName: String = "Apple TV",
        expiresAt: String = "",
        completed: Bool = false
    ) {
        self.pin = pin
        self.sessionId = sessionId
        self.publicKey = publicKey
        self.deviceName = deviceName
        self.expiresAt = expiresAt
        self.completed = completed
    }

    private enum CodingKeys: String, CodingKey {
        case pin, sessionId, publicKey, receiverPublicKey, deviceName, expiresAt, completed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.pin = try container.decode(String.self, forKey: .pin)
        self.sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId) ?? self.pin
        let pk = try? container.decodeIfPresent(String.self, forKey: .publicKey)
        let rpk = try? container.decodeIfPresent(String.self, forKey: .receiverPublicKey)
        self.publicKey = pk ?? rpk ?? ""
        self.deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName) ?? "Apple TV"
        self.expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt) ?? ""
        self.completed = try container.decodeIfPresent(Bool.self, forKey: .completed) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pin, forKey: .pin)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(publicKey, forKey: .publicKey)
        try container.encode(deviceName, forKey: .deviceName)
        try container.encode(expiresAt, forKey: .expiresAt)
        try container.encode(completed, forKey: .completed)
    }
}

public struct EncryptedPairingBundle: Codable, Sendable, Equatable {
    public let senderPublicKey: String
    public let nonce: String
    public let ciphertext: String
    public let tag: String

    public init(
        senderPublicKey: String,
        nonce: String,
        ciphertext: String,
        tag: String
    ) {
        self.senderPublicKey = senderPublicKey
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
    }
}

public typealias PairingCompletePayload = EncryptedPairingBundle

public struct PairingTransferPayload: Codable, Sendable, Equatable {
    public let serverName: String
    public let baseUrl: String
    public let apiToken: String
    public let configYamlSnippet: String?

    public init(
        serverName: String,
        baseUrl: String,
        apiToken: String,
        configYamlSnippet: String? = nil
    ) {
        self.serverName = serverName
        self.baseUrl = baseUrl
        self.apiToken = apiToken
        self.configYamlSnippet = configYamlSnippet
    }
}

// MARK: - Realtime WebSocket / SSE Events

public enum RealtimeEventType: String, Codable, Sendable, Equatable {
    case configReloaded = "config_reloaded"
    case serviceStatusChanged = "service_status_changed"
    case alertTriggered = "alert_triggered"
    case alertResolved = "alert_resolved"
    case incidentAcknowledged = "incident_acknowledged"
    case pairingCompleted = "pairing_completed"
    case unknown
}

public struct RealtimeEventEnvelope: Codable, Sendable, Equatable {
    public let type: String
    public let timestamp: String
    public let payload: [String: JSONValue]

    public var eventType: RealtimeEventType {
        RealtimeEventType(rawValue: type) ?? .unknown
    }

    public init(type: String, timestamp: String = "", payload: [String: JSONValue] = [:]) {
        self.type = type
        self.timestamp = timestamp
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey {
        case type, event, timestamp, payload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let t = try? container.decodeIfPresent(String.self, forKey: .type)
        let e = try? container.decodeIfPresent(String.self, forKey: .event)
        self.type = t ?? e ?? "unknown"
        self.timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp) ?? ""
        self.payload = try container.decodeIfPresent([String: JSONValue].self, forKey: .payload) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(payload, forKey: .payload)
    }

    private func payloadValue(_ camel: String, _ snake: String) -> JSONValue? {
        payload[camel] ?? payload[snake]
    }

    public var serviceId: String? { payloadValue("serviceId", "service_id")?.stringValue }
    public var serviceName: String? { payloadValue("serviceName", "service_name")?.stringValue }
    public var incidentId: String? { payloadValue("incidentId", "incident_id")?.stringValue }
    public var status: String? { payload["status"]?.stringValue }
    public var severity: String? { payload["severity"]?.stringValue }
    public var title: String? { payload["title"]?.stringValue }
    public var message: String? { payload["message"]?.stringValue }
    public var pin: String? { payload["pin"]?.stringValue }
    public var configHash: String? { payloadValue("configHash", "config_hash")?.stringValue ?? payload["hash"]?.stringValue }
    public var latencyMs: Int? { payloadValue("latencyMs", "latency_ms")?.intValue }
}
