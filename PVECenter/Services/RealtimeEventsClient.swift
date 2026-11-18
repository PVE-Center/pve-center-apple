import Foundation
import Observation

public enum RealtimeConnectionState: String, Sendable, Equatable {
    case disconnected
    case connecting
    case connectedWebSocket
    case connectedSSE
    case reconnecting

    public var label: String {
        switch self {
        case .disconnected: "Déconnecté"
        case .connecting: "Connexion…"
        case .connectedWebSocket: "WebSocket Live"
        case .connectedSSE: "SSE Live"
        case .reconnecting: "Reconnexion…"
        }
    }

    public var isConnected: Bool {
        self == .connectedWebSocket || self == .connectedSSE
    }
}

/// Real-time event client supporting WebSocket (`/api/ws/events`) with automatic
/// Server-Sent Events (`/api/events/stream`) fallback and exponential backoff reconnect.
@Observable
@MainActor
public final class RealtimeEventsClient {
    public private(set) var connectionState: RealtimeConnectionState = .disconnected
    public private(set) var lastEvent: RealtimeEventEnvelope?
    public private(set) var lastEventAt: Date?
    public private(set) var lastError: String?
    public private(set) var reconnectAttempt: Int = 0

    public var onEvent: (@MainActor (RealtimeEventEnvelope) -> Void)?

    private var connectionTask: Task<Void, Never>?
    private var activeBaseURL: String = ""
    private var activeToken: String?
    private let decoder: JSONDecoder

    public init() {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = dec
    }

    public func connect(baseURL: String, bearerToken: String?) {
        let normalized = APIClient.normalizeBaseURL(baseURL)
        guard !normalized.isEmpty else {
            disconnect()
            return
        }

        if connectionTask != nil && activeBaseURL == normalized && activeToken == bearerToken {
            return
        }

        disconnect()
        activeBaseURL = normalized
        activeToken = bearerToken
        reconnectAttempt = 0
        lastError = nil

        connectionTask = Task { [weak self] in
            await self?.runConnectionLoop(baseURL: normalized, bearerToken: bearerToken)
        }
    }

    public func disconnect() {
        connectionTask?.cancel()
        connectionTask = nil
        activeBaseURL = ""
        activeToken = nil
        reconnectAttempt = 0
        connectionState = .disconnected
    }

    // MARK: - Connection Loop & Backoff

    private func runConnectionLoop(baseURL: String, bearerToken: String?) async {
        var preferSSE = false

        while !Task.isCancelled {
            connectionState = reconnectAttempt == 0 ? .connecting : .reconnecting

            let connectedStart = Date()
            do {
                if !preferSSE {
                    try await streamViaWebSocket(baseURL: baseURL, bearerToken: bearerToken)
                } else {
                    try await streamViaSSE(baseURL: baseURL, bearerToken: bearerToken)
                }
            } catch is CancellationError {
                break
            } catch {
                lastError = error.localizedDescription
                // If WebSocket handshake or stream failed, immediately attempt SSE fallback.
                if !preferSSE && !Task.isCancelled {
                    preferSSE = true
                    do {
                        try await streamViaSSE(baseURL: baseURL, bearerToken: bearerToken)
                    } catch is CancellationError {
                        break
                    } catch {
                        lastError = error.localizedDescription
                    }
                }
            }

            if Task.isCancelled { break }

            // Reset backoff if previous session stayed connected for at least 10 seconds.
            if Date().timeIntervalSince(connectedStart) >= 10 {
                reconnectAttempt = 0
                preferSSE = false
            } else {
                reconnectAttempt += 1
                // Alternate back to WebSocket on even retries so WS recovers once network/proxy allows it.
                if reconnectAttempt % 2 == 0 {
                    preferSSE = false
                }
            }

            let delaySeconds = backoffDelay(attempt: reconnectAttempt)
            connectionState = .reconnecting
            try? await Task.sleep(for: .seconds(delaySeconds))
        }

        if Task.isCancelled {
            connectionState = .disconnected
        }
    }

    private func backoffDelay(attempt: Int) -> Double {
        let exponent = min(max(attempt - 1, 0), 5)
        let base = min(30.0, pow(2.0, Double(exponent)))
        let jitter = Double.random(in: 0.0...0.45)
        return base + jitter
    }

    // MARK: - WebSocket Transport

    private func streamViaWebSocket(baseURL: String, bearerToken: String?) async throws {
        guard let wsURL = buildEndpointURL(baseURL: baseURL, path: "/api/ws/events", webSocket: true, token: bearerToken) else {
            throw APIError.invalidBaseURL
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: wsURL)
        if let token = bearerToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let task = session.webSocketTask(with: request)
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }

        // Confirm initial receive or ping before marking connected.
        let pingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled else { break }
                try? await sendWebSocketPing(task)
            }
        }
        defer { pingTask.cancel() }

        connectionState = .connectedWebSocket
        lastError = nil

        while !Task.isCancelled {
            let message = try await task.receive()
            reconnectAttempt = 0

            switch message {
            case .string(let text):
                if text == "ping" {
                    try? await task.send(.string("{\"type\":\"pong\"}"))
                    continue
                }
                if let data = text.data(using: .utf8) {
                    try await handleIncomingJSONData(data, webSocketTask: task)
                }
            case .data(let data):
                try await handleIncomingJSONData(data, webSocketTask: task)
            @unknown default:
                break
            }
        }
    }

    private func sendWebSocketPing(_ task: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func handleIncomingJSONData(_ data: Data, webSocketTask: URLSessionWebSocketTask?) async throws {
        guard let envelope = try? decoder.decode(RealtimeEventEnvelope.self, from: data) else {
            return
        }
        if envelope.type.lowercased() == "ping" {
            try? await webSocketTask?.send(.string("{\"type\":\"pong\"}"))
            return
        }
        if envelope.type.lowercased() == "pong" || envelope.type.lowercased() == "heartbeat" {
            return
        }
        dispatch(envelope)
    }

    // MARK: - SSE Fallback Transport

    private func streamViaSSE(baseURL: String, bearerToken: String?) async throws {
        guard let sseURL = buildEndpointURL(baseURL: baseURL, path: "/api/events/stream", webSocket: false, token: bearerToken) else {
            throw APIError.invalidBaseURL
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: sseURL)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if let token = bearerToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transportError("Flux SSE invalide.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.serverError(statusCode: http.statusCode, detail: "Flux SSE refusé (HTTP \(http.statusCode)).")
        }

        connectionState = .connectedSSE
        lastError = nil
        reconnectAttempt = 0

        // Parse raw UTF-8 lines directly from bytes so blank event-delimiter lines are preserved.
        var lineBuffer = Data()
        var currentEventName: String?
        var dataLines: [String] = []

        func flushEventIfReady() {
            guard !dataLines.isEmpty else {
                currentEventName = nil
                return
            }
            let joined = dataLines.joined(separator: "\n")
            dataLines.removeAll()
            let eventHint = currentEventName
            currentEventName = nil

            guard let data = joined.data(using: .utf8) else { return }
            if let envelope = try? decoder.decode(RealtimeEventEnvelope.self, from: data) {
                if envelope.type == "ping" || envelope.type == "heartbeat" { return }
                dispatch(envelope)
            } else if let eventHint, eventHint != "ping", eventHint != "heartbeat" {
                let synthetic = RealtimeEventEnvelope(type: eventHint, timestamp: "", payload: [:])
                dispatch(synthetic)
            }
        }

        for try await byte in bytes {
            if Task.isCancelled { break }
            if byte == 0x0A { // '\n'
                let line = String(data: lineBuffer, encoding: .utf8)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\r")) ?? ""
                lineBuffer.removeAll(keepingCapacity: true)

                if line.isEmpty {
                    flushEventIfReady()
                } else if line.hasPrefix(":") {
                    continue
                } else if line.hasPrefix("event:") {
                    currentEventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("data:") {
                    let payloadPart = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    dataLines.append(payloadPart)
                }
            } else {
                lineBuffer.append(byte)
            }
        }

        flushEventIfReady()
    }

    // MARK: - Helpers

    private func dispatch(_ envelope: RealtimeEventEnvelope) {
        lastEvent = envelope
        lastEventAt = Date()
        onEvent?(envelope)
    }

    private func buildEndpointURL(baseURL: String, path: String, webSocket: Bool, token: String?) -> URL? {
        guard var components = URLComponents(string: "\(baseURL)\(path)") else {
            return nil
        }
        if webSocket {
            if components.scheme?.lowercased() == "https" {
                components.scheme = "wss"
            } else if components.scheme?.lowercased() == "http" {
                components.scheme = "ws"
            }
        }
        if let token, !token.isEmpty {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "token", value: token))
            components.queryItems = items
        }
        return components.url
    }
}
