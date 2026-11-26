import CryptoKit
import Foundation

/// Thread-safe in-memory state used when Demo Mode is active (or during App Store Review).
public actor DemoDataStore {
    public static let shared = DemoDataStore()

    private let gb: Int64 = 1024 * 1024 * 1024
    private let tb: Int64 = 1024 * 1024 * 1024 * 1024

    private var resources: [PveResource]
    private var pveTasks: [PveTaskItem]
    private var seerrRequests: [SeerrRequestItem]
    private var qbitAltSpeed: Bool = false
    private var qbitTorrents: [QbitTorrentItem]
    private var users: [UnifiedUser]
    private var setupEnv: SetupEnvConfig
    private var customServices: [CustomServiceConfig]
    private var mutableCategories: [ServiceCategory]?
    private var incidents: [IncidentEvent]
    private var notificationChannels: NotificationChannelsResponse
    private var yamlConfigText: String
    private var onboardingConfigured: Bool = true
    private var registeredAPNsTokens: Set<String> = []
    private var demoPairingSessions: [String: PairingSessionInfo] = [:]
    private var demoPairingBundles: [String: EncryptedPairingBundle] = [:]
    private var updateTargets: [UpdateTargetItem] = DemoDataStore.makeDefaultUpdateTargets()
    private var activeUpdateJob: UpdateJob?
    private var recentUpdateJobs: [UpdateJob] = []
    private var updateJobStepCursor: Int = 0
    private var updatesLastCheckedAt: String = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-120))

    public init() {
        let nowSec = Int(Date().timeIntervalSince1970)
        self.resources = [
            PveResource(
                vmid: 101,
                node: "pve-node-01",
                name: "ct-reverse-proxy",
                type: .lxc,
                status: "running",
                cpuPct: 4.2,
                cpus: 2,
                memUsedBytes: 420 * 1024 * 1024,
                memTotalBytes: 2 * 1024 * 1024 * 1024,
                memPct: 21.0,
                diskUsedBytes: 4 * 1024 * 1024 * 1024,
                diskTotalBytes: 16 * 1024 * 1024 * 1024,
                uptimeSeconds: 1_842_300,
                uptimeHuman: "21j 7h",
                tags: ["network", "prod"],
                isSelf: false
            ),
            PveResource(
                vmid: 102,
                node: "pve-node-01",
                name: "ct-media-server",
                type: .lxc,
                status: "running",
                cpuPct: 31.4,
                cpus: 8,
                memUsedBytes: 7 * 1024 * 1024 * 1024,
                memTotalBytes: 16 * 1024 * 1024 * 1024,
                memPct: 43.7,
                diskUsedBytes: 28 * 1024 * 1024 * 1024,
                diskTotalBytes: 64 * 1024 * 1024 * 1024,
                uptimeSeconds: 914_520,
                uptimeHuman: "10j 14h",
                tags: ["media", "gpu"],
                isSelf: false
            ),
            PveResource(
                vmid: 103,
                node: "pve-node-01",
                name: "vm-docker-host",
                type: .qemu,
                status: "running",
                cpuPct: 18.6,
                cpus: 6,
                memUsedBytes: 11 * 1024 * 1024 * 1024,
                memTotalBytes: 16 * 1024 * 1024 * 1024,
                memPct: 68.8,
                diskUsedBytes: 54 * 1024 * 1024 * 1024,
                diskTotalBytes: 120 * 1024 * 1024 * 1024,
                uptimeSeconds: 1_408_120,
                uptimeHuman: "16j 7h",
                tags: ["docker", "prod"],
                isSelf: false
            ),
            PveResource(
                vmid: 104,
                node: "pve-node-01",
                name: "ct-backup-node",
                type: .lxc,
                status: "stopped",
                cpuPct: 0,
                cpus: 4,
                memUsedBytes: 0,
                memTotalBytes: 4 * 1024 * 1024 * 1024,
                memPct: 0,
                diskUsedBytes: 14 * 1024 * 1024 * 1024,
                diskTotalBytes: 40 * 1024 * 1024 * 1024,
                uptimeSeconds: 0,
                uptimeHuman: "Arrêté",
                tags: ["backup"],
                isSelf: false
            ),
            PveResource(
                vmid: 116,
                node: "pve-node-01",
                name: "pve-panel",
                type: .lxc,
                status: "running",
                cpuPct: 1.8,
                cpus: 2,
                memUsedBytes: 360 * 1024 * 1024,
                memTotalBytes: 2 * 1024 * 1024 * 1024,
                memPct: 17.5,
                diskUsedBytes: 2 * 1024 * 1024 * 1024,
                diskTotalBytes: 8 * 1024 * 1024 * 1024,
                uptimeSeconds: 604_800,
                uptimeHuman: "7j 0h",
                tags: ["panel", "tailscale"],
                isSelf: true
            ),
            PveResource(
                vmid: 201,
                node: "pve-node-02",
                name: "ct-monitoring-stack",
                type: .lxc,
                status: "running",
                cpuPct: 12.4,
                cpus: 4,
                memUsedBytes: 3 * 1024 * 1024 * 1024,
                memTotalBytes: 8 * 1024 * 1024 * 1024,
                memPct: 37.5,
                diskUsedBytes: 18 * 1024 * 1024 * 1024,
                diskTotalBytes: 48 * 1024 * 1024 * 1024,
                uptimeSeconds: 1_123_200,
                uptimeHuman: "13j 0h",
                tags: ["grafana", "prometheus"],
                isSelf: false
            ),
            PveResource(
                vmid: 202,
                node: "pve-node-02",
                name: "vm-immich-ai",
                type: .qemu,
                status: "running",
                cpuPct: 28.5,
                cpus: 8,
                memUsedBytes: 14 * 1024 * 1024 * 1024,
                memTotalBytes: 32 * 1024 * 1024 * 1024,
                memPct: 43.8,
                diskUsedBytes: 92 * 1024 * 1024 * 1024,
                diskTotalBytes: 200 * 1024 * 1024 * 1024,
                uptimeSeconds: 784_800,
                uptimeHuman: "9j 2h",
                tags: ["photos", "gpu"],
                isSelf: false
            ),
            PveResource(
                vmid: 203,
                node: "pve-node-02",
                name: "ct-pbs-replicate",
                type: .lxc,
                status: "stopped",
                cpuPct: 0,
                cpus: 2,
                memUsedBytes: 0,
                memTotalBytes: 4 * 1024 * 1024 * 1024,
                memPct: 0,
                diskUsedBytes: 12 * 1024 * 1024 * 1024,
                diskTotalBytes: 60 * 1024 * 1024 * 1024,
                uptimeSeconds: 0,
                uptimeHuman: "Arrêté",
                tags: ["backup"],
                isSelf: false
            ),
        ]

        self.pveTasks = [
            PveTaskItem(
                upid: "UPID:pve-node-01:demo-vzdump-102",
                type: "vzdump",
                vmid: "102",
                user: "root@pam",
                status: "OK",
                starttime: nowSec - 3200,
                endtime: nowSec - 2810,
                durationSec: 390
            ),
            PveTaskItem(
                upid: "UPID:pve-node-01:demo-aptupdate",
                type: "aptupdate",
                vmid: "",
                user: "root@pam",
                status: "OK",
                starttime: nowSec - 14_400,
                endtime: nowSec - 14_350,
                durationSec: 50
            ),
            PveTaskItem(
                upid: "UPID:pve-node-01:demo-vzstart-101",
                type: "vzstart",
                vmid: "101",
                user: "root@pam",
                status: "OK",
                starttime: nowSec - 86_400,
                endtime: nowSec - 86_392,
                durationSec: 8
            ),
        ]

        self.seerrRequests = [
            SeerrRequestItem(
                id: 401,
                status: 1,
                mediaType: "movie",
                title: "Dune : Deuxième Partie (2024)",
                requestedBy: "Alex",
                createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-1500)),
                mediaStatus: 2
            ),
            SeerrRequestItem(
                id: 402,
                status: 2,
                mediaType: "tv",
                title: "Severance - Saison 2",
                requestedBy: "Camille",
                createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-18_000)),
                mediaStatus: 4
            ),
        ]

        self.qbitTorrents = [
            QbitTorrentItem(
                hash: "demo-hash-ubuntu-2404",
                name: "ubuntu-24.04.2-live-server-amd64.iso",
                state: "downloading",
                progressPct: 74.2,
                dlspeed: 24_800_000,
                upspeed: 3_100_000,
                size: 3_100_000_000,
                eta: 32
            ),
            QbitTorrentItem(
                hash: "demo-hash-debian-12",
                name: "debian-12.9.0-amd64-netinst.iso",
                state: "uploading",
                progressPct: 100,
                dlspeed: 0,
                upspeed: 5_400_000,
                size: 730_000_000,
                eta: 8_640_000
            ),
        ]

        self.users = [
            UnifiedUser(
                jellyfinId: "demo-admin-01",
                name: "Admin Démo",
                isAdmin: true,
                isProtected: true,
                isDisabled: false,
                enableAllFolders: true,
                enabledFolders: [],
                enableDownloading: true,
                maxActiveSessions: 0,
                lastActivity: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-120)),
                inJellyseerr: true,
                jellyseerrId: 1,
                requestCount: 14,
                autoApprove: true
            ),
            UnifiedUser(
                jellyfinId: "demo-guest-02",
                name: "Alex",
                isAdmin: false,
                isProtected: false,
                isDisabled: false,
                enableAllFolders: false,
                enabledFolders: ["lib-movies", "lib-series"],
                enableDownloading: true,
                maxActiveSessions: 2,
                lastActivity: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-10_800)),
                inJellyseerr: true,
                jellyseerrId: 2,
                requestCount: 6,
                autoApprove: true
            ),
            UnifiedUser(
                jellyfinId: "demo-guest-03",
                name: "Camille",
                isAdmin: false,
                isProtected: false,
                isDisabled: false,
                enableAllFolders: true,
                enabledFolders: [],
                enableDownloading: false,
                maxActiveSessions: 2,
                lastActivity: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-93_600)),
                inJellyseerr: false,
                jellyseerrId: nil,
                requestCount: 0,
                autoApprove: false
            ),
        ]

        self.setupEnv = SetupEnvConfig(
            devAuthBypass: false,
            allowedTailscaleUsers: "demo@pve-center.app",
            protectedOwnerUsername: "admin",
            pveHost: "https://192.168.1.10:8006",
            pveNode: "pve-node-01",
            pveTokenId: "root@pam!pve-panel",
            pveTokenSecretSet: true,
            pveVerifySsl: false,
            panelSelfVmid: 116,
            jellyfinUrl: "http://192.168.1.26:8096",
            jellyfinApiKeySet: true,
            jellyseerrUrl: "http://192.168.1.31:5055",
            jellyseerrApiKeySet: true,
            plexUrl: "http://192.168.1.30:32400",
            plexTokenSet: true,
            radarrUrl: "http://192.168.1.27:7878",
            radarrApiKeySet: true,
            sonarrUrl: "http://192.168.1.28:8989",
            sonarrApiKeySet: true,
            prowlarrUrl: "http://192.168.1.29:9696",
            prowlarrApiKeySet: true,
            qbitUrl: "http://192.168.1.32:8090",
            qbitUsername: "admin",
            qbitPasswordSet: true
        )

        let isoFormatter = ISO8601DateFormatter()
        self.customServices = [
            CustomServiceConfig(
                id: "jellyfin",
                name: "Jellyfin",
                description: "Serveur multimédia 4K HDR & transcodage matériel",
                category: "Médias & Streaming",
                icon: "film",
                protocol: .httpRest,
                url: "http://192.168.1.26:8096",
                healthUrl: "http://192.168.1.26:8096/health",
                expectedStatus: 200,
                order: 0,
                enabled: true,
                status: "up",
                online: true,
                latencyMs: 8,
                httpStatus: 200,
                message: "HTTP 200 OK",
                lastCheckAt: isoFormatter.string(from: Date().addingTimeInterval(-12))
            ),
            CustomServiceConfig(
                id: "proxmox-ssh",
                name: "Hôte Proxmox SSH",
                description: "Contrôle port TCP 22 sur pve-node-01",
                category: "Infrastructure & Sécurité",
                icon: "terminal",
                protocol: .tcpPort,
                host: "192.168.1.10",
                port: 22,
                order: 1,
                enabled: true,
                status: "up",
                online: true,
                latencyMs: 2,
                message: "Port TCP 22 ouvert",
                lastCheckAt: isoFormatter.string(from: Date().addingTimeInterval(-10))
            ),
            CustomServiceConfig(
                id: "gateway-icmp",
                name: "Passerelle Réseau",
                description: "Latence ICMP vers routeur principal",
                category: "Infrastructure & Sécurité",
                icon: "wifi",
                protocol: .icmpPing,
                host: "192.168.1.1",
                order: 2,
                enabled: true,
                status: "up",
                online: true,
                latencyMs: 1,
                message: "1 paquet reçu (1 ms)",
                lastCheckAt: isoFormatter.string(from: Date().addingTimeInterval(-8))
            ),
            CustomServiceConfig(
                id: "media-stats-json",
                name: "Télémétrie Streaming",
                description: "Extraction JSON des flux actifs et bibliothèque",
                category: "Médias & Streaming",
                icon: "chart.bar.doc.horizontal",
                protocol: .jsonMetrics,
                url: "http://192.168.1.26:8096/Sessions",
                jsonMetricPath: "active_streams",
                order: 3,
                enabled: true,
                status: "up",
                online: true,
                latencyMs: 11,
                httpStatus: 200,
                message: "Métriques extraites",
                metrics: [
                    "active_streams": .int(2),
                    "movies": .int(418),
                    "transcodes": .int(1),
                ],
                lastCheckAt: isoFormatter.string(from: Date().addingTimeInterval(-15))
            ),
            CustomServiceConfig(
                id: "backup-heartbeat",
                name: "Job Sauvegarde Nuit",
                description: "Webhook entrant Restic / Proxmox Backup",
                category: "Infrastructure & Sécurité",
                icon: "externaldrive.badge.checkmark",
                protocol: .webhookIngest,
                webhookTtlSeconds: 86400,
                order: 4,
                enabled: true,
                status: "up",
                online: true,
                latencyMs: 0,
                message: "Heartbeat reçu il y a 2h",
                metrics: [
                    "snapshots": .int(14),
                    "duration_s": .int(142),
                ],
                lastCheckAt: isoFormatter.string(from: Date().addingTimeInterval(-7200))
            ),
            CustomServiceConfig(
                id: "vaultwarden",
                name: "Vaultwarden",
                description: "Coffre-fort de mots de passe chiffré",
                category: "Infrastructure & Sécurité",
                icon: "shield",
                protocol: .httpRest,
                url: "http://192.168.1.35:8222",
                healthUrl: "http://192.168.1.35:8222/alive",
                expectedStatus: 200,
                order: 5,
                enabled: true,
                status: "down",
                online: false,
                latencyMs: 42,
                httpStatus: 502,
                message: "HTTP 502 Bad Gateway",
                lastCheckAt: isoFormatter.string(from: Date().addingTimeInterval(-25))
            ),
        ]

        self.incidents = [
            IncidentEvent(
                id: "inc-demo-01",
                serviceId: "vaultwarden",
                serviceName: "Vaultwarden",
                severity: "critical",
                title: "Vaultwarden hors ligne (HTTP 502)",
                message: "3 échecs consécutifs détectés sur /alive.",
                startedAt: isoFormatter.string(from: Date().addingTimeInterval(-420)),
                resolvedAt: nil,
                acknowledged: false,
                acknowledgedAt: nil
            ),
            IncidentEvent(
                id: "inc-demo-00",
                serviceId: "radarr",
                serviceName: "Radarr",
                severity: "warning",
                title: "Latence élevée détectée sur Radarr",
                message: "Temps de réponse revenu sous 20 ms.",
                startedAt: isoFormatter.string(from: Date().addingTimeInterval(-7200)),
                resolvedAt: isoFormatter.string(from: Date().addingTimeInterval(-6600)),
                acknowledged: true,
                acknowledgedAt: isoFormatter.string(from: Date().addingTimeInterval(-7000))
            ),
        ]

        self.notificationChannels = NotificationChannelsResponse(
            apns: APNsConfigSummary(
                enabled: true,
                teamId: "DEMO123456",
                keyId: "APNSDEMO01",
                bundleId: "io.ac.pvepanel.app",
                privateKeyPath: "/app/config/AuthKey.p8",
                useSandbox: true,
                keyConfigured: true
            ),
            webhooks: [
                NotificationChannelConfig(
                    id: "wh-discord-demo",
                    name: "Discord Homelab",
                    type: "discord",
                    enabled: true,
                    url: "https://discord.com/api/webhooks/demo/masked",
                    notifyOnDown: true,
                    notifyOnRecovery: true,
                    includeDetails: true
                ),
                NotificationChannelConfig(
                    id: "wh-ntfy-demo",
                    name: "ntfy Mobile",
                    type: "generic",
                    enabled: true,
                    url: "https://ntfy.sh/pve-center-demo",
                    notifyOnDown: true,
                    notifyOnRecovery: false,
                    includeDetails: true
                ),
            ]
        )

        self.yamlConfigText = """
        version: 1
        server:
          id: demo-pve-node-01
          name: Homelab Démo
          listen_host: 0.0.0.0
          listen_port: 8000
          public_url: https://panel.example.ts.net
          mdns_enabled: true
          mdns_service_name: pve-center-demo
          refresh_interval_seconds: 5
        security:
          tailscale_sso_enabled: true
          allowed_tailscale_users: demo@pve-center.app
          dev_auth_bypass: false
        proxmox:
          host: https://192.168.1.10:8006
          token_id: root@pam!pve-panel
          token_secret: ${PVE_TOKEN_SECRET}
          verify_ssl: false
          default_node: pve-node-01
        alerts:
          enabled: true
          default_consecutive_failures: 3
          default_cooldown_seconds: 300
          check_interval_seconds: 30
        """
    }

    public func currentUser() -> AuthUser {
        AuthUser(
            login: "demo@pve-center.app",
            name: "Mode Démo App Store",
            profilePic: nil,
            authMode: "demo"
        )
    }

    public func pveOverview(node: String? = nil) -> PveOverview {
        let reqNode = node?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let node1 = demoNodeSummary(for: "pve-node-01")
        let node2 = demoNodeSummary(for: "pve-node-02")
        let clusterNodes = demoClusterNodes(node1: node1, node2: node2)
        let extStorage = demoExternalStorage()

        if reqNode == "*" || reqNode.lowercased() == "all" {
            let sortedResources = resources.sorted {
                if $0.vmid != $1.vmid { return $0.vmid < $1.vmid }
                return ($0.node ?? "") < ($1.node ?? "")
            }
            let running = sortedResources.filter(\.isRunning).count
            let lxcCount = sortedResources.filter { $0.type == .lxc }.count
            let qemuCount = sortedResources.filter { $0.type == .qemu }.count

            let memUsed = node1.memUsedBytes + node2.memUsedBytes
            let memTotal = max(1, node1.memTotalBytes + node2.memTotalBytes)
            let memPct = ((Double(memUsed) / Double(memTotal)) * 1000).rounded() / 10
            let avgCpu = (((node1.cpuPct + node2.cpuPct) / 2.0) * 10).rounded() / 10

            let combinedStorages = node1.storages.map { st in
                StorageInfo(
                    name: "\(node1.name):\(st.name)",
                    type: st.type,
                    active: st.active,
                    usedBytes: st.usedBytes,
                    totalBytes: st.totalBytes,
                    usedPct: st.usedPct
                )
            } + node2.storages.map { st in
                StorageInfo(
                    name: "\(node2.name):\(st.name)",
                    type: st.type,
                    active: st.active,
                    usedBytes: st.usedBytes,
                    totalBytes: st.totalBytes,
                    usedPct: st.usedPct
                )
            }

            let clusterSummary = NodeSummary(
                name: "Cluster (2 nœuds)",
                cpuPct: avgCpu,
                cpuModel: node1.cpuModel,
                cpuThreads: node1.cpuThreads + node2.cpuThreads,
                loadavg: node1.loadavg,
                memUsedBytes: memUsed,
                memTotalBytes: memTotal,
                memPct: memPct,
                swapUsedBytes: node1.swapUsedBytes + node2.swapUsedBytes,
                swapTotalBytes: node1.swapTotalBytes + node2.swapTotalBytes,
                rootfsUsedBytes: node1.rootfsUsedBytes + node2.rootfsUsedBytes,
                rootfsTotalBytes: node1.rootfsTotalBytes + node2.rootfsTotalBytes,
                uptimeSeconds: max(node1.uptimeSeconds, node2.uptimeSeconds),
                uptimeHuman: node1.uptimeHuman,
                pveVersion: node1.pveVersion,
                storages: combinedStorages
            )

            return PveOverview(
                online: true,
                node: clusterSummary,
                counts: PveCounts(
                    total: sortedResources.count,
                    running: running,
                    stopped: sortedResources.count - running,
                    lxc: lxcCount,
                    qemu: qemuCount
                ),
                resources: sortedResources,
                externalStorage: extStorage,
                selectedNode: reqNode,
                failoverActive: false,
                clusterNodes: clusterNodes
            )
        }

        let targetNodeName = reqNode == "pve-node-02" ? "pve-node-02" : "pve-node-01"
        let nodeSummary = targetNodeName == "pve-node-02" ? node2 : node1
        let nodeResources = resources.filter { ($0.node ?? "pve-node-01") == targetNodeName }
        let running = nodeResources.filter(\.isRunning).count
        let lxcCount = nodeResources.filter { $0.type == .lxc }.count
        let qemuCount = nodeResources.filter { $0.type == .qemu }.count

        return PveOverview(
            online: true,
            node: nodeSummary,
            counts: PveCounts(
                total: nodeResources.count,
                running: running,
                stopped: nodeResources.count - running,
                lxc: lxcCount,
                qemu: qemuCount
            ),
            resources: nodeResources,
            externalStorage: extStorage,
            selectedNode: targetNodeName,
            failoverActive: false,
            clusterNodes: clusterNodes
        )
    }

    private func demoNodeSummary(for nodeName: String) -> NodeSummary {
        if nodeName == "pve-node-02" {
            return NodeSummary(
                name: "pve-node-02",
                cpuPct: 16.4,
                cpuModel: "Intel Xeon Silver 4314",
                cpuThreads: 16,
                loadavg: ["0.72", "0.68", "0.61"],
                memUsedBytes: 17 * gb,
                memTotalBytes: 48 * gb,
                memPct: 35.4,
                swapUsedBytes: 256 * 1024 * 1024,
                swapTotalBytes: 8 * gb,
                rootfsUsedBytes: 28 * gb,
                rootfsTotalBytes: 100 * gb,
                uptimeSeconds: 1_123_200,
                uptimeHuman: "13j 0h 15m",
                pveVersion: "8.3.2",
                storages: [
                    StorageInfo(
                        name: "local-zfs",
                        type: "zfspool",
                        active: true,
                        usedBytes: 280 * gb,
                        totalBytes: 1000 * gb,
                        usedPct: 28.0
                    ),
                    StorageInfo(
                        name: "local",
                        type: "dir",
                        active: true,
                        usedBytes: 52 * gb,
                        totalBytes: 120 * gb,
                        usedPct: 43.3
                    ),
                ]
            )
        }

        return NodeSummary(
            name: "pve-node-01",
            cpuPct: 23.8,
            cpuModel: "AMD Ryzen / EPYC Virtualization Host",
            cpuThreads: 16,
            loadavg: ["1.18", "1.05", "0.94"],
            memUsedBytes: 28 * gb,
            memTotalBytes: 64 * gb,
            memPct: 43.8,
            swapUsedBytes: 512 * 1024 * 1024,
            swapTotalBytes: 8 * gb,
            rootfsUsedBytes: 42 * gb,
            rootfsTotalBytes: 120 * gb,
            uptimeSeconds: 1_842_310,
            uptimeHuman: "21j 7h 45m",
            pveVersion: "8.3.2",
            storages: [
                StorageInfo(
                    name: "local-lvm",
                    type: "lvmthin",
                    active: true,
                    usedBytes: 412 * gb,
                    totalBytes: 1000 * gb,
                    usedPct: 41.2
                ),
                StorageInfo(
                    name: "local",
                    type: "dir",
                    active: true,
                    usedBytes: 88 * gb,
                    totalBytes: 240 * gb,
                    usedPct: 36.7
                ),
            ]
        )
    }

    private func demoClusterNodes(node1: NodeSummary, node2: NodeSummary) -> [ClusterNode] {
        [
            ClusterNode(
                name: node1.name,
                status: "online",
                online: true,
                cpuPct: node1.cpuPct,
                cpus: node1.cpuThreads,
                memUsedBytes: node1.memUsedBytes,
                memTotalBytes: node1.memTotalBytes,
                memPct: node1.memPct,
                uptimeSeconds: node1.uptimeSeconds,
                uptimeHuman: node1.uptimeHuman
            ),
            ClusterNode(
                name: node2.name,
                status: "online",
                online: true,
                cpuPct: node2.cpuPct,
                cpus: node2.cpuThreads,
                memUsedBytes: node2.memUsedBytes,
                memTotalBytes: node2.memTotalBytes,
                memPct: node2.memPct,
                uptimeSeconds: node2.uptimeSeconds,
                uptimeHuman: node2.uptimeHuman
            ),
        ]
    }

    private func demoExternalStorage() -> ExternalStorageOverview {
        ExternalStorageOverview(
            pool: MergerfsPoolInfo(
                name: "Pool MergerFS (32 To)",
                mount: "/mnt/storage",
                fstype: "fuse.mergerfs",
                policy: "mfs (most free space)",
                drivesCount: 3,
                available: true,
                totalBytes: 32 * tb,
                usedBytes: 20 * tb,
                availBytes: 12 * tb,
                usedPct: 62.5
            ),
            drives: [
                PhysicalDriveInfo(
                    mount: "/mnt/disk1",
                    label: "Disque 1 • 16 To",
                    wwn: "wwn-0x5000demo00000001",
                    devpath: "/dev/sda",
                    model: "Seagate IronWolf Pro 16TB",
                    vendor: "ATA",
                    serial: "DEMO-16TB-01",
                    type: "HDD",
                    rpm: "7200 rpm",
                    health: "PASSED",
                    sizeBytes: 16 * tb,
                    totalBytes: 16 * tb,
                    usedBytes: 10 * tb,
                    availBytes: 6 * tb,
                    usedPct: 62.5
                ),
                PhysicalDriveInfo(
                    mount: "/mnt/disk2",
                    label: "Disque 2 • 16 To",
                    wwn: "wwn-0x5000demo00000002",
                    devpath: "/dev/sdb",
                    model: "Seagate IronWolf Pro 16TB",
                    vendor: "ATA",
                    serial: "DEMO-16TB-02",
                    type: "HDD",
                    rpm: "7200 rpm",
                    health: "PASSED",
                    sizeBytes: 16 * tb,
                    totalBytes: 16 * tb,
                    usedBytes: 9 * tb,
                    availBytes: 7 * tb,
                    usedPct: 56.3
                ),
                PhysicalDriveInfo(
                    mount: "/mnt/disk3",
                    label: "Cache NVMe • 2 To",
                    wwn: "wwn-0x5000demo00000003",
                    devpath: "/dev/nvme0n1",
                    model: "Samsung 990 PRO 2TB",
                    vendor: "NVMe",
                    serial: "DEMO-NVME-01",
                    type: "SSD",
                    rpm: "NVMe",
                    health: "PASSED",
                    sizeBytes: 2 * tb,
                    totalBytes: 2 * tb,
                    usedBytes: 840 * gb,
                    availBytes: 1160 * gb,
                    usedPct: 42.0
                ),
            ],
            systemSsd: SystemSsdInfo(
                devpath: "/dev/nvme1n1",
                model: "Enterprise Boot NVMe 512GB",
                serial: "DEMO-SYS-01",
                health: "PASSED",
                sizeBytes: 512 * gb
            )
        )
    }

    public func performPveAction(type: PveResourceType, vmid: Int, action: PveAction, node: String? = nil) throws {
        let matchedIdx: Int? = {
            if let node, !node.isEmpty {
                return resources.firstIndex(where: {
                    $0.vmid == vmid && $0.type == type && ($0.node ?? "pve-node-01") == node
                })
            }
            return nil
        }() ?? resources.firstIndex(where: { $0.vmid == vmid && $0.type == type })

        guard let idx = matchedIdx else {
            throw APIError.serverError(statusCode: 404, detail: "Ressource introuvable en mode démo.")
        }
        if resources[idx].isSelf && action != .start {
            throw APIError.serverError(
                statusCode: 400,
                detail: "Action bloquée : impossible d'arrêter ou redémarrer le conteneur hébergeant le panel."
            )
        }
        switch action {
        case .stop, .shutdown:
            resources[idx].status = "stopped"
            resources[idx].cpuPct = 0
            resources[idx].memUsedBytes = 0
            resources[idx].memPct = 0
            resources[idx].uptimeSeconds = 0
            resources[idx].uptimeHuman = "Arrêté"
        case .start, .reboot:
            resources[idx].status = "running"
            resources[idx].cpuPct = 8.4
            resources[idx].memUsedBytes = Int64(Double(resources[idx].memTotalBytes) * 0.35)
            resources[idx].memPct = 35.0
            resources[idx].uptimeSeconds = 60
            resources[idx].uptimeHuman = "1m"
        }

        let targetNode = resources[idx].node ?? "pve-node-01"
        let now = Int(Date().timeIntervalSince1970)
        pveTasks.insert(
            PveTaskItem(
                upid: "UPID:\(targetNode):demo-\(action.rawValue)-\(vmid)-\(now)",
                type: "\(type == .lxc ? "vz" : "qm")\(action.rawValue)",
                vmid: "\(vmid)",
                user: "demo@pve",
                status: "OK",
                starttime: now,
                endtime: now + 1,
                durationSec: 1
            ),
            at: 0
        )
    }

    public func servicesCategories() -> [ServiceCategory] {
        if let mutableCategories {
            return mutableCategories
        }
        return [
            ServiceCategory(
                name: "Médias & Streaming",
                services: [
                    ServiceItem(
                        id: "jellyfin",
                        name: "Jellyfin",
                        description: "Serveur multimédia 4K HDR & transcodage matériel",
                        url: "https://panel.example.ts.net",
                        pingUrl: nil,
                        icon: "film",
                        widget: "jellyfin",
                        online: true,
                        latencyMs: 8.2,
                        statusCode: 200
                    ),
                    ServiceItem(
                        id: "jellyseerr",
                        name: "Jellyseerr",
                        description: "Portail de demandes de films et séries",
                        url: "https://panel.example.ts.net",
                        pingUrl: nil,
                        icon: "sparkles",
                        widget: nil,
                        online: true,
                        latencyMs: 11.4,
                        statusCode: 200
                    ),
                ]
            ),
            ServiceCategory(
                name: "Téléchargements & Automation",
                services: [
                    ServiceItem(
                        id: "radarr",
                        name: "Radarr",
                        description: "Gestion automatisée de la vidéothèque Films",
                        url: "https://panel.example.ts.net",
                        pingUrl: nil,
                        icon: "clapperboard",
                        widget: "radarr",
                        online: true,
                        latencyMs: 12.1,
                        statusCode: 200
                    ),
                    ServiceItem(
                        id: "sonarr",
                        name: "Sonarr",
                        description: "Suivi et téléchargement des séries TV",
                        url: "https://panel.example.ts.net",
                        pingUrl: nil,
                        icon: "tv",
                        widget: "sonarr",
                        online: true,
                        latencyMs: 13.0,
                        statusCode: 200
                    ),
                    ServiceItem(
                        id: "prowlarr",
                        name: "Prowlarr",
                        description: "Gestionnaire centralisé d'indexeurs",
                        url: "https://panel.example.ts.net",
                        pingUrl: nil,
                        icon: "search",
                        widget: "prowlarr",
                        online: true,
                        latencyMs: 9.6,
                        statusCode: 200
                    ),
                    ServiceItem(
                        id: "qbittorrent",
                        name: "qBittorrent",
                        description: "Client BitTorrent haute vitesse",
                        url: "https://panel.example.ts.net",
                        pingUrl: nil,
                        icon: "download",
                        widget: "qbittorrent",
                        online: true,
                        latencyMs: 7.4,
                        statusCode: 200
                    ),
                ]
            ),
            ServiceCategory(
                name: "Infrastructure & Sécurité",
                services: [
                    ServiceItem(
                        id: "proxmox",
                        name: "Proxmox VE",
                        description: "Hyperviseur principal KVM / LXC",
                        url: "https://panel.example.ts.net",
                        pingUrl: nil,
                        icon: "server",
                        widget: nil,
                        online: true,
                        latencyMs: 3.1,
                        statusCode: 200
                    ),
                    ServiceItem(
                        id: "vaultwarden",
                        name: "Vaultwarden",
                        description: "Coffre-fort de mots de passe chiffré",
                        url: "https://panel.example.ts.net",
                        pingUrl: nil,
                        icon: "shield",
                        widget: nil,
                        online: true,
                        latencyMs: 9.2,
                        statusCode: 200
                    ),
                ]
            ),
        ]
    }

    public func updateCategoryService(id: String, payload: CategoryServiceUpdateRequest) throws -> CategoryServiceMutationResponse {
        var cats = servicesCategories()
        for catIdx in cats.indices {
            if let svcIdx = cats[catIdx].services.firstIndex(where: { $0.id == id }) {
                let current = cats[catIdx].services[svcIdx]
                let updated = ServiceItem(
                    id: current.id,
                    name: payload.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? payload.name!.trimmingCharacters(in: .whitespacesAndNewlines) : current.name,
                    description: payload.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? current.description,
                    url: payload.url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? current.url,
                    pingUrl: payload.pingUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? current.pingUrl,
                    icon: payload.icon?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? payload.icon!.trimmingCharacters(in: .whitespacesAndNewlines) : current.icon,
                    widget: {
                        guard let w = payload.widget?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                            return current.widget
                        }
                        return w.isEmpty ? nil : w
                    }(),
                    online: current.online,
                    latencyMs: current.latencyMs,
                    statusCode: current.statusCode,
                    protocolType: current.protocolType,
                    metrics: current.metrics,
                    isCustom: current.isCustom
                )
                let targetCat = payload.category?.trimmingCharacters(in: .whitespacesAndNewlines)
                let destCatName = (targetCat?.isEmpty == false) ? targetCat! : cats[catIdx].name

                if destCatName.caseInsensitiveCompare(cats[catIdx].name) == .orderedSame {
                    var list = cats[catIdx].services
                    list[svcIdx] = updated
                    cats[catIdx] = ServiceCategory(name: cats[catIdx].name, services: list)
                } else {
                    var srcList = cats[catIdx].services
                    srcList.remove(at: svcIdx)
                    if srcList.isEmpty {
                        cats.remove(at: catIdx)
                    } else {
                        cats[catIdx] = ServiceCategory(name: cats[catIdx].name, services: srcList)
                    }
                    if let destIdx = cats.firstIndex(where: { $0.name.caseInsensitiveCompare(destCatName) == .orderedSame }) {
                        var destList = cats[destIdx].services
                        destList.append(updated)
                        cats[destIdx] = ServiceCategory(name: cats[destIdx].name, services: destList)
                    } else {
                        cats.append(ServiceCategory(name: destCatName, services: [updated]))
                    }
                }
                mutableCategories = cats
                return CategoryServiceMutationResponse(ok: true, category: destCatName, service: updated)
            }
        }
        throw APIError.serverError(statusCode: 404, detail: "Service introuvable : \(id)")
    }

    public func moveCategoryService(id: String, direction: String) {
        var cats = servicesCategories()
        for catIdx in cats.indices {
            if let svcIdx = cats[catIdx].services.firstIndex(where: { $0.id == id }) {
                let targetIdx = direction == "up" ? svcIdx - 1 : svcIdx + 1
                var list = cats[catIdx].services
                if list.indices.contains(targetIdx) {
                    list.swapAt(svcIdx, targetIdx)
                    cats[catIdx] = ServiceCategory(name: cats[catIdx].name, services: list)
                    mutableCategories = cats
                }
                return
            }
        }
    }

    public func deleteCategoryService(id: String) throws {
        var cats = servicesCategories()
        for catIdx in cats.indices {
            if let svcIdx = cats[catIdx].services.firstIndex(where: { $0.id == id }) {
                var list = cats[catIdx].services
                list.remove(at: svcIdx)
                if list.isEmpty {
                    cats.remove(at: catIdx)
                } else {
                    cats[catIdx] = ServiceCategory(name: cats[catIdx].name, services: list)
                }
                mutableCategories = cats
                return
            }
        }
        throw APIError.serverError(statusCode: 404, detail: "Service introuvable : \(id)")
    }

    public func testCategoryService(id: String, override: CategoryServiceTestRequest?) -> CategoryServiceTestResponse {
        return CategoryServiceTestResponse(
            ok: true,
            serviceId: id,
            online: true,
            statusCode: 200,
            latencyMs: 9,
            message: "Joignable (HTTP 200 • Mode Démo)"
        )
    }

    public func widgets() -> WidgetsMap {
        let dlTotal = qbitTorrents.reduce(Int64(0)) { $0 + ($1.isPaused ? 0 : $1.dlspeed) }
        let upTotal = qbitTorrents.reduce(Int64(0)) { $0 + ($1.isPaused ? 0 : $1.upspeed) }
        let factor = qbitAltSpeed ? 0.25 : 1.0

        return WidgetsMap(
            jellyfin: JellyfinWidget(
                status: "ok",
                activeStreamsCount: 2,
                activeStreams: [
                    JellyfinStream(
                        user: "Alex",
                        title: "Dune : Deuxième Partie",
                        device: "Apple TV 4K",
                        playMethod: "DirectPlay",
                        isPaused: false
                    ),
                    JellyfinStream(
                        user: "Camille",
                        title: "Severance S02E03",
                        device: "iPhone 16 Pro",
                        playMethod: "Transcode",
                        isPaused: false
                    ),
                ],
                moviesCount: 418,
                seriesCount: 64,
                episodesCount: 1840
            ),
            plex: nil,
            radarr: RadarrWidget(
                status: "ok",
                moviesTotal: 418,
                moviesDownloaded: 414,
                moviesMissing: 4,
                queueCount: 1,
                upcoming: [UpcomingItem(title: "Mickey 17", date: "2026-11-22")]
            ),
            sonarr: SonarrWidget(
                status: "ok",
                seriesTotal: 64,
                episodesDownloaded: 1840,
                queueCount: 2,
                upcoming: [UpcomingItem(title: "Severance S02E04", date: "2026-11-20")]
            ),
            prowlarr: ProwlarrWidget(
                status: "ok",
                indexersEnabled: 8,
                indexersTotal: 8,
                queries: 1420,
                grabs: 86
            ),
            qbittorrent: QbittorrentWidget(
                status: "ok",
                dlSpeedBytes: Int64(Double(dlTotal) * factor),
                upSpeedBytes: Int64(Double(upTotal) * factor),
                dlTotalBytes: 2 * tb,
                upTotalBytes: 6 * tb,
                downloadingCount: qbitTorrents.filter { $0.state == "downloading" }.count,
                seedingCount: qbitTorrents.filter { $0.state == "uploading" }.count,
                torrentsTotal: qbitTorrents.count
            )
        )
    }

    public func opsOverview() -> OpsOverview {
        OpsOverview(
            pveTasks: Array(pveTasks.prefix(12)),
            seerrRequests: seerrRequests,
            qbitControl: QbitControlOverview(
                available: true,
                altSpeedEnabled: qbitAltSpeed,
                torrents: qbitTorrents
            )
        )
    }

    public func decideSeerrRequest(id: Int, approve: Bool) throws {
        guard let idx = seerrRequests.firstIndex(where: { $0.id == id }) else {
            throw APIError.serverError(statusCode: 404, detail: "Demande introuvable.")
        }
        seerrRequests[idx].status = approve ? 2 : 3
    }

    public func toggleQbitSpeedMode() -> Bool {
        qbitAltSpeed.toggle()
        return qbitAltSpeed
    }

    public func controlTorrent(hash: String, pause: Bool) throws {
        guard let idx = qbitTorrents.firstIndex(where: { $0.hash == hash }) else {
            throw APIError.serverError(statusCode: 404, detail: "Torrent introuvable.")
        }
        let completed = qbitTorrents[idx].progressPct >= 100
        qbitTorrents[idx].state = pause ? (completed ? "pausedUP" : "pausedDL") : (completed ? "uploading" : "downloading")
    }

    public func usersOverview() -> UsersOverview {
        let total = users.count
        let synced = users.filter(\.inJellyseerr).count
        let disabled = users.filter(\.isDisabled).count

        return UsersOverview(
            counts: UsersCounts(
                totalJellyfin: total,
                syncedJellyseerr: synced,
                unsyncedCount: total - synced,
                disabledCount: disabled
            ),
            libraries: [
                JellyfinLibrary(id: "lib-movies", name: "Films 4K & HD"),
                JellyfinLibrary(id: "lib-series", name: "Séries TV"),
                JellyfinLibrary(id: "lib-anime", name: "Animation"),
            ],
            users: users
        )
    }

    public func createUser(_ req: CreateUserRequest) throws -> UnifiedUser {
        let trimmed = req.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            throw APIError.serverError(statusCode: 400, detail: "Nom d'utilisateur invalide.")
        }
        let created = UnifiedUser(
            jellyfinId: "demo-user-\(Int(Date().timeIntervalSince1970))",
            name: trimmed,
            isAdmin: false,
            isProtected: false,
            isDisabled: false,
            enableAllFolders: req.enableAllFolders,
            enabledFolders: req.enabledFolders,
            enableDownloading: req.enableDownloading,
            maxActiveSessions: req.maxActiveSessions,
            lastActivity: nil,
            inJellyseerr: req.syncJellyseerr,
            jellyseerrId: req.syncJellyseerr ? (users.count + 10) : nil,
            requestCount: 0,
            autoApprove: req.autoApprove
        )
        users.append(created)
        return created
    }

    public func syncUsers(_ req: SyncUsersRequest) -> Int {
        var count = 0
        for idx in users.indices {
            let match = req.jellyfinUserIds?.contains(users[idx].jellyfinId) ?? !users[idx].inJellyseerr
            if match {
                users[idx].inJellyseerr = true
                users[idx].jellyseerrId = users[idx].jellyseerrId ?? (idx + 10)
                users[idx].autoApprove = req.autoApprove
                count += 1
            }
        }
        return count
    }

    public func updateUser(id: String, req: UpdateUserRequest) throws {
        guard let idx = users.firstIndex(where: { $0.jellyfinId == id }) else {
            throw APIError.serverError(statusCode: 404, detail: "Utilisateur introuvable.")
        }
        if users[idx].isProtected == true && (req.isDisabled == true || req.isAdmin == false) {
            throw APIError.serverError(
                statusCode: 400,
                detail: "Impossible de désactiver ou rétrograder le compte propriétaire protégé."
            )
        }
        if let v = req.isDisabled { users[idx].isDisabled = v }
        if let v = req.isAdmin { users[idx].isAdmin = v }
        if let v = req.enableAllFolders { users[idx].enableAllFolders = v }
        if let v = req.enabledFolders { users[idx].enabledFolders = v }
        if let v = req.enableDownloading { users[idx].enableDownloading = v }
        if let v = req.maxActiveSessions { users[idx].maxActiveSessions = v }
        if let v = req.autoApprove { users[idx].autoApprove = v }
    }

    public func deleteUser(id: String) throws {
        guard let target = users.first(where: { $0.jellyfinId == id }) else {
            throw APIError.serverError(statusCode: 404, detail: "Utilisateur introuvable.")
        }
        if target.isProtected == true {
            throw APIError.serverError(statusCode: 400, detail: "Suppression du compte propriétaire protégé interdite.")
        }
        users.removeAll { $0.jellyfinId == id }
    }

    // MARK: - Setup Simulation

    public func setupStatus() -> SetupStatusResponse {
        let configured = !setupEnv.pveHost.isEmpty && setupEnv.pveTokenSecretSet
        let demoURL = "https://panel.example.ts.net"
        let encodedURL = demoURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? demoURL
        let encodedNode = setupEnv.pveNode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? setupEnv.pveNode
        return SetupStatusResponse(
            isConfigured: configured,
            tailscaleUrl: demoURL,
            pairingDeepLink: "pvecenter://connect?url=\(encodedURL)&name=\(encodedNode)",
            env: setupEnv,
            categories: servicesCategories().map { category in
                SetupCategoryConfig(
                    name: category.name,
                    services: category.services.map { svc in
                        SetupServiceConfig(
                            id: svc.id,
                            name: svc.name,
                            description: svc.description,
                            url: svc.url,
                            pingUrl: svc.pingUrl,
                            icon: svc.icon,
                            widget: svc.widget
                        )
                    }
                )
            },
            storageMounts: [
                StorageMountConfig(mount: "/mnt/disk1", subpath: "disk1", wwn: "wwn-0x5000demo00000001", label: "Disque 1 • 16 To"),
                StorageMountConfig(mount: "/mnt/disk2", subpath: "disk2", wwn: "wwn-0x5000demo00000002", label: "Disque 2 • 16 To"),
            ]
        )
    }

    public func testServiceConnection(_ req: ServiceTestRequest) -> ServiceTestResponse {
        let cleanURL = req.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanURL.isEmpty, cleanURL.lowercased().hasPrefix("http") else {
            return ServiceTestResponse(
                ok: false,
                service: req.service,
                message: "URL invalide ou vide pour \(req.service).",
                latencyMs: nil
            )
        }
        return ServiceTestResponse(
            ok: true,
            service: req.service,
            message: "Connexion simulée réussie (Mode Démo) vers \(cleanURL).",
            latencyMs: 6.4
        )
    }

    public func saveSetupConfig(_ req: SetupConfigUpdateRequest) -> SetupConfigUpdateResponse {
        if let env = req.env {
            if let v = env.devAuthBypass { setupEnv.devAuthBypass = v }
            if let v = env.allowedTailscaleUsers { setupEnv.allowedTailscaleUsers = v }
            if let v = env.protectedOwnerUsername { setupEnv.protectedOwnerUsername = v }
            if let v = env.pveHost { setupEnv.pveHost = v }
            if let v = env.pveNode { setupEnv.pveNode = v }
            if let v = env.pveTokenId { setupEnv.pveTokenId = v }
            if let v = env.pveTokenSecret, !v.isEmpty { setupEnv.pveTokenSecretSet = true }
            if let v = env.pveVerifySsl { setupEnv.pveVerifySsl = v }
            if let v = env.panelSelfVmid { setupEnv.panelSelfVmid = v }
            if let v = env.jellyfinUrl { setupEnv.jellyfinUrl = v }
            if let v = env.jellyfinApiKey, !v.isEmpty { setupEnv.jellyfinApiKeySet = true }
            if let v = env.jellyseerrUrl { setupEnv.jellyseerrUrl = v }
            if let v = env.jellyseerrApiKey, !v.isEmpty { setupEnv.jellyseerrApiKeySet = true }
            if let v = env.plexUrl { setupEnv.plexUrl = v }
            if let v = env.plexToken, !v.isEmpty { setupEnv.plexTokenSet = true }
            if let v = env.radarrUrl { setupEnv.radarrUrl = v }
            if let v = env.radarrApiKey, !v.isEmpty { setupEnv.radarrApiKeySet = true }
            if let v = env.sonarrUrl { setupEnv.sonarrUrl = v }
            if let v = env.sonarrApiKey, !v.isEmpty { setupEnv.sonarrApiKeySet = true }
            if let v = env.prowlarrUrl { setupEnv.prowlarrUrl = v }
            if let v = env.prowlarrApiKey, !v.isEmpty { setupEnv.prowlarrApiKeySet = true }
            if let v = env.qbitUrl { setupEnv.qbitUrl = v }
            if let v = env.qbitUsername { setupEnv.qbitUsername = v }
            if let v = env.qbitPassword, !v.isEmpty { setupEnv.qbitPasswordSet = true }
        }
        let configured = !setupEnv.pveHost.isEmpty && setupEnv.pveTokenSecretSet
        return SetupConfigUpdateResponse(
            ok: true,
            isConfigured: configured,
            message: "Configuration simulée enregistrée et rechargée (Mode Démo)."
        )
    }

    // MARK: - Auth & Onboarding

    public func login(_ req: AuthLoginRequest) throws -> AuthLoginResponse {
        if let pin = req.pin, !pin.isEmpty, pin.count < 4 {
            throw APIError.serverError(statusCode: 401, detail: "Code PIN invalide (Mode Démo).")
        }
        return AuthLoginResponse(
            ok: true,
            token: "demo-session-token-pve-center",
            tokenType: "bearer",
            expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(86_400)),
            user: currentUser()
        )
    }

    public func onboardingStatus() -> OnboardingStatusResponse {
        OnboardingStatusResponse(
            isConfigured: onboardingConfigured,
            configExists: onboardingConfigured,
            hasApiTokens: true,
            hasAdminPin: true,
            serverId: "demo-pve-node-01",
            serverName: "Homelab Démo",
            publicUrl: "https://panel.example.ts.net",
            tailscaleSsoEnabled: true,
            mdnsEnabled: true
        )
    }

    public func initOnboarding(_ req: OnboardingInitRequest) -> OnboardingInitResponse {
        onboardingConfigured = true
        if let services = req.customServices, !services.isEmpty {
            customServices.append(contentsOf: services)
        }
        if let webhooks = req.webhooks, !webhooks.isEmpty {
            notificationChannels.webhooks.append(contentsOf: webhooks)
        }
        return OnboardingInitResponse(
            ok: true,
            apiToken: "pve_demo_\(UUID().uuidString.prefix(12).lowercased())",
            tokenName: req.tokenName ?? "iOS / Apple App",
            serverId: "demo-pve-node-01",
            configHash: yamlHash(),
            message: "Configuration initiale simulée appliquée (Mode Démo)."
        )
    }

    // MARK: - Custom Services

    public func customServicesList() -> [CustomServiceConfig] {
        customServices.sorted { $0.order < $1.order }
    }

    public func createCustomService(_ service: CustomServiceConfig) -> CustomServiceConfig {
        var created = service
        if created.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            created.id = "svc-\(Int(Date().timeIntervalSince1970))"
        }
        created.order = customServices.count
        created.status = created.status ?? "up"
        created.online = created.online ?? true
        created.latencyMs = created.latencyMs ?? 9
        created.message = created.message ?? "Service ajouté (Mode Démo)"
        created.lastCheckAt = ISO8601DateFormatter().string(from: Date())
        customServices.append(created)
        return created
    }

    public func updateCustomService(id: String, service: CustomServiceConfig) throws -> CustomServiceConfig {
        guard let idx = customServices.firstIndex(where: { $0.id == id }) else {
            throw APIError.serverError(statusCode: 404, detail: "Service personnalisé introuvable.")
        }
        var updated = service
        updated.id = id
        updated.status = updated.status ?? customServices[idx].status
        updated.online = updated.online ?? customServices[idx].online
        updated.latencyMs = updated.latencyMs ?? customServices[idx].latencyMs
        customServices[idx] = updated
        return updated
    }

    public func deleteCustomService(id: String) throws {
        guard customServices.contains(where: { $0.id == id }) else {
            throw APIError.serverError(statusCode: 404, detail: "Service personnalisé introuvable.")
        }
        customServices.removeAll { $0.id == id }
    }

    public func reorderCustomServices(serviceIds: [String]) {
        let indexMap = Dictionary(uniqueKeysWithValues: serviceIds.enumerated().map { ($1, $0) })
        for idx in customServices.indices {
            if let newOrder = indexMap[customServices[idx].id] {
                customServices[idx].order = newOrder
            }
        }
        customServices.sort { $0.order < $1.order }
    }

    public func testCustomService(id: String, override: CustomServiceConfig? = nil) -> CustomServiceTestResult {
        let target = override ?? customServices.first(where: { $0.id == id })
        let targetName = target?.name ?? id
        let proto = target?.`protocol` ?? .httpRest
        let isDownDemo = id == "vaultwarden" && override == nil

        if isDownDemo {
            return CustomServiceTestResult(
                ok: false,
                status: "down",
                latencyMs: 42,
                httpStatus: 502,
                message: "HTTP 502 Bad Gateway simulé sur \(targetName)."
            )
        }

        return CustomServiceTestResult(
            ok: true,
            status: "up",
            latencyMs: proto == .icmpPing ? 1 : 9,
            httpStatus: (proto == .httpRest || proto == .jsonMetrics) ? 200 : nil,
            message: "Test \(proto.title) réussi sur \(targetName) (Mode Démo).",
            metrics: target?.metrics
        )
    }

    // MARK: - Incidents & Mute

    public func incidentsList(activeOnly: Bool, limit: Int) -> [IncidentEvent] {
        let filtered = activeOnly ? incidents.filter(\.isActive) : incidents
        return Array(filtered.prefix(max(1, limit)))
    }

    public func acknowledgeIncident(id: String) throws {
        guard let idx = incidents.firstIndex(where: { $0.id == id }) else {
            throw APIError.serverError(statusCode: 404, detail: "Incident introuvable.")
        }
        incidents[idx].acknowledged = true
        incidents[idx].acknowledgedAt = ISO8601DateFormatter().string(from: Date())
    }

    public func muteService(id: String, minutes: Int) {
        guard let idx = customServices.firstIndex(where: { $0.id == id }) else { return }
        customServices[idx].mutedUntil = ISO8601DateFormatter().string(
            from: Date().addingTimeInterval(TimeInterval(minutes * 60))
        )
    }

    public func unmuteService(id: String) {
        guard let idx = customServices.firstIndex(where: { $0.id == id }) else { return }
        customServices[idx].mutedUntil = nil
    }

    // MARK: - Notification Channels & APNs

    public func notificationChannelsOverview() -> NotificationChannelsResponse {
        notificationChannels
    }

    public func saveNotificationChannels(_ channels: NotificationChannelsResponse) -> NotificationChannelsResponse {
        notificationChannels = channels
        return notificationChannels
    }

    public func testNotification(_ request: TestNotificationRequest) -> TestNotificationResult {
        var results: [TestNotificationChannelResult] = []
        if request.channelType == nil || request.channelType == "all" || request.channelType == "apns" {
            results.append(TestNotificationChannelResult(
                channelId: "apns",
                channelType: "apns",
                name: "Apple Push (APNs)",
                ok: notificationChannels.apns.enabled,
                message: notificationChannels.apns.enabled
                    ? "Push APNs simulé envoyé (\(registeredAPNsTokens.count) appareil(s))."
                    : "APNs désactivé."
            ))
        }
        for webhook in notificationChannels.webhooks where webhook.enabled {
            if let targetID = request.channelId, targetID != webhook.id { continue }
            if let targetType = request.channelType, targetType != "all", targetType != webhook.type { continue }
            results.append(TestNotificationChannelResult(
                channelId: webhook.id,
                channelType: webhook.type,
                name: webhook.name,
                ok: true,
                message: "Notification de test envoyée à \(webhook.name) (Mode Démo)."
            ))
        }
        return TestNotificationResult(
            ok: results.allSatisfy(\.ok),
            results: results,
            message: "Test effectué sur \(results.count) canal(aux)."
        )
    }

    public func registerAPNsDevice(_ req: APNsDeviceRegisterRequest) {
        registeredAPNsTokens.insert(req.deviceToken)
    }

    public func unregisterAPNsDevice(_ token: String) {
        registeredAPNsTokens.remove(token)
    }

    // MARK: - Declarative YAML Config

    public func fetchConfigYAML() -> YAMLConfigResponse {
        YAMLConfigResponse(
            yaml: yamlConfigText,
            hash: yamlHash(),
            parsedSummary: [
                "version": .int(1),
                "custom_services_count": .int(customServices.count),
                "webhooks_count": .int(notificationChannels.webhooks.count),
            ]
        )
    }

    public func validateConfigYAML(_ yaml: String) -> YAMLValidationResponse {
        let trimmed = yaml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return YAMLValidationResponse(valid: false, errors: ["Le fichier YAML ne peut pas être vide."], warnings: [])
        }
        var warnings: [String] = []
        if !trimmed.contains("server:") {
            warnings.append("Section 'server:' absente — valeurs par défaut appliquées.")
        }
        return YAMLValidationResponse(
            valid: true,
            errors: [],
            warnings: warnings,
            hash: sha256Hex(trimmed),
            message: "YAML valide (Mode Démo)."
        )
    }

    public func saveConfigYAML(_ yaml: String) -> YAMLValidationResponse {
        let validation = validateConfigYAML(yaml)
        if validation.valid {
            yamlConfigText = yaml
        }
        return YAMLValidationResponse(
            valid: validation.valid,
            errors: validation.errors,
            warnings: validation.warnings,
            hash: yamlHash(),
            message: validation.valid ? "Configuration YAML sauvegardée et rechargée (Mode Démo)." : "Erreurs de validation YAML."
        )
    }

    public func exportConfigYAML() -> String {
        yamlConfigText
    }

    // MARK: - LAN Discovery & Pairing

    public func lanDiscoveryServices() -> [DiscoveryServerItem] {
        [
            DiscoveryServerItem(
                id: "demo-pvecenter-01",
                name: "Homelab Démo (pve-node-01)",
                serviceType: "_pvecenter._tcp",
                host: "192.168.1.10",
                port: 8000,
                isHttps: false,
                publicUrl: "https://panel.example.ts.net",
                version: "2.0.0",
                txt: ["id": "demo-pvecenter-01", "name": "Homelab Démo", "version": "2.0.0"],
                suggestedProtocol: .httpRest,
                isLocalBonjour: false
            ),
            DiscoveryServerItem(
                id: "demo-nas-smb",
                name: "NAS Storage (SMB)",
                serviceType: "_smb._tcp",
                host: "192.168.1.20",
                port: 445,
                isHttps: false,
                suggestedProtocol: .tcpPort,
                isLocalBonjour: false
            ),
            DiscoveryServerItem(
                id: "demo-pve-ssh",
                name: "Proxmox VE SSH",
                serviceType: "_ssh._tcp",
                host: "192.168.1.10",
                port: 22,
                isHttps: false,
                suggestedProtocol: .tcpPort,
                isLocalBonjour: false
            ),
            DiscoveryServerItem(
                id: "demo-grafana-http",
                name: "Grafana Monitoring",
                serviceType: "_http._tcp",
                host: "192.168.1.33",
                port: 3000,
                isHttps: false,
                suggestedProtocol: .httpRest,
                isLocalBonjour: false
            ),
        ]
    }

    public func discoveryQR(baseURL: String) -> DiscoveryQRResponse {
        let resolved = baseURL.isEmpty ? "https://panel.example.ts.net" : baseURL
        let encoded = resolved.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? resolved
        return DiscoveryQRResponse(
            deepLink: "pvecenter://connect?url=\(encoded)&name=Homelab%20D%C3%A9mo",
            onboardingLink: "pvecenter://connect?url=\(encoded)&name=Homelab%20D%C3%A9mo",
            publicUrl: resolved,
            svgDataUrl: nil,
            serverId: "demo-pve-node-01",
            serverName: "Homelab Démo"
        )
    }

    public func createDemoPairingSession(publicKey: String, deviceName: String) -> PairingSessionInfo {
        let pin = String(format: "%06d", Int.random(in: 0...999_999))
        let session = PairingSessionInfo(
            pin: pin,
            sessionId: UUID().uuidString.lowercased(),
            publicKey: publicKey,
            deviceName: deviceName,
            expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(300)),
            completed: false
        )
        demoPairingSessions[pin] = session
        return session
    }

    public func fetchDemoPairingSession(pin: String) throws -> PairingSessionInfo {
        guard let session = demoPairingSessions[pin] else {
            throw APIError.serverError(statusCode: 404, detail: "Session d'appairage introuvable.")
        }
        return session
    }

    public func completeDemoPairingSession(pin: String, bundle: EncryptedPairingBundle) throws {
        guard var session = demoPairingSessions[pin] else {
            throw APIError.serverError(statusCode: 404, detail: "Session d'appairage introuvable.")
        }
        session = PairingSessionInfo(
            pin: session.pin,
            sessionId: session.sessionId,
            publicKey: session.publicKey,
            deviceName: session.deviceName,
            expiresAt: session.expiresAt,
            completed: true
        )
        demoPairingSessions[pin] = session
        demoPairingBundles[pin] = bundle
    }

    public func fetchDemoPairingPayload(pin: String) -> EncryptedPairingBundle? {
        demoPairingBundles.removeValue(forKey: pin)
    }

    private func yamlHash() -> String {
        sha256Hex(yamlConfigText)
    }

    private func sha256Hex(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Unified Update Center (Demo Mode)

    private static func makeDefaultUpdateTargets() -> [UpdateTargetItem] {
        let ts = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-120))
        return [
            UpdateTargetItem(
                id: "panel:server",
                category: "pve_center",
                kind: "panel_server",
                name: "Serveur PVE Command Center",
                subtitle: "Repo /opt/pve-panel • conteneur LXC #116",
                scope: nil,
                node: "pve-node-01",
                vmid: 116,
                composeDir: nil,
                status: "online",
                currentVersion: "v1.0.0",
                latestVersion: "v1.1.0",
                updateAvailable: true,
                pendingCount: 1,
                packagesPreview: ["pve-panel -> v1.1.0"],
                canExecute: true,
                requiresSsh: true,
                releaseUrl: "https://github.com/PVE-Center/pve-panel/releases",
                lastCheckedAt: ts
            ),
            UpdateTargetItem(
                id: "client:apple",
                category: "pve_center",
                kind: "client_app",
                name: "Applications Apple (iOS / macOS / tvOS)",
                subtitle: "Swift 6 natif (Xcode / TestFlight)",
                scope: nil,
                node: nil,
                vmid: nil,
                composeDir: nil,
                status: "available",
                currentVersion: "v1.0.0",
                latestVersion: "v1.1.0",
                updateAvailable: true,
                pendingCount: nil,
                packagesPreview: ["PVECenter.app"],
                canExecute: false,
                requiresSsh: false,
                releaseUrl: "https://github.com/PVE-Center/pve-center-apple/releases",
                lastCheckedAt: ts
            ),
            UpdateTargetItem(
                id: "client:desktop",
                category: "pve_center",
                kind: "client_app",
                name: "Client Desktop (Windows / Linux)",
                subtitle: "Tauri v2 (.exe / .msi / .AppImage / .deb)",
                scope: nil,
                node: nil,
                vmid: nil,
                composeDir: nil,
                status: "available",
                currentVersion: "v1.0.0",
                latestVersion: "v1.1.0",
                updateAvailable: true,
                pendingCount: nil,
                packagesPreview: ["PVE.Center-setup.exe", "pve-center_amd64.AppImage"],
                canExecute: false,
                requiresSsh: false,
                releaseUrl: "https://github.com/PVE-Center/pve-center-clients/releases",
                lastCheckedAt: ts
            ),
            UpdateTargetItem(
                id: "proxmox:pve-node-01",
                category: "proxmox",
                kind: "pve_node",
                name: "Nœud Proxmox VE : pve-node-01",
                subtitle: "APT système & hyperviseur Proxmox",
                scope: nil,
                node: "pve-node-01",
                vmid: nil,
                composeDir: nil,
                status: "online",
                currentVersion: "APT",
                latestVersion: "3 paquet(s)",
                updateAvailable: true,
                pendingCount: 3,
                packagesPreview: ["pve-manager (8.3.1 -> 8.3.2)", "proxmox-ve (8.3.0 -> 8.3.1)", "libpve-storage-perl (8.3.1 -> 8.3.3)"],
                canExecute: true,
                requiresSsh: true,
                releaseUrl: nil,
                lastCheckedAt: ts
            ),
            UpdateTargetItem(
                id: "lxc:102",
                category: "containers_vms",
                kind: "lxc",
                name: "ct-media-server (#102)",
                subtitle: "LXC sur pve-node-01 • running",
                scope: nil,
                node: "pve-node-01",
                vmid: 102,
                composeDir: nil,
                status: "running",
                currentVersion: "OS invité",
                latestVersion: "5 paquet(s)",
                updateAvailable: true,
                pendingCount: 5,
                packagesPreview: [],
                canExecute: true,
                requiresSsh: true,
                releaseUrl: nil,
                lastCheckedAt: ts
            ),
            UpdateTargetItem(
                id: "qemu:103",
                category: "containers_vms",
                kind: "qemu",
                name: "vm-docker-host (#103)",
                subtitle: "QEMU sur pve-node-01 • running",
                scope: nil,
                node: "pve-node-01",
                vmid: 103,
                composeDir: nil,
                status: "running",
                currentVersion: "OS invité",
                latestVersion: "Prêt pour QEMU Guest Agent",
                updateAvailable: true,
                pendingCount: 4,
                packagesPreview: [],
                canExecute: true,
                requiresSsh: false,
                releaseUrl: nil,
                lastCheckedAt: ts
            ),
            UpdateTargetItem(
                id: "docker:media-stack",
                category: "docker",
                kind: "docker_compose",
                name: "Stack Docker : media-stack",
                subtitle: "LXC 102 (pve-node-01) • /opt/stacks/media",
                scope: "lxc",
                node: "pve-node-01",
                vmid: 102,
                composeDir: "/opt/stacks/media",
                status: "running",
                currentVersion: "4 conteneur(s)",
                latestVersion: "Pull / Recreate",
                updateAvailable: true,
                pendingCount: 4,
                packagesPreview: ["jellyfin/jellyfin:latest", "lscr.io/linuxserver/radarr:latest", "lscr.io/linuxserver/sonarr:latest"],
                canExecute: true,
                requiresSsh: true,
                releaseUrl: nil,
                lastCheckedAt: ts
            ),
        ]
    }

    public func updatesOverview() -> UpdatesOverviewResponse {
        UpdatesOverviewResponse(
            enabled: true,
            sshConfigured: true,
            sshMessage: "Connecté en SSH (root@192.168.1.10 • Mode Démo).",
            sshHost: "192.168.1.10",
            lastCheckedAt: updatesLastCheckedAt,
            summary: UpdatesSummary(
                totalTargets: updateTargets.count,
                updatesAvailable: updateTargets.filter(\.updateAvailable).count,
                pendingPackages: updateTargets.reduce(0) { $0 + ($1.updateAvailable ? ($1.pendingCount ?? 0) : 0) },
                executableTargets: updateTargets.filter(\.canExecute).count
            ),
            targets: updateTargets,
            activeJob: activeUpdateJob,
            recentJobs: recentUpdateJobs
        )
    }

    public func checkUpdates() -> UpdatesOverviewResponse {
        let now = ISO8601DateFormatter().string(from: Date())
        updatesLastCheckedAt = now
        for idx in updateTargets.indices {
            updateTargets[idx].lastCheckedAt = now
        }
        return updatesOverview()
    }

    public func runUpdates(_ request: RunUpdatesRequest) throws -> RunUpdatesResponse {
        if activeUpdateJob?.status == "running" {
            throw APIError.serverError(statusCode: 409, detail: "Une opération de mise à jour est déjà en cours.")
        }

        let selected = updateTargets
            .filter { target in
                if request.targetIds.contains("all") {
                    return target.canExecute && (target.id != "panel:server" || request.includePanelSelf)
                }
                return request.targetIds.contains(target.id) && target.canExecute
            }
            .sorted { ($0.id == "panel:server" ? 1 : 0) < ($1.id == "panel:server" ? 1 : 0) }

        guard !selected.isEmpty else {
            throw APIError.serverError(statusCode: 400, detail: "Aucune cible exécutable sélectionnée.")
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let job = UpdateJob(
            id: "upd-demo-\(UUID().uuidString.prefix(5).lowercased())",
            status: "running",
            startedAt: now,
            finishedAt: nil,
            progressPct: 10,
            steps: selected.enumerated().map { idx, t in
                UpdateJobStep(
                    targetId: t.id,
                    name: t.name,
                    category: t.category,
                    status: idx == 0 ? "running" : "pending",
                    message: idx == 0 ? "Mise à jour en cours (Démo)…" : "En attente"
                )
            },
            logs: ["[\(now)] Démarrage de la mise à jour centralisée (\(selected.count) cible(s))."]
        )
        activeUpdateJob = job
        updateJobStepCursor = 0
        return RunUpdatesResponse(ok: true, job: job)
    }

    public func updatesJobStatus() -> UpdatesJobStatusResponse {
        if var job = activeUpdateJob, job.status == "running" {
            let now = ISO8601DateFormatter().string(from: Date())
            if updateJobStepCursor < job.steps.count {
                let targetId = job.steps[updateJobStepCursor].targetId
                job.steps[updateJobStepCursor].status = "succeeded"
                job.steps[updateJobStepCursor].message = "Mis à jour avec succès (Démo)."
                job.logs.append("[\(now)] OK \(job.steps[updateJobStepCursor].name) -> À jour")
                if let tIdx = updateTargets.firstIndex(where: { $0.id == targetId }) {
                    updateTargets[tIdx].updateAvailable = false
                    updateTargets[tIdx].pendingCount = 0
                    updateTargets[tIdx].latestVersion = "À jour"
                }
                updateJobStepCursor += 1
                job.progressPct = Int((Double(updateJobStepCursor) / Double(max(1, job.steps.count))) * 100)
                if updateJobStepCursor < job.steps.count {
                    job.steps[updateJobStepCursor].status = "running"
                    job.steps[updateJobStepCursor].message = "Mise à jour en cours (Démo)…"
                } else {
                    job.status = "succeeded"
                    job.finishedAt = now
                    recentUpdateJobs.insert(job, at: 0)
                    recentUpdateJobs = Array(recentUpdateJobs.prefix(8))
                }
                activeUpdateJob = job
            }
        }
        return UpdatesJobStatusResponse(activeJob: activeUpdateJob, recentJobs: recentUpdateJobs)
    }

    public func updatesSetupInfo() -> UpdatesSetupInfoResponse {
        let pub = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDemoUpdateCenterKey000000000000 pve-center-updates"
        return UpdatesSetupInfoResponse(
            sshConfigured: true,
            sshMessage: "Connecté en SSH (root@192.168.1.10 • Mode Démo).",
            sshHost: "192.168.1.10",
            sshPort: 22,
            sshUser: "root",
            sshPublicKey: pub,
            proxmoxOneLiner: "mkdir -p ~/.ssh && printf '%s\\n' '\(pub)' >> ~/.ssh/authorized_keys",
            panelRepoDir: "/opt/pve-panel"
        )
    }

    public func rotateUpdatesSSHKey() -> UpdatesSetupInfoResponse {
        let pub = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIRotatedDemoKey00000000000000 pve-center-updates"
        return UpdatesSetupInfoResponse(
            sshConfigured: true,
            sshMessage: "Nouvelle clé Ed25519 générée (Mode Démo).",
            sshHost: "192.168.1.10",
            sshPort: 22,
            sshUser: "root",
            sshPublicKey: pub,
            proxmoxOneLiner: "mkdir -p ~/.ssh && printf '%s\\n' '\(pub)' >> ~/.ssh/authorized_keys",
            panelRepoDir: "/opt/pve-panel"
        )
    }
}
