import CryptoKit
import Foundation
import Network
import Observation

public enum PairingCryptoError: LocalizedError, Sendable, Equatable {
    case invalidPIN
    case invalidPublicKey
    case invalidCiphertext
    case decryptionFailed
    case localConnectionFailed(String)
    case relayUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidPIN:
            return "Le code PIN à 6 chiffres est invalide."
        case .invalidPublicKey:
            return "La clé publique ECDH reçue est invalide."
        case .invalidCiphertext:
            return "Les données chiffrées d'appairage sont malformées."
        case .decryptionFailed:
            return "Déchiffrement impossible. Vérifiez que le code PIN à 6 chiffres est identique."
        case .localConnectionFailed(let detail):
            return "Connexion pair-à-pair locale impossible (\(detail))."
        case .relayUnavailable:
            return "Aucun appareil cible local ni relais HTTPS configuré."
        }
    }
}

public enum PairingTransportMode: String, Sendable, Equatable {
    case localBonjour
    case httpsRelay
    case hybrid

    public var label: String {
        switch self {
        case .localBonjour: "Bonjour local (_pvepair._tcp)"
        case .httpsRelay: "Relais HTTPS chiffré"
        case .hybrid: "Bonjour + Relais HTTPS"
        }
    }
}

public enum PairingRoleState: Sendable, Equatable {
    case idle
    case advertising(pin: String, transport: PairingTransportMode, expiresAt: Date?)
    case connecting
    case encrypting
    case waitingForAck
    case completed(PairingTransferPayload)
    case sentSuccess(targetDevice: String, transport: PairingTransportMode)
    case failed(String)
}

// MARK: - Pure CryptoKit Engine (ECDH P-256 + HKDF-SHA256 + AES-256-GCM)

public enum PairingCryptoEngine {
    public static func generatePrivateKey() -> P256.KeyAgreement.PrivateKey {
        P256.KeyAgreement.PrivateKey()
    }

    public static func publicKeyBase64(from privateKey: P256.KeyAgreement.PrivateKey) -> String {
        privateKey.publicKey.x963Representation.base64EncodedString()
    }

    public static func decodePublicKey(base64: String) throws -> P256.KeyAgreement.PublicKey {
        guard let data = Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw PairingCryptoError.invalidPublicKey
        }
        if let x963 = try? P256.KeyAgreement.PublicKey(x963Representation: data) {
            return x963
        }
        if let raw = try? P256.KeyAgreement.PublicKey(rawRepresentation: data) {
            return raw
        }
        throw PairingCryptoError.invalidPublicKey
    }

    public static func normalizePIN(_ rawPIN: String) throws -> String {
        let digits = rawPIN.filter(\.isNumber)
        guard digits.count == 6 else {
            throw PairingCryptoError.invalidPIN
        }
        return digits
    }

    public static func deriveSymmetricKey(
        privateKey: P256.KeyAgreement.PrivateKey,
        peerPublicKey: P256.KeyAgreement.PublicKey,
        pin: String
    ) throws -> SymmetricKey {
        let normalizedPIN = try normalizePIN(pin)
        let pinData = Data(normalizedPIN.utf8)
        let salt = Data("pvecenter-pairing-salt-v1:".utf8) + pinData
        let info = Data("pvecenter-pairing-aes256gcm-v1:".utf8) + pinData

        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: info,
            outputByteCount: 32
        )
    }

    public static func encrypt(
        payload: PairingTransferPayload,
        receiverPublicKeyBase64: String,
        pin: String
    ) throws -> EncryptedPairingBundle {
        let receiverKey = try decodePublicKey(base64: receiverPublicKeyBase64)
        let ephemeralSenderKey = generatePrivateKey()
        let symmetricKey = try deriveSymmetricKey(
            privateKey: ephemeralSenderKey,
            peerPublicKey: receiverKey,
            pin: pin
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let plaintext = try encoder.encode(payload)

        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey)
        return EncryptedPairingBundle(
            senderPublicKey: publicKeyBase64(from: ephemeralSenderKey),
            nonce: Data(sealedBox.nonce).base64EncodedString(),
            ciphertext: sealedBox.ciphertext.base64EncodedString(),
            tag: sealedBox.tag.base64EncodedString()
        )
    }

    public static func decrypt(
        bundle: EncryptedPairingBundle,
        receiverPrivateKey: P256.KeyAgreement.PrivateKey,
        pin: String
    ) throws -> PairingTransferPayload {
        let senderKey = try decodePublicKey(base64: bundle.senderPublicKey)
        let symmetricKey = try deriveSymmetricKey(
            privateKey: receiverPrivateKey,
            peerPublicKey: senderKey,
            pin: pin
        )

        guard let nonceData = Data(base64Encoded: bundle.nonce),
              let ciphertextData = Data(base64Encoded: bundle.ciphertext),
              let tagData = Data(base64Encoded: bundle.tag),
              let nonce = try? AES.GCM.Nonce(data: nonceData) else {
            throw PairingCryptoError.invalidCiphertext
        }

        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: ciphertextData,
                tag: tagData
            )
        } catch {
            throw PairingCryptoError.invalidCiphertext
        }

        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(sealedBox, using: symmetricKey)
        } catch {
            throw PairingCryptoError.decryptionFailed
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(PairingTransferPayload.self, from: plaintext)
        } catch {
            throw PairingCryptoError.invalidCiphertext
        }
    }
}

// MARK: - Observable Sender & Receiver State Machine

/// Manages end-to-end encrypted iPhone <-> Apple TV pairing over both:
/// 1) Local Bonjour peer-to-peer (`_pvepair._tcp` via `NWListener` / `NWConnection`)
/// 2) HTTPS relay fallback (`/api/pairing/sessions`) for cross-VLAN or Tailscale setups.
@Observable
@MainActor
public final class PairingCryptoService {
    public private(set) var receiverState: PairingRoleState = .idle
    public private(set) var senderState: PairingRoleState = .idle
    public private(set) var activePIN: String?
    public private(set) var expiresAt: Date?
    public private(set) var receivedPayload: PairingTransferPayload?
    public private(set) var lastError: String?

    private let listenerCoordinator = LocalPairingListenerCoordinator()
    private var receiverPrivateKey: P256.KeyAgreement.PrivateKey?
    private var relayPollTask: Task<Void, Never>?
    private var activeRelayBaseURL: String?
    private var activeAPIClient: APIClient?

    public init() {}

    // MARK: - Receiver (Apple TV / Receiving Device)

    public func startReceiver(
        deviceName: String,
        relayBaseURL: String? = nil,
        apiClient: APIClient? = nil
    ) async {
        stopReceiver()
        lastError = nil
        receivedPayload = nil

        let privateKey = PairingCryptoEngine.generatePrivateKey()
        let publicKeyB64 = PairingCryptoEngine.publicKeyBase64(from: privateKey)
        self.receiverPrivateKey = privateKey

        var resolvedPIN = String(format: "%06d", Int.random(in: 0...999_999))
        var resolvedExpiry: Date? = Date().addingTimeInterval(300)
        var transportMode: PairingTransportMode = .localBonjour

        let normalizedRelay = APIClient.normalizeBaseURL(relayBaseURL ?? "")
        if !normalizedRelay.isEmpty, let apiClient {
            do {
                let session = try await apiClient.createPairingSession(
                    baseURL: normalizedRelay,
                    publicKey: publicKeyB64,
                    deviceName: deviceName
                )
                if let validPIN = try? PairingCryptoEngine.normalizePIN(session.pin) {
                    resolvedPIN = validPIN
                }
                if let parsedExpiry = Self.parseISO8601(session.expiresAt) {
                    resolvedExpiry = parsedExpiry
                }
                transportMode = .hybrid
                activeRelayBaseURL = normalizedRelay
                activeAPIClient = apiClient
                startRelayPolling(pin: resolvedPIN, baseURL: normalizedRelay, apiClient: apiClient)
            } catch {
                // Relay unreachable: keep local Bonjour listener active seamlessly.
                transportMode = .localBonjour
            }
        }

        activePIN = resolvedPIN
        expiresAt = resolvedExpiry
        receiverState = .advertising(pin: resolvedPIN, transport: transportMode, expiresAt: resolvedExpiry)

        let expectedPIN = resolvedPIN
        listenerCoordinator.start(
            serviceName: deviceName,
            publicKeyBase64: publicKeyB64,
            onBundleReceived: { [weak self] bundle in
                await self?.processReceivedBundle(bundle, pin: expectedPIN, expectedKey: privateKey)
                    ?? (false, "Session d'appairage expirée.")
            },
            onListenerError: { [weak self] errorMsg in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if case .completed = self.receiverState { return }
                    // Only fail if no relay fallback is active.
                    if self.relayPollTask == nil {
                        self.lastError = errorMsg
                        self.receiverState = .failed(errorMsg)
                    }
                }
            }
        )
    }

    public func stopReceiver() {
        relayPollTask?.cancel()
        relayPollTask = nil
        listenerCoordinator.stop()
        activeRelayBaseURL = nil
        activeAPIClient = nil
        receiverPrivateKey = nil
        activePIN = nil
        expiresAt = nil
        if case .completed = receiverState {
            return
        }
        receiverState = .idle
    }

    public func resetReceiver() {
        receivedPayload = nil
        lastError = nil
        stopReceiver()
        receiverState = .idle
    }

    /// Invoked when `RealtimeEventsClient` receives a `pairing_completed` event matching `activePIN`.
    public func handleRealtimePairingCompleted(pin: String?) async {
        guard let activePIN,
              pin == nil || pin == activePIN,
              let relayURL = activeRelayBaseURL,
              let apiClient = activeAPIClient else {
            return
        }
        await fetchAndDecryptRelayPayloadOnce(pin: activePIN, baseURL: relayURL, apiClient: apiClient)
    }

    private func startRelayPolling(pin: String, baseURL: String, apiClient: APIClient) {
        relayPollTask?.cancel()
        relayPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, !Task.isCancelled else { break }
                if let exp = self.expiresAt, Date() >= exp {
                    self.receiverState = .failed("Code PIN expiré (5 min). Générez un nouveau code.")
                    self.stopReceiver()
                    break
                }
                let done = await self.fetchAndDecryptRelayPayloadOnce(pin: pin, baseURL: baseURL, apiClient: apiClient)
                if done { break }
            }
        }
    }

    @discardableResult
    private func fetchAndDecryptRelayPayloadOnce(
        pin: String,
        baseURL: String,
        apiClient: APIClient
    ) async -> Bool {
        guard let receiverPrivateKey else { return false }
        do {
            guard let bundle = try await apiClient.fetchPairingPayload(baseURL: baseURL, pin: pin) else {
                return false
            }
            let payload = try PairingCryptoEngine.decrypt(
                bundle: bundle,
                receiverPrivateKey: receiverPrivateKey,
                pin: pin
            )
            completeReceiver(with: payload)
            return true
        } catch let error as PairingCryptoError {
            lastError = error.localizedDescription
            return false
        } catch {
            return false
        }
    }

    @MainActor
    private func processReceivedBundle(
        _ bundle: EncryptedPairingBundle,
        pin: String,
        expectedKey: P256.KeyAgreement.PrivateKey
    ) -> (Bool, String) {
        do {
            let payload = try PairingCryptoEngine.decrypt(
                bundle: bundle,
                receiverPrivateKey: expectedKey,
                pin: pin
            )
            completeReceiver(with: payload)
            return (true, "Configuration reçue et déchiffrée.")
        } catch {
            let msg = error.localizedDescription
            lastError = msg
            return (false, msg)
        }
    }

    private func completeReceiver(with payload: PairingTransferPayload) {
        receivedPayload = payload
        lastError = nil
        receiverState = .completed(payload)
        relayPollTask?.cancel()
        relayPollTask = nil
        listenerCoordinator.stop()
    }

    // MARK: - Sender (iPhone / Mac)

    public func resetSender() {
        senderState = .idle
        lastError = nil
    }

    @discardableResult
    public func sendPairingPayload(
        _ payload: PairingTransferPayload,
        pin: String,
        localTarget: DiscoveryServerItem? = nil,
        relayBaseURL: String? = nil,
        apiClient: APIClient
    ) async -> Bool {
        lastError = nil
        let normalizedPIN: String
        do {
            normalizedPIN = try PairingCryptoEngine.normalizePIN(pin)
        } catch {
            let msg = error.localizedDescription
            lastError = msg
            senderState = .failed(msg)
            return false
        }

        // 1) Prefer local peer-to-peer Bonjour (_pvepair._tcp) when target is selected.
        if let localTarget {
            do {
                try await sendViaLocalBonjour(payload, pin: normalizedPIN, target: localTarget)
                return true
            } catch {
                // Fall back to HTTPS relay if configured.
                let normalizedRelay = APIClient.normalizeBaseURL(relayBaseURL ?? "")
                if normalizedRelay.isEmpty {
                    lastError = error.localizedDescription
                    senderState = .failed(error.localizedDescription)
                    return false
                }
            }
        }

        // 2) HTTPS Relay fallback (/api/pairing/sessions/{pin}).
        let normalizedRelay = APIClient.normalizeBaseURL(relayBaseURL ?? "")
        guard !normalizedRelay.isEmpty else {
            let msg = PairingCryptoError.relayUnavailable.localizedDescription
            lastError = msg
            senderState = .failed(msg)
            return false
        }

        do {
            try await sendViaRelay(payload, pin: normalizedPIN, relayBaseURL: normalizedRelay, apiClient: apiClient)
            return true
        } catch {
            lastError = error.localizedDescription
            senderState = .failed(error.localizedDescription)
            return false
        }
    }

    public func sendViaLocalBonjour(
        _ payload: PairingTransferPayload,
        pin: String,
        target: DiscoveryServerItem
    ) async throws {
        let normalizedPIN = try PairingCryptoEngine.normalizePIN(pin)
        senderState = .connecting

        let senderClient = LocalPairingSenderClient()
        let endpoint: NWEndpoint
        if !target.host.isEmpty && !target.host.hasSuffix(".local") && target.port > 0,
           let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: target.port)) {
            endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(target.host), port: nwPort)
        } else {
            endpoint = NWEndpoint.service(
                name: target.name,
                type: BonjourDiscoveryService.pairingServiceType,
                domain: "local.",
                interface: nil
            )
        }

        let hello = try await senderClient.connectAndReadHello(endpoint: endpoint)
        senderState = .encrypting

        let bundle = try PairingCryptoEngine.encrypt(
            payload: payload,
            receiverPublicKeyBase64: hello.publicKey,
            pin: normalizedPIN
        )

        senderState = .waitingForAck
        let ack = try await senderClient.sendBundleAndAwaitAck(bundle)
        guard ack.ok else {
            throw PairingCryptoError.localConnectionFailed(ack.message)
        }

        senderState = .sentSuccess(
            targetDevice: hello.deviceName.isEmpty ? target.name : hello.deviceName,
            transport: .localBonjour
        )
    }

    public func sendViaRelay(
        _ payload: PairingTransferPayload,
        pin: String,
        relayBaseURL: String,
        apiClient: APIClient
    ) async throws {
        let normalizedPIN = try PairingCryptoEngine.normalizePIN(pin)
        senderState = .connecting

        let sessionInfo = try await apiClient.fetchPairingSession(baseURL: relayBaseURL, pin: normalizedPIN)
        senderState = .encrypting

        let bundle = try PairingCryptoEngine.encrypt(
            payload: payload,
            receiverPublicKeyBase64: sessionInfo.publicKey,
            pin: normalizedPIN
        )

        senderState = .waitingForAck
        try await apiClient.completePairingSession(baseURL: relayBaseURL, pin: normalizedPIN, payload: bundle)
        senderState = .sentSuccess(targetDevice: sessionInfo.deviceName, transport: .httpsRelay)
    }

    // MARK: - Date Helper

    private static func parseISO8601(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}

// MARK: - Local Wire Framing & Queue-Confined NWListener / NWConnection

private struct LocalPairingWireMessage: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case hello
        case bundle
        case ack
    }

    let kind: Kind
    var deviceName: String?
    var publicKey: String?
    var bundle: EncryptedPairingBundle?
    var ok: Bool?
    var message: String?
}

private enum LocalWireCodec {
    static let maxFrameSize = 1_048_576

    static func encodeFrame(_ message: LocalPairingWireMessage) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = try encoder.encode(message)
        var length = UInt32(json.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(json)
        return frame
    }

    static func decodeMessage(_ data: Data) throws -> LocalPairingWireMessage {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(LocalPairingWireMessage.self, from: data)
    }

    static func readFrame(from connection: NWConnection, completion: @escaping @Sendable (Result<LocalPairingWireMessage, Error>) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { headerData, _, isComplete, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let headerData, headerData.count == 4 else {
                let errMsg = isComplete ? "Connexion fermée prématurément." : "En-tête de trame invalide."
                completion(.failure(PairingCryptoError.localConnectionFailed(errMsg)))
                return
            }
            let length = headerData.withUnsafeBytes { rawPtr -> Int in
                let value = rawPtr.loadUnaligned(as: UInt32.self)
                return Int(UInt32(bigEndian: value))
            }
            guard length > 0 && length <= maxFrameSize else {
                completion(.failure(PairingCryptoError.localConnectionFailed("Taille de trame invalide (\(length)).")))
                return
            }

            connection.receive(minimumIncompleteLength: length, maximumLength: length) { bodyData, _, _, bodyError in
                if let bodyError {
                    completion(.failure(bodyError))
                    return
                }
                guard let bodyData, bodyData.count == length else {
                    completion(.failure(PairingCryptoError.localConnectionFailed("Corps de trame incomplet.")))
                    return
                }
                do {
                    let msg = try decodeMessage(bodyData)
                    completion(.success(msg))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }
}

private final class LocalPairingListenerCoordinator: @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.ac.pvepanel.pairing.listener")
    private var listener: NWListener?
    private var activeConnections: [ObjectIdentifier: NWConnection] = [:]

    func start(
        serviceName: String,
        publicKeyBase64: String,
        onBundleReceived: @escaping @Sendable (EncryptedPairingBundle) async -> (Bool, String),
        onListenerError: @escaping @Sendable (String) -> Void
    ) {
        queue.async { [weak self] in
            self?.stopOnQueue()
            guard let self else { return }

            let params = NWParameters.tcp
            params.includePeerToPeer = true

            do {
                let nwListener = try NWListener(using: params)
                let txt = NWTXTRecord([
                    "pk": publicKeyBase64,
                    "name": serviceName,
                    "proto": "v1",
                ])
                nwListener.service = NWListener.Service(
                    name: serviceName,
                    type: BonjourDiscoveryService.pairingServiceType,
                    domain: "local.",
                    txtRecord: txt
                )

                nwListener.stateUpdateHandler = { state in
                    if case .failed(let error) = state {
                        onListenerError("Serveur Bonjour d'appairage indisponible (\(error.localizedDescription)).")
                    }
                }

                nwListener.newConnectionHandler = { [weak self] connection in
                    self?.handleAcceptedConnection(
                        connection,
                        deviceName: serviceName,
                        publicKeyBase64: publicKeyBase64,
                        onBundleReceived: onBundleReceived
                    )
                }

                nwListener.start(queue: self.queue)
                self.listener = nwListener
            } catch {
                onListenerError("Impossible de démarrer l'écoute Bonjour (\(error.localizedDescription)).")
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    private func stopOnQueue() {
        listener?.cancel()
        listener = nil
        for conn in activeConnections.values {
            conn.cancel()
        }
        activeConnections.removeAll()
    }

    private func handleAcceptedConnection(
        _ connection: NWConnection,
        deviceName: String,
        publicKeyBase64: String,
        onBundleReceived: @escaping @Sendable (EncryptedPairingBundle) async -> (Bool, String)
    ) {
        let connID = ObjectIdentifier(connection)
        activeConnections[connID] = connection
        let workQueue = queue

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                let hello = LocalPairingWireMessage(
                    kind: .hello,
                    deviceName: deviceName,
                    publicKey: publicKeyBase64
                )
                guard let frame = try? LocalWireCodec.encodeFrame(hello) else {
                    connection.cancel()
                    return
                }
                connection.send(content: frame, completion: .contentProcessed { sendErr in
                    if sendErr != nil {
                        connection.cancel()
                        return
                    }
                    LocalWireCodec.readFrame(from: connection) { result in
                        switch result {
                        case .success(let msg) where msg.kind == .bundle:
                            guard let bundle = msg.bundle else {
                                connection.cancel()
                                return
                            }
                            Task {
                                let (ok, ackMsg) = await onBundleReceived(bundle)
                                let ack = LocalPairingWireMessage(kind: .ack, ok: ok, message: ackMsg)
                                if let ackData = try? LocalWireCodec.encodeFrame(ack) {
                                    connection.send(content: ackData, completion: .contentProcessed { _ in
                                        connection.cancel()
                                    })
                                } else {
                                    connection.cancel()
                                }
                            }
                        default:
                            connection.cancel()
                        }
                    }
                })
            case .failed, .cancelled:
                workQueue.async { [weak self] in
                    self?.activeConnections.removeValue(forKey: connID)
                }
            default:
                break
            }
        }

        connection.start(queue: workQueue)
    }
}

private final class LocalPairingSenderClient: @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.ac.pvepanel.pairing.sender")
    private var connection: NWConnection?

    deinit {
        connection?.cancel()
    }

    func connectAndReadHello(endpoint: NWEndpoint) async throws -> (deviceName: String, publicKey: String) {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: PairingCryptoError.localConnectionFailed("Annulé."))
                    return
                }
                let params = NWParameters.tcp
                params.includePeerToPeer = true
                let conn = NWConnection(to: endpoint, using: params)
                self.connection = conn

                let resumed = LockedFlag()

                self.queue.asyncAfter(deadline: .now() + 5.0) {
                    if resumed.tryFlip() {
                        conn.cancel()
                        continuation.resume(throwing: PairingCryptoError.localConnectionFailed("Délai dépassé."))
                    }
                }

                conn.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        LocalWireCodec.readFrame(from: conn) { result in
                            guard resumed.tryFlip() else { return }
                            switch result {
                            case .success(let msg) where msg.kind == .hello:
                                continuation.resume(returning: (msg.deviceName ?? "Apple TV", msg.publicKey ?? ""))
                            case .success:
                                continuation.resume(throwing: PairingCryptoError.localConnectionFailed("Réponse inattendue."))
                            case .failure(let err):
                                continuation.resume(throwing: PairingCryptoError.localConnectionFailed(err.localizedDescription))
                            }
                        }
                    case .failed(let err):
                        if resumed.tryFlip() {
                            continuation.resume(throwing: PairingCryptoError.localConnectionFailed(err.localizedDescription))
                        }
                    case .cancelled:
                        if resumed.tryFlip() {
                            continuation.resume(throwing: PairingCryptoError.localConnectionFailed("Connexion annulée."))
                        }
                    default:
                        break
                    }
                }

                conn.start(queue: self.queue)
            }
        }
    }

    func sendBundleAndAwaitAck(_ bundle: EncryptedPairingBundle) async throws -> (ok: Bool, message: String) {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self, let conn = self.connection else {
                    continuation.resume(throwing: PairingCryptoError.localConnectionFailed("Connexion fermée."))
                    return
                }
                let msg = LocalPairingWireMessage(kind: .bundle, bundle: bundle)
                guard let frame = try? LocalWireCodec.encodeFrame(msg) else {
                    continuation.resume(throwing: PairingCryptoError.localConnectionFailed("Encodage impossible."))
                    return
                }
                let resumed = LockedFlag()
                conn.send(content: frame, completion: .contentProcessed { sendErr in
                    if let sendErr {
                        if resumed.tryFlip() {
                            conn.cancel()
                            continuation.resume(throwing: PairingCryptoError.localConnectionFailed(sendErr.localizedDescription))
                        }
                        return
                    }
                    LocalWireCodec.readFrame(from: conn) { result in
                        guard resumed.tryFlip() else { return }
                        conn.cancel()
                        switch result {
                        case .success(let ack) where ack.kind == .ack:
                            continuation.resume(returning: (ack.ok ?? false, ack.message ?? ""))
                        case .success:
                            continuation.resume(throwing: PairingCryptoError.localConnectionFailed("Accusé invalide."))
                        case .failure(let err):
                            continuation.resume(throwing: PairingCryptoError.localConnectionFailed(err.localizedDescription))
                        }
                    }
                })
            }
        }
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flipped = false

    func tryFlip() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if flipped { return false }
        flipped = true
        return true
    }
}
