import CryptoKit
import Foundation
import XCTest
@testable import WalletAssociationCore
@testable import WalletAssociationRelay

final class RelayAssociationBridgeTests: XCTestCase {
    private let origin = "https://app.example"

    func testDiscoverReturnsRelayTransportAndNoAccounts() async throws {
        let harness = RelayHarness(origin: origin)

        let response = try await harness.request(operation: "discover")

        XCTAssertEqual(response["ok"] as? Bool, true)
        let body = try XCTUnwrap(response["body"] as? [String: Any])
        XCTAssertEqual(body["protocolVersion"] as? String, "2")
        XCTAssertNil(body["accounts"])
        XCTAssertEqual((body["transports"] as? [[String: Any]])?.first?["type"] as? String, "relay")
    }

    func testHandshakeRejectsMismatchedMetadataOrigin() async throws {
        let harness = RelayHarness(origin: origin)
        let dappKey = AssociationCrypto.makePrivateKey()

        let response = try await harness.request(
            operation: "handshake",
            body: AssociationHandshakeRequest(
                protocolVersion: "2",
                dappPublicKeyBase64: AssociationCrypto.publicKeyBase64(for: dappKey),
                metadata: AssociationRequestMetadata(origin: "https://wrong.example")
            )
        )

        XCTAssertEqual(response["ok"] as? Bool, false)
        XCTAssertEqual(((response["error"] as? [String: Any])?["error"] as? [String: Any])?["code"] as? String, "invalid_origin")
    }

    func testHandshakeReturnsWalletPublicKeyAndId() async throws {
        let harness = RelayHarness(origin: origin)
        let session = try await harness.handshake()

        XCTAssertFalse(session.handshake.handshakeId.isEmpty)
        XCTAssertEqual(Data(base64Encoded: session.handshake.walletPublicKeyBase64)?.count, 32)
    }

    func testAssociateDecryptsCreatePayloadAndCallsDelegate() async throws {
        let delegate = RelayTestDelegate()
        let harness = RelayHarness(origin: origin, delegate: delegate)

        let response = try await harness.associate(AssociationRequestPayload(kind: .create, requestedChains: ["solana:devnet"]))

        XCTAssertEqual(delegate.lastApproveRequest?.kind, .create)
        XCTAssertEqual(delegate.lastApproveContext?.origin, origin)
        XCTAssertEqual(response.sessionId, delegate.sessionId)
    }

    func testSignMessageAndTransactionRPCsReturnEncryptedResponses() async throws {
        let delegate = RelayTestDelegate()
        let harness = RelayHarness(origin: origin, delegate: delegate)

        let message = try await harness.rpc(.message(requestId: "message", token: delegate.sessionToken))
        XCTAssertEqual(delegate.lastRPCRequest?.method, "solana.signMessage")
        if case .signMessage(let result) = message.result {
            XCTAssertEqual(result.signatureBase64, Data([1, 2, 3]).base64EncodedString())
        } else {
            XCTFail("Expected sign message response")
        }

        let transaction = try await harness.rpc(.transaction(requestId: "tx", token: delegate.sessionToken))
        XCTAssertEqual(delegate.lastRPCRequest?.method, "solana.signTransaction")
        if case .signTransaction(let result) = transaction.result {
            XCTAssertEqual(result.signedTransactionBase64, Data([4, 5, 6]).base64EncodedString())
        } else {
            XCTFail("Expected sign transaction response")
        }
    }

    func testSessionRotationRoutesToDelegate() async throws {
        let delegate = RelayTestDelegate()
        let harness = RelayHarness(origin: origin, delegate: delegate)

        let response = try await harness.rpc(.rotation(requestId: "rotate", token: delegate.sessionToken))

        XCTAssertEqual(delegate.rotateCallCount, 1)
        if case .sessionRotation(let result) = response.result {
            XCTAssertEqual(result.sessionId, delegate.sessionId)
            XCTAssertEqual(result.sessionTokenBase64, delegate.rotatedToken.base64EncodedString())
        } else {
            XCTFail("Expected session rotation response")
        }
    }

    func testDefaultSessionRotationReturnsUnsupportedMethod() async throws {
        let delegate = DefaultRotationDelegate()
        let harness = RelayHarness(origin: origin, delegate: delegate)

        let response = try await harness.rpcResponse(.rotation(requestId: "rotate", token: delegate.sessionToken))

        XCTAssertEqual(response["ok"] as? Bool, false)
        XCTAssertEqual(((response["error"] as? [String: Any])?["error"] as? [String: Any])?["code"] as? String, "unsupported_method")
    }

    func testDuplicateRPCRequestIdIsRejected() async throws {
        let delegate = RelayTestDelegate()
        let harness = RelayHarness(origin: origin, delegate: delegate)

        _ = try await harness.rpc(.message(requestId: "duplicate", token: delegate.sessionToken))
        let response = try await harness.rpcResponse(.message(requestId: "duplicate", token: delegate.sessionToken))

        XCTAssertEqual(response["ok"] as? Bool, false)
        XCTAssertEqual(((response["error"] as? [String: Any])?["error"] as? [String: Any])?["code"] as? String, "session_invalid")
    }

    func testSendEventEmitsEncryptedEventFrame() async throws {
        let delegate = RelayTestDelegate()
        let harness = RelayHarness(origin: origin, delegate: delegate)
        let event = AssociationSessionEventPayload(
            eventId: "event",
            issuedAt: Date(),
            sessionTokenBase64: delegate.sessionToken.base64EncodedString(),
            type: .accountsChanged,
            accounts: []
        )

        try await harness.bridge.sendEvent(event, sessionId: delegate.sessionId, origin: origin)

        let frame = try XCTUnwrap(harness.client.sentObjects.last)
        XCTAssertEqual(frame["kind"] as? String, "wap_event")
        let body = try XCTUnwrap(frame["body"] as? [String: Any])
        let data = try JSONSerialization.data(withJSONObject: body)
        let envelope = try harness.decoder.decode(AssociationEnvelope.self, from: data)
        let key = try AssociationCrypto.sessionKey(sessionToken: delegate.sessionToken, sessionId: delegate.sessionId, origin: origin)
        let opened = try AssociationCrypto.open(
            AssociationSessionEventPayload.self,
            sealedBoxBase64: envelope.sealedBoxBase64,
            key: key,
            decoder: harness.decoder
        )
        XCTAssertEqual(opened.type, .accountsChanged)
    }
}

private final class RelayHarness {
    let client = FakeRelayWebSocketClient()
    let bridge: RelayAssociationBridge
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    private let origin: String

    init(origin: String, delegate: AssociationBridgeDelegate = RelayTestDelegate()) {
        self.origin = origin
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        let uri = AssociationConnectionURI(
            version: "2",
            transport: "relay",
            relayURL: URL(string: "ws://127.0.0.1:9000/v2/relay")!,
            roomId: "room",
            roomSecret: "secret",
            origin: origin,
            expiresAt: Date().addingTimeInterval(300)
        )
        bridge = RelayAssociationBridge(connectionURI: uri, delegate: delegate, webSocketClient: client)
    }

    func request(operation: String, id: String = UUID().uuidString) async throws -> [String: Any] {
        let frame: [String: Any] = ["kind": "wap_request", "id": id, "operation": operation]
        try await bridge.handleRelayFrameForTesting(string(frame))
        return try XCTUnwrap(client.sentObjects.last)
    }

    func request<T: Encodable>(operation: String, body: T, id: String = UUID().uuidString) async throws -> [String: Any] {
        var frame: [String: Any] = ["kind": "wap_request", "id": id, "operation": operation]
        frame["body"] = try jsonObject(body)
        try await bridge.handleRelayFrameForTesting(string(frame))
        return try XCTUnwrap(client.sentObjects.last)
    }

    func handshake() async throws -> HandshakeSession {
        let dappKey = AssociationCrypto.makePrivateKey()
        let response = try await request(
            operation: "handshake",
            body: AssociationHandshakeRequest(
                protocolVersion: "2",
                dappPublicKeyBase64: AssociationCrypto.publicKeyBase64(for: dappKey),
                metadata: AssociationRequestMetadata(origin: origin, appName: "Example")
            )
        )
        XCTAssertEqual(response["ok"] as? Bool, true)
        let handshake = try decodeBody(AssociationHandshakeResponse.self, response: response)
        let key = try AssociationCrypto.handshakeKey(
            privateKey: dappKey,
            peerPublicKeyBase64: handshake.walletPublicKeyBase64,
            handshakeId: handshake.handshakeId,
            origin: origin
        )
        return HandshakeSession(handshake: handshake, key: key)
    }

    func associate(_ payload: AssociationRequestPayload) async throws -> AssociationResponsePayload {
        let session = try await handshake()
        let sealed = try AssociationCrypto.seal(payload, key: session.key, encoder: encoder)
        let envelope = AssociationEnvelope(protocolVersion: "2", keyId: session.handshake.handshakeId, sealedBoxBase64: sealed)
        let response = try await request(operation: "associate", body: envelope)
        let encrypted = try decodeBody(AssociationEnvelope.self, response: response)
        return try AssociationCrypto.open(
            AssociationResponsePayload.self,
            sealedBoxBase64: encrypted.sealedBoxBase64,
            key: session.key,
            decoder: decoder
        )
    }

    func rpc(_ payload: AssociationRPCRequestPayload) async throws -> AssociationRPCResponsePayload {
        let response = try await rpcResponse(payload)
        let encrypted = try decodeBody(AssociationEnvelope.self, response: response)
        let token = try XCTUnwrap(Data(base64Encoded: payload.sessionTokenBase64))
        let key = try AssociationCrypto.sessionKey(sessionToken: token, sessionId: encrypted.keyId, origin: origin)
        return try AssociationCrypto.open(
            AssociationRPCResponsePayload.self,
            sealedBoxBase64: encrypted.sealedBoxBase64,
            key: key,
            decoder: decoder
        )
    }

    func rpcResponse(_ payload: AssociationRPCRequestPayload) async throws -> [String: Any] {
        let token = try XCTUnwrap(Data(base64Encoded: payload.sessionTokenBase64))
        let key = try AssociationCrypto.sessionKey(sessionToken: token, sessionId: "session-id", origin: origin)
        let sealed = try AssociationCrypto.seal(payload, key: key, encoder: encoder)
        let envelope = AssociationEnvelope(protocolVersion: "2", keyId: "session-id", sealedBoxBase64: sealed)
        return try await request(operation: "rpc", body: envelope, id: payload.requestId)
    }

    private func decodeBody<T: Decodable>(_ type: T.Type, response: [String: Any]) throws -> T {
        let body = try XCTUnwrap(response["body"])
        let data = try JSONSerialization.data(withJSONObject: body)
        return try decoder.decode(type, from: data)
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try encoder.encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func string(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}

private struct HandshakeSession {
    let handshake: AssociationHandshakeResponse
    let key: SymmetricKey
}

private final class FakeRelayWebSocketClient: RelayWebSocketClient, @unchecked Sendable {
    var sentObjects: [[String: Any]] = []

    func connect(url: URL) async throws {}
    func receive() async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        throw URLError(.timedOut)
    }
    func close() {}

    func send(_ string: String) async throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(string.utf8)) as? [String: Any])
        sentObjects.append(object)
    }
}

private class DefaultRotationDelegate: AssociationBridgeDelegate, @unchecked Sendable {
    let sessionId = "session-id"
    let sessionToken = Data(repeating: 7, count: 32)

    func associationApprove(_ request: AssociationRequestPayload, context: AssociationHandshakeContext) async throws -> AssociationResponsePayload {
        AssociationResponsePayload(
            sessionId: sessionId,
            sessionTokenBase64: sessionToken.base64EncodedString(),
            expiresAt: Date().addingTimeInterval(3600),
            accounts: [],
            chains: AssociationProtocol.supportedChains,
            features: AssociationProtocol.supportedFeatures,
            signingPolicy: .prompt
        )
    }

    func associationSessionToken(sessionId: String, verifiedOrigin: String) async throws -> AssociationSessionToken {
        AssociationSessionToken(token: sessionToken)
    }

    func associationRPC(_ request: AssociationRPCRequestPayload, session: AssociationSessionContext) async throws -> AssociationRPCResponsePayload {
        throw WalletAssociationError.unsupportedMethod(request.method)
    }

    func associationRotateSessionToken(
        _ request: AssociationSessionRotationRequest,
        session: AssociationSessionContext
    ) async throws -> AssociationSessionRotationResponse {
        throw WalletAssociationError.unsupportedMethod("wallet.session.rotate")
    }
}

private final class RelayTestDelegate: DefaultRotationDelegate, @unchecked Sendable {
    let rotatedToken = Data(repeating: 9, count: 32)
    var lastApproveRequest: AssociationRequestPayload?
    var lastApproveContext: AssociationHandshakeContext?
    var lastRPCRequest: AssociationRPCRequestPayload?
    var rotateCallCount = 0

    override func associationApprove(_ request: AssociationRequestPayload, context: AssociationHandshakeContext) async throws -> AssociationResponsePayload {
        lastApproveRequest = request
        lastApproveContext = context
        return try await super.associationApprove(request, context: context)
    }

    override func associationRPC(_ request: AssociationRPCRequestPayload, session: AssociationSessionContext) async throws -> AssociationRPCResponsePayload {
        lastRPCRequest = request
        switch request.method {
        case "solana.signMessage":
            return AssociationRPCResponsePayload(
                requestId: request.requestId,
                result: .signMessage(AssociationSignMessageResponse(signatureBase64: Data([1, 2, 3]).base64EncodedString()))
            )
        case "solana.signTransaction":
            return AssociationRPCResponsePayload(
                requestId: request.requestId,
                result: .signTransaction(AssociationSignTransactionResponse(
                    signedTransactionBase64: Data([4, 5, 6]).base64EncodedString(),
                    signature: "signature"
                ))
            )
        default:
            throw WalletAssociationError.unsupportedMethod(request.method)
        }
    }

    override func associationRotateSessionToken(
        _ request: AssociationSessionRotationRequest,
        session: AssociationSessionContext
    ) async throws -> AssociationSessionRotationResponse {
        rotateCallCount += 1
        return AssociationSessionRotationResponse(
            sessionId: sessionId,
            sessionTokenBase64: rotatedToken.base64EncodedString(),
            expiresAt: Date().addingTimeInterval(3600)
        )
    }
}

private extension AssociationRPCRequestPayload {
    static func message(requestId: String, token: Data) -> AssociationRPCRequestPayload {
        AssociationRPCRequestPayload(
            requestId: requestId,
            issuedAt: Date(),
            sessionTokenBase64: token.base64EncodedString(),
            method: "solana.signMessage",
            params: .signMessage(AssociationSignMessageParams(
                accountAddress: "account",
                messageBase64: Data("hello".utf8).base64EncodedString()
            ))
        )
    }

    static func transaction(requestId: String, token: Data) -> AssociationRPCRequestPayload {
        AssociationRPCRequestPayload(
            requestId: requestId,
            issuedAt: Date(),
            sessionTokenBase64: token.base64EncodedString(),
            method: "solana.signTransaction",
            params: .signTransaction(AssociationSignTransactionParams(
                accountAddress: "account",
                transactionBase64: Data("tx".utf8).base64EncodedString()
            ))
        )
    }

    static func rotation(requestId: String, token: Data) -> AssociationRPCRequestPayload {
        AssociationRPCRequestPayload(
            requestId: requestId,
            issuedAt: Date(),
            sessionTokenBase64: token.base64EncodedString(),
            method: "wallet.session.rotate",
            params: .sessionRotation(AssociationSessionRotationRequest())
        )
    }
}
