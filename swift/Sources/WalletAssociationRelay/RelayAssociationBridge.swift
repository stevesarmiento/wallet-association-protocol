import CryptoKit
import Foundation
import WalletAssociationCore

public final class RelayAssociationBridge: @unchecked Sendable {
    private let connectionURI: AssociationConnectionURI
    private let configuration: RelayAssociationBridgeConfiguration
    private weak var delegate: AssociationBridgeDelegate?
    private let webSocketClient: RelayWebSocketClient
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var receiveTask: Task<Void, Never>?
    private var pendingHandshakes: [String: PendingHandshake] = [:]
    private var replayCache = AssociationReplayCache()

    public init(
        connectionURI: AssociationConnectionURI,
        configuration: RelayAssociationBridgeConfiguration = RelayAssociationBridgeConfiguration(),
        delegate: AssociationBridgeDelegate
    ) {
        self.connectionURI = connectionURI
        self.configuration = configuration
        self.delegate = delegate
        self.webSocketClient = URLSessionRelayWebSocketClient()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    init(
        connectionURI: AssociationConnectionURI,
        configuration: RelayAssociationBridgeConfiguration = RelayAssociationBridgeConfiguration(),
        delegate: AssociationBridgeDelegate,
        webSocketClient: RelayWebSocketClient
    ) {
        self.connectionURI = connectionURI
        self.configuration = configuration
        self.delegate = delegate
        self.webSocketClient = webSocketClient
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func start() async throws {
        try await webSocketClient.connect(url: walletSocketURL())
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    public func stop() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketClient.close()
        pendingHandshakes.removeAll()
        replayCache.removeAll()
    }

    public func sendEvent(
        _ event: AssociationSessionEventPayload,
        sessionId: String,
        origin: String
    ) async throws {
        guard let delegate else {
            throw WalletAssociationError.unavailable("relay unavailable")
        }
        let token = try await delegate.associationSessionToken(sessionId: sessionId, verifiedOrigin: origin).token
        let key = try AssociationCrypto.sessionKey(sessionToken: token, sessionId: sessionId, origin: origin)
        let sealed = try AssociationCrypto.seal(event, key: key, encoder: encoder)
        let envelope = AssociationEnvelope(protocolVersion: AssociationProtocol.version, keyId: sessionId, sealedBoxBase64: sealed)
        try await send([
            "kind": "wap_event",
            "id": UUID().uuidString,
            "body": try jsonObject(envelope)
        ])
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            do {
                let message = try await webSocketClient.receive()
                try await handle(message)
            } catch {
                if !Task.isCancelled {
                    stop()
                }
                return
            }
        }
    }

    func handleRelayFrameForTesting(_ string: String) async throws {
        try await handle(string)
    }

    private func handle(_ message: String) async throws {
        let data = Data(message.utf8)
        guard let frame = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = frame["kind"] as? String
        else {
            return
        }

        if kind == "ping" {
            try await send(["kind": "pong"])
            return
        }
        guard kind == "wap_request",
              let id = frame["id"] as? String,
              let operation = frame["operation"] as? String
        else {
            return
        }

        do {
            let body = try await responseBody(operation: operation, frame: frame)
            try await send(["kind": "wap_response", "id": id, "ok": true, "body": body])
        } catch {
            try await send(["kind": "wap_response", "id": id, "ok": false, "error": errorBody(error)])
        }
    }

    private func responseBody(operation: String, frame: [String: Any]) async throws -> Any {
        switch operation {
        case "discover":
            return try jsonObject(discoverResponse())
        case "handshake":
            let request = try decodeBody(AssociationHandshakeRequest.self, frame: frame)
            try validateProtocol(request.protocolVersion)
            if let metadataOrigin = request.metadata?.origin, metadataOrigin != connectionURI.origin {
                throw WalletAssociationError.invalidOrigin
            }
            return try jsonObject(handshake(request, origin: connectionURI.origin))
        case "associate":
            let envelope = try decodeBody(AssociationEnvelope.self, frame: frame)
            try validateProtocol(envelope.protocolVersion)
            return try jsonObject(try await associate(envelope, origin: connectionURI.origin))
        case "rpc":
            let envelope = try decodeBody(AssociationEnvelope.self, frame: frame)
            try validateProtocol(envelope.protocolVersion)
            return try jsonObject(try await rpc(envelope, origin: connectionURI.origin))
        default:
            throw WalletAssociationError.malformedRequest
        }
    }

    private func discoverResponse() -> AssociationDiscoverResponse {
        AssociationDiscoverResponse(
            name: configuration.walletName,
            version: configuration.walletVersion,
            protocolVersion: AssociationProtocol.version,
            transports: [AssociationTransportDescriptor(type: "relay", host: nil, port: nil)],
            chains: configuration.supportedChains,
            features: configuration.supportedFeatures,
            encryption: AssociationProtocol.encryption,
            sessionTokenTtlSeconds: configuration.sessionTokenTtlSeconds
        )
    }

    private func handshake(_ request: AssociationHandshakeRequest, origin: String) throws -> AssociationHandshakeResponse {
        _ = try AssociationCrypto.publicKey(fromBase64: request.dappPublicKeyBase64)
        let handshakeId = UUID().uuidString
        let privateKey = AssociationCrypto.makePrivateKey()
        let expiresAt = Date().addingTimeInterval(AssociationProtocol.handshakeTtlSeconds)
        pruneExpiredHandshakes(now: Date())
        evictPendingHandshakesIfNeeded()
        pendingHandshakes[handshakeId] = PendingHandshake(
            id: handshakeId,
            origin: origin,
            privateKey: privateKey,
            dappPublicKeyBase64: request.dappPublicKeyBase64,
            metadata: request.metadata,
            createdAt: Date(),
            expiresAt: expiresAt
        )
        return AssociationHandshakeResponse(
            protocolVersion: AssociationProtocol.version,
            handshakeId: handshakeId,
            walletPublicKeyBase64: AssociationCrypto.publicKeyBase64(for: privateKey),
            expiresAt: expiresAt
        )
    }

    private func associate(_ envelope: AssociationEnvelope, origin: String) async throws -> AssociationEnvelope {
        pruneExpiredHandshakes(now: Date())
        guard let handshake = pendingHandshakes.removeValue(forKey: envelope.keyId), handshake.origin == origin else {
            throw WalletAssociationError.invalidHandshake
        }
        guard handshake.expiresAt > Date() else {
            throw WalletAssociationError.invalidHandshake
        }
        let key = try AssociationCrypto.handshakeKey(
            privateKey: handshake.privateKey,
            peerPublicKeyBase64: handshake.dappPublicKeyBase64,
            handshakeId: handshake.id,
            origin: origin
        )
        let payload = try AssociationCrypto.open(
            AssociationRequestPayload.self,
            sealedBoxBase64: envelope.sealedBoxBase64,
            key: key,
            decoder: decoder
        )
        guard let delegate else {
            throw WalletAssociationError.unavailable("relay unavailable")
        }
        let response = try await delegate.associationApprove(
            payload,
            context: AssociationHandshakeContext(
                handshakeId: handshake.id,
                origin: origin,
                dappPublicKeyBase64: handshake.dappPublicKeyBase64,
                metadata: handshake.metadata
            )
        )
        let sealed = try AssociationCrypto.seal(response, key: key, encoder: encoder)
        return AssociationEnvelope(protocolVersion: AssociationProtocol.version, keyId: handshake.id, sealedBoxBase64: sealed)
    }

    private func rpc(_ envelope: AssociationEnvelope, origin: String) async throws -> AssociationEnvelope {
        guard let delegate else {
            throw WalletAssociationError.unavailable("relay unavailable")
        }
        let token = try await delegate.associationSessionToken(sessionId: envelope.keyId, verifiedOrigin: origin).token
        try AssociationToken.validate(token)
        let key = try AssociationCrypto.sessionKey(sessionToken: token, sessionId: envelope.keyId, origin: origin)
        let payload = try AssociationCrypto.open(
            AssociationRPCRequestPayload.self,
            sealedBoxBase64: envelope.sealedBoxBase64,
            key: key,
            decoder: decoder
        )
        guard let requestToken = Data(base64Encoded: payload.sessionTokenBase64) else {
            throw WalletAssociationError.sessionTokenInvalid
        }
        try AssociationToken.validate(requestToken)
        guard AssociationToken.constantTimeEquals(requestToken, token) else {
            throw WalletAssociationError.sessionTokenInvalid
        }
        try replayCache.validate(payload, sessionId: envelope.keyId)
        let session = AssociationSessionContext(sessionId: envelope.keyId, origin: origin)
        let response: AssociationRPCResponsePayload
        if payload.method == "wallet.session.rotate", case .sessionRotation(let request) = payload.params {
            let result = try await delegate.associationRotateSessionToken(request, session: session)
            response = AssociationRPCResponsePayload(requestId: payload.requestId, result: .sessionRotation(result))
        } else {
            response = try await delegate.associationRPC(payload, session: session)
        }
        let sealed = try AssociationCrypto.seal(response, key: key, encoder: encoder)
        return AssociationEnvelope(protocolVersion: AssociationProtocol.version, keyId: envelope.keyId, sealedBoxBase64: sealed)
    }

    private func walletSocketURL() -> URL {
        var components = URLComponents(url: connectionURI.relayURL, resolvingAgainstBaseURL: false)!
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "room", value: connectionURI.roomId))
        items.append(URLQueryItem(name: "secret", value: connectionURI.roomSecret))
        items.append(URLQueryItem(name: "role", value: "wallet"))
        components.queryItems = items
        return components.url!
    }

    private func send(_ object: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let string = String(data: data, encoding: .utf8) else {
            throw WalletAssociationError.malformedRequest
        }
        try await webSocketClient.send(string)
    }

    private func decodeBody<T: Decodable>(_ type: T.Type, frame: [String: Any]) throws -> T {
        guard let body = frame["body"] else {
            throw WalletAssociationError.malformedRequest
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        return try decoder.decode(type, from: data)
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try encoder.encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func validateProtocol(_ version: String) throws {
        guard version == AssociationProtocol.version else {
            throw WalletAssociationError.unsupportedProtocol(version)
        }
    }

    private func pruneExpiredHandshakes(now: Date) {
        pendingHandshakes = pendingHandshakes.filter { $0.value.expiresAt > now }
    }

    private func evictPendingHandshakesIfNeeded() {
        guard pendingHandshakes.count >= configuration.maxPendingHandshakes else { return }
        let excessCount = pendingHandshakes.count - configuration.maxPendingHandshakes + 1
        let evictedIds = pendingHandshakes
            .values
            .sorted { $0.createdAt < $1.createdAt }
            .prefix(excessCount)
            .map(\.id)
        for id in evictedIds {
            pendingHandshakes.removeValue(forKey: id)
        }
    }

    private func errorBody(_ error: Error) -> [String: Any] {
        let associationError = error as? WalletAssociationError
        let code: String
        switch associationError {
        case .invalidOrigin:
            code = "invalid_origin"
        case .sessionNotFound, .sessionExpired, .sessionTokenInvalid, .replayDetected:
            code = "session_invalid"
        case .unsupportedMethod:
            code = "unsupported_method"
        case .unavailable:
            code = "bridge_unavailable"
        default:
            code = "malformed_request"
        }
        return ["error": ["code": code, "message": error.localizedDescription]]
    }
}

private struct PendingHandshake {
    let id: String
    let origin: String
    let privateKey: Curve25519.KeyAgreement.PrivateKey
    let dappPublicKeyBase64: String
    let metadata: AssociationRequestMetadata?
    let createdAt: Date
    let expiresAt: Date
}
