import Foundation
import Network
import Observation

/// Bonjour / mDNS service discovery powered by Apple `Network.framework` (`NWBrowser` + `NWConnection`).
/// Works uniformly on iOS, macOS, and tvOS under Swift 6 strict concurrency.
@Observable
@MainActor
public final class BonjourDiscoveryService {
    public nonisolated static let pveServiceType = "_pvecenter._tcp"
    public nonisolated static let pairingServiceType = "_pvepair._tcp"
    public nonisolated static let optionalLANServiceTypes = [
        "_pvecenter._tcp",
        "_http._tcp",
        "_ssh._tcp",
        "_smb._tcp",
    ]

    public private(set) var pveServers: [DiscoveryServerItem] = []
    public private(set) var pairingReceivers: [DiscoveryServerItem] = []
    public private(set) var lanServices: [DiscoveryServerItem] = []
    public private(set) var isScanningPVE: Bool = false
    public private(set) var isScanningPairing: Bool = false
    public private(set) var isScanningLAN: Bool = false
    public private(set) var lastError: String?

    private let coordinator = BonjourBrowserCoordinator()
    private var lanScanTask: Task<Void, Never>?

    public init() {}

    public var allDiscoveredServers: [DiscoveryServerItem] {
        pveServers
    }

    // MARK: - PVE Center Discovery (_pvecenter._tcp)

    public func startPVEDiscovery() {
        isScanningPVE = true
        lastError = nil
        coordinator.startBrowsing(
            key: "pve",
            serviceTypes: [Self.pveServiceType],
            onUpdate: { [weak self] items in
                Task { @MainActor [weak self] in
                    self?.pveServers = items
                }
            },
            onError: { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.lastError = message
                    self?.isScanningPVE = false
                }
            }
        )
    }

    public func stopPVEDiscovery() {
        coordinator.stopBrowsing(key: "pve")
        isScanningPVE = false
    }

    // MARK: - Apple TV Pairing Discovery (_pvepair._tcp)

    public func startPairingDiscovery() {
        isScanningPairing = true
        lastError = nil
        coordinator.startBrowsing(
            key: "pairing",
            serviceTypes: [Self.pairingServiceType],
            onUpdate: { [weak self] items in
                Task { @MainActor [weak self] in
                    self?.pairingReceivers = items
                }
            },
            onError: { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.lastError = message
                    self?.isScanningPairing = false
                }
            }
        )
    }

    public func stopPairingDiscovery() {
        coordinator.stopBrowsing(key: "pairing")
        isScanningPairing = false
    }

    // MARK: - Bounded LAN Scan (_http._tcp, _ssh._tcp, _smb._tcp, _pvecenter._tcp)

    @discardableResult
    public func scanLANServices(timeoutSeconds: TimeInterval = 3.0) async -> [DiscoveryServerItem] {
        lanScanTask?.cancel()
        isScanningLAN = true
        lastError = nil

        coordinator.startBrowsing(
            key: "lan",
            serviceTypes: Self.optionalLANServiceTypes,
            onUpdate: { [weak self] items in
                Task { @MainActor [weak self] in
                    self?.lanServices = items
                }
            },
            onError: { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.lastError = message
                }
            }
        )

        let clamped = max(0.8, min(timeoutSeconds, 10.0))
        try? await Task.sleep(for: .seconds(clamped))

        coordinator.stopBrowsing(key: "lan")
        isScanningLAN = false
        return lanServices
    }

    public func stopAll() {
        lanScanTask?.cancel()
        coordinator.stopAll()
        isScanningPVE = false
        isScanningPairing = false
        isScanningLAN = false
    }
}

// MARK: - Queue-Confined NWBrowser + NWConnection Coordinator

/// Confines all non-Sendable `Network.framework` objects onto a single serial `DispatchQueue`
/// and emits only `Sendable` `DiscoveryServerItem` snapshots outward.
private final class BonjourBrowserCoordinator: @unchecked Sendable {
    private struct BrowserSlot {
        let browsers: [NWBrowser]
        var itemsByID: [String: DiscoveryServerItem]
        var resolvers: [String: NWConnection]
        let onUpdate: @Sendable ([DiscoveryServerItem]) -> Void
        let onError: @Sendable (String) -> Void
    }

    private let queue = DispatchQueue(label: "io.ac.pvepanel.bonjour.coordinator")
    private var slots: [String: BrowserSlot] = [:]

    func startBrowsing(
        key: String,
        serviceTypes: [String],
        onUpdate: @escaping @Sendable ([DiscoveryServerItem]) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopBrowsingOnQueue(key: key)

            var browsers: [NWBrowser] = []
            for serviceType in serviceTypes {
                let params = NWParameters.tcp
                params.includePeerToPeer = true
                let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: serviceType, domain: "local.")
                let browser = NWBrowser(for: descriptor, using: params)

                browser.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .failed(let error):
                        onError("Découverte Bonjour interrompue (\(error.localizedDescription)).")
                    case .waiting(let error):
                        onError("En attente du réseau local (\(error.localizedDescription)).")
                    default:
                        break
                    }
                    _ = self
                }

                browser.browseResultsChangedHandler = { [weak self] results, _ in
                    self?.handleResults(results, serviceType: serviceType, slotKey: key)
                }

                browser.start(queue: self.queue)
                browsers.append(browser)
            }

            self.slots[key] = BrowserSlot(
                browsers: browsers,
                itemsByID: [:],
                resolvers: [:],
                onUpdate: onUpdate,
                onError: onError
            )
        }
    }

    func stopBrowsing(key: String) {
        queue.async { [weak self] in
            self?.stopBrowsingOnQueue(key: key)
        }
    }

    func stopAll() {
        queue.async { [weak self] in
            guard let self else { return }
            for key in Array(self.slots.keys) {
                self.stopBrowsingOnQueue(key: key)
            }
        }
    }

    private func stopBrowsingOnQueue(key: String) {
        guard let existing = slots.removeValue(forKey: key) else { return }
        for browser in existing.browsers {
            browser.cancel()
        }
        for resolver in existing.resolvers.values {
            resolver.cancel()
        }
    }

    private func handleResults(_ results: Set<NWBrowser.Result>, serviceType: String, slotKey: String) {
        guard var slot = slots[slotKey] else { return }

        // Remove stale entries belonging to this serviceType.
        let activeIDs = Set(results.compactMap { result -> String? in
            guard case .service(let name, let type, let domain, _) = result.endpoint else { return nil }
            return "\(type)|\(domain)|\(name)"
        })

        for (itemID, existingItem) in slot.itemsByID where existingItem.serviceType == serviceType && !activeIDs.contains(itemID) {
            slot.itemsByID.removeValue(forKey: itemID)
            slot.resolvers.removeValue(forKey: itemID)?.cancel()
        }

        for result in results {
            guard case .service(let rawName, let rawType, let domain, _) = result.endpoint else {
                continue
            }

            let itemID = "\(rawType)|\(domain)|\(rawName)"
            let txtMap = extractTXTDictionary(from: result.metadata)
            let displayName = (txtMap["name"]?.isEmpty == false) ? (txtMap["name"] ?? rawName) : rawName
            let portFromTXT = txtMap["port"].flatMap(Int.init) ?? Self.defaultPort(for: rawType)
            let httpsFlag = Self.parseBool(txtMap["https"]) ?? (portFromTXT == 443)
            let publicURL = (txtMap["public_url"]?.isEmpty == false) ? txtMap["public_url"] : nil
            let version = (txtMap["version"]?.isEmpty == false) ? txtMap["version"] : nil
            let existingHost = slot.itemsByID[itemID]?.host ?? ""
            let existingPort = slot.itemsByID[itemID]?.port ?? portFromTXT

            let item = DiscoveryServerItem(
                id: txtMap["id"]?.isEmpty == false ? (txtMap["id"] ?? itemID) : itemID,
                name: displayName,
                serviceType: rawType,
                host: existingHost.isEmpty ? "\(Self.sanitizeHostComponent(rawName)).local" : existingHost,
                port: existingPort,
                isHttps: httpsFlag,
                publicUrl: publicURL,
                version: version,
                txt: txtMap,
                suggestedProtocol: Self.suggestedProtocol(for: rawType),
                isLocalBonjour: true
            )
            slot.itemsByID[itemID] = item

            // Resolve actual LAN IP + port via short-lived NWConnection if not already resolved.
            if existingHost.isEmpty && slot.resolvers[itemID] == nil {
                let conn = startEndpointResolution(
                    endpoint: result.endpoint,
                    itemID: itemID,
                    slotKey: slotKey
                )
                slot.resolvers[itemID] = conn
            }
        }

        slots[slotKey] = slot
        emitSortedItems(for: slot)
    }

    private func startEndpointResolution(
        endpoint: NWEndpoint,
        itemID: String,
        slotKey: String
    ) -> NWConnection {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let connection = NWConnection(to: endpoint, using: params)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                if case .hostPort(let host, let port)? = connection.currentPath?.remoteEndpoint {
                    let resolvedHost = Self.formatHost(host)
                    let resolvedPort = Int(port.rawValue)
                    self.updateResolvedEndpoint(
                        slotKey: slotKey,
                        itemID: itemID,
                        host: resolvedHost,
                        port: resolvedPort
                    )
                }
                connection.cancel()
            case .failed, .cancelled:
                self.clearResolver(slotKey: slotKey, itemID: itemID)
            default:
                break
            }
        }

        connection.start(queue: queue)

        // Bound resolution attempts to 3 seconds so unreachable ports don't linger.
        queue.asyncAfter(deadline: .now() + 3.0) { [weak self, weak connection] in
            connection?.cancel()
            self?.clearResolver(slotKey: slotKey, itemID: itemID)
        }

        return connection
    }

    private func updateResolvedEndpoint(slotKey: String, itemID: String, host: String, port: Int) {
        guard var slot = slots[slotKey], var item = slot.itemsByID[itemID] else { return }
        if !host.isEmpty {
            item.host = host
        }
        if port > 0 && item.txt["port"] == nil {
            item.port = port
        }
        slot.itemsByID[itemID] = item
        slot.resolvers.removeValue(forKey: itemID)
        slots[slotKey] = slot
        emitSortedItems(for: slot)
    }

    private func clearResolver(slotKey: String, itemID: String) {
        guard var slot = slots[slotKey] else { return }
        slot.resolvers.removeValue(forKey: itemID)
        slots[slotKey] = slot
    }

    private func emitSortedItems(for slot: BrowserSlot) {
        let sorted = slot.itemsByID.values.sorted { lhs, rhs in
            if lhs.isPVECenterServer != rhs.isPVECenterServer {
                return lhs.isPVECenterServer
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        slot.onUpdate(sorted)
    }

    private func extractTXTDictionary(from metadata: NWBrowser.Result.Metadata) -> [String: String] {
        guard case let .bonjour(record) = metadata else {
            return [:]
        }
        return record.dictionary
    }

    private static func formatHost(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let address):
            let bytes = Array(address.rawValue)
            if bytes.count == 4 {
                return "\(bytes[0]).\(bytes[1]).\(bytes[2]).\(bytes[3])"
            }
            return address.debugDescription
        case .ipv6(let address):
            return address.debugDescription.split(separator: "%").first.map(String.init) ?? address.debugDescription
        case .name(let hostname, _):
            return hostname
        @unknown default:
            return ""
        }
    }

    private static func defaultPort(for serviceType: String) -> Int {
        let lower = serviceType.lowercased()
        if lower.contains("_ssh._tcp") { return 22 }
        if lower.contains("_smb._tcp") { return 445 }
        if lower.contains("_pvecenter._tcp") { return 8000 }
        return 80
    }

    private static func suggestedProtocol(for serviceType: String) -> CustomServiceProtocol {
        let lower = serviceType.lowercased()
        if lower.contains("_ssh._tcp") || lower.contains("_smb._tcp") {
            return .tcpPort
        }
        return .httpRest
    }

    private static func parseBool(_ raw: String?) -> Bool? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on": return true
        case "0", "false", "no", "off": return false
        default: return nil
        }
    }

    private static func sanitizeHostComponent(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }
}
