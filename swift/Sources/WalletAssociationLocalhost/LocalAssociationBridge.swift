import CryptoKit
import Foundation
import Network
import WalletAssociationCore

public final class LocalAssociationBridge: @unchecked Sendable {
    public static let defaultPort = AssociationProtocol.defaultPort
    public static let protocolVersion = AssociationProtocol.version
    public static let supportedChains = AssociationProtocol.supportedChains
    public static let supportedFeatures = AssociationProtocol.supportedFeatures

    public private(set) var port: UInt16

    private weak var delegate: LocalAssociationBridgeDelegate?
    private let configuration: LocalAssociationBridgeConfiguration
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "LocalAssociationBridge")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var pendingHandshakes: [String: PendingHandshake] = [:]
    private var replayCache = AssociationReplayCache()

    public convenience init(port: UInt16 = LocalAssociationBridge.defaultPort, delegate: LocalAssociationBridgeDelegate?) {
        self.init(
            configuration: LocalAssociationBridgeConfiguration(port: port),
            delegate: delegate
        )
    }

    public init(configuration: LocalAssociationBridgeConfiguration, delegate: LocalAssociationBridgeDelegate?) {
        self.port = configuration.port
        self.configuration = configuration
        self.delegate = delegate
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func start() throws {
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(IPv4Address("127.0.0.1")!),
            port: nwPort
        )
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state, let activePort = listener.port?.rawValue {
                self?.port = activePort
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        pendingHandshakes.removeAll()
        replayCache.removeAll()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, into: RequestBuffer())
    }

    private func receive(on connection: NWConnection, into buffer: RequestBuffer) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if let data {
                buffer.data.append(data)
            }
            do {
                if let expected = try HTTPAssociationRequest.expectedLength(
                    in: buffer.data,
                    maxRequestBytes: configuration.maxRequestBytes,
                    maxBodyBytes: configuration.maxBodyBytes
                ), buffer.data.count >= expected || isComplete {
                    Task {
                        let response = await self.response(for: buffer.data)
                        connection.send(content: response, completion: .contentProcessed { _ in
                            connection.cancel()
                        })
                    }
                    return
                }
            } catch {
                Task {
                    let request = try? HTTPAssociationRequest(
                        data: buffer.data,
                        maxRequestBytes: self.configuration.maxRequestBytes,
                        maxBodyBytes: self.configuration.maxBodyBytes
                    )
                    let response = HTTPAssociationResponse.bridgeError(error, encoder: self.encoder, request: request)
                    connection.send(content: response, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
                return
            }
            if error != nil || isComplete {
                connection.cancel()
                return
            }
            self.receive(on: connection, into: buffer)
        }
    }

    private func response(for data: Data) async -> Data {
        do {
            let request = try HTTPAssociationRequest(
                data: data,
                maxRequestBytes: configuration.maxRequestBytes,
                maxBodyBytes: configuration.maxBodyBytes
            )
            if request.method == "OPTIONS" {
                return HTTPAssociationResponse.response(status: 204, body: Data(), request: request)
            }

            switch (request.method, request.path) {
            case ("GET", "/health"):
                return try HTTPAssociationResponse.success(status: 200, encodable: ["status": "ok"], encoder: encoder, request: request)
            case ("GET", "/v2/discover"):
                return try HTTPAssociationResponse.success(status: 200, encodable: discoverResponse(), encoder: encoder, request: request)
            case ("POST", "/v2/handshake"):
                let body = try decoder.decode(AssociationHandshakeRequest.self, from: request.body)
                try validateProtocol(body.protocolVersion)
                let origin = try verifiedOrigin(for: request, metadata: body.metadata)
                let result = try handshake(body, origin: origin)
                return try HTTPAssociationResponse.success(status: 200, encodable: result, encoder: encoder, request: request)
            case ("POST", "/v2/associate"):
                let envelope = try decoder.decode(AssociationEnvelope.self, from: request.body)
                try validateProtocol(envelope.protocolVersion)
                let origin = try verifiedOrigin(for: request, metadata: nil)
                let result = try await associate(envelope, origin: origin)
                return try HTTPAssociationResponse.success(status: 200, encodable: result, encoder: encoder, request: request)
            case ("POST", "/v2/rpc"):
                let envelope = try decoder.decode(AssociationEnvelope.self, from: request.body)
                try validateProtocol(envelope.protocolVersion)
                let origin = try verifiedOrigin(for: request, metadata: nil)
                let result = try await rpc(envelope, origin: origin)
                return try HTTPAssociationResponse.success(status: 200, encodable: result, encoder: encoder, request: request)
            default:
                return HTTPAssociationResponse.error(status: 404, code: "not_found", message: "not found", encoder: encoder, request: request)
            }
        } catch {
            let request = try? HTTPAssociationRequest(
                data: data,
                maxRequestBytes: configuration.maxRequestBytes,
                maxBodyBytes: configuration.maxBodyBytes
            )
            return HTTPAssociationResponse.bridgeError(error, encoder: encoder, request: request)
        }
    }

    private func discoverResponse() -> AssociationDiscoverResponse {
        AssociationDiscoverResponse(
            name: configuration.walletName,
            version: configuration.walletVersion,
            protocolVersion: Self.protocolVersion,
            transports: [AssociationTransportDescriptor(type: "localhost", host: "127.0.0.1", port: port)],
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
            protocolVersion: Self.protocolVersion,
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
            throw WalletAssociationError.unavailable("bridge unavailable")
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
        return AssociationEnvelope(protocolVersion: Self.protocolVersion, keyId: handshake.id, sealedBoxBase64: sealed)
    }

    private func rpc(_ envelope: AssociationEnvelope, origin: String) async throws -> AssociationEnvelope {
        guard let delegate else {
            throw WalletAssociationError.unavailable("bridge unavailable")
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
        let response = try await delegate.associationRPC(
            payload,
            session: AssociationSessionContext(sessionId: envelope.keyId, origin: origin)
        )
        let sealed = try AssociationCrypto.seal(response, key: key, encoder: encoder)
        return AssociationEnvelope(protocolVersion: Self.protocolVersion, keyId: envelope.keyId, sealedBoxBase64: sealed)
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

    private func validateProtocol(_ version: String) throws {
        guard version == Self.protocolVersion else {
            throw WalletAssociationError.unsupportedProtocol(version)
        }
    }

    private func verifiedOrigin(for request: HTTPAssociationRequest, metadata: AssociationRequestMetadata?) throws -> String {
        guard let origin = request.headers["origin"], LocalhostCORS.isValidBrowserOrigin(origin) else {
            throw WalletAssociationError.invalidOrigin
        }
        if let metadataOrigin = metadata?.origin, metadataOrigin != origin {
            throw WalletAssociationError.invalidOrigin
        }
        return origin
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

private final class RequestBuffer {
    var data = Data()
}
