import CryptoKit
import Foundation
import Network
import XCTest
@testable import WalletAssociationCore
@testable import WalletAssociationLocalhost

final class LocalAssociationBridgeTests: XCTestCase {
    private let origin = "https://app.example"

    func testDefaultPortIsFixed() {
        XCTAssertEqual(LocalAssociationBridge.defaultPort, 51_884)
    }

    func testDiscoverReturnsProtocolVersionAndNoAccounts() async throws {
        let harness = try await AssociationHarness()
        let response = try await harness.request(method: "GET", path: "/v2/discover")

        XCTAssertEqual(response.status, 200)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        XCTAssertEqual(json["protocolVersion"] as? String, "2")
        XCTAssertNil(json["accounts"])
        XCTAssertEqual((json["transports"] as? [[String: Any]])?.first?["type"] as? String, "localhost")
    }

    func testV1RoutesReturn404() async throws {
        let harness = try await AssociationHarness()
        let response = try await harness.request(method: "GET", path: "/v1/discover")

        XCTAssertEqual(response.status, 404)
    }

    func testOptionsAssociateReturnsCORSPreflightHeaders() async throws {
        let harness = try await AssociationHarness()
        let response = try await harness.request(method: "OPTIONS", path: "/v2/associate", origin: origin)

        XCTAssertEqual(response.status, 204)
        XCTAssertEqual(response.headers["access-control-allow-origin"], origin)
        XCTAssertEqual(response.headers["access-control-allow-methods"], "GET, POST, OPTIONS")
        XCTAssertEqual(response.headers["access-control-allow-headers"], "Content-Type")
        XCTAssertNil(response.headers["access-control-allow-credentials"])
    }

    func testHandshakeRejectsMissingOrigin() async throws {
        let harness = try await AssociationHarness()
        let dappKey = AssociationCrypto.makePrivateKey()
        let body = AssociationHandshakeRequest(
            protocolVersion: "2",
            dappPublicKeyBase64: AssociationCrypto.publicKeyBase64(for: dappKey)
        )
        let response = try await harness.jsonRequest(method: "POST", path: "/v2/handshake", body: body)

        XCTAssertEqual(response.status, 400)
        XCTAssertEqual(try response.errorCode(), "invalid_origin")
    }

    func testHandshakeRejectsMismatchedMetadataOrigin() async throws {
        let harness = try await AssociationHarness()
        let dappKey = AssociationCrypto.makePrivateKey()
        let body = AssociationHandshakeRequest(
            protocolVersion: "2",
            dappPublicKeyBase64: AssociationCrypto.publicKeyBase64(for: dappKey),
            metadata: AssociationRequestMetadata(origin: "https://wrong.example")
        )
        let response = try await harness.jsonRequest(method: "POST", path: "/v2/handshake", origin: origin, body: body)

        XCTAssertEqual(response.status, 400)
        XCTAssertEqual(try response.errorCode(), "invalid_origin")
    }

    func testHandshakeReturnsWalletPublicKeyAndId() async throws {
        let harness = try await AssociationHarness()
        let session = try await harness.handshake(origin: origin)

        XCTAssertFalse(session.handshake.handshakeId.isEmpty)
        XCTAssertEqual(Data(base64Encoded: session.handshake.walletPublicKeyBase64)?.count, 32)
    }

    func testAssociateRejectsUnknownHandshake() async throws {
        let harness = try await AssociationHarness()
        let envelope = AssociationEnvelope(protocolVersion: "2", keyId: "missing", sealedBoxBase64: "not-base64")
        let response = try await harness.jsonRequest(method: "POST", path: "/v2/associate", origin: origin, body: envelope)

        XCTAssertEqual(response.status, 400)
        XCTAssertEqual(try response.errorCode(), "malformed_request")
    }

    func testEncryptedCreateAssociationCallsDelegateAndReturnsSession() async throws {
        let delegate = TestAssociationDelegate()
        let harness = try await AssociationHarness(delegate: delegate)

        let response = try await harness.associate(
            AssociationRequestPayload(kind: .create, requestedChains: ["solana:devnet"]),
            origin: origin
        )

        XCTAssertEqual(delegate.lastApproveContext?.origin, origin)
        XCTAssertEqual(delegate.lastApproveRequest?.kind, .create)
        XCTAssertEqual(response.sessionId, delegate.sessionId)
        XCTAssertEqual(response.sessionTokenBase64, delegate.sessionToken.base64EncodedString())
    }

    func testResumeAssociationWithValidTokenDoesNotRequireNewSession() async throws {
        let delegate = TestAssociationDelegate()
        let harness = try await AssociationHarness(delegate: delegate)

        let response = try await harness.associate(
            AssociationRequestPayload(
                kind: .resume,
                resumeSessionId: delegate.sessionId,
                resumeSessionTokenBase64: delegate.sessionToken.base64EncodedString()
            ),
            origin: origin
        )

        XCTAssertEqual(response.sessionId, delegate.sessionId)
        XCTAssertEqual(delegate.lastApproveRequest?.kind, .resume)
    }

    func testResumeAssociationWithExpiredSessionReturnsSessionInvalid() async throws {
        let delegate = TestAssociationDelegate()
        delegate.sessionExpired = true
        let harness = try await AssociationHarness(delegate: delegate)
        let response = try await harness.associateResponse(
            AssociationRequestPayload(
                kind: .resume,
                resumeSessionId: delegate.sessionId,
                resumeSessionTokenBase64: delegate.sessionToken.base64EncodedString()
            ),
            origin: origin
        )

        XCTAssertEqual(response.status, 403)
        XCTAssertEqual(try response.errorCode(), "session_invalid")
    }

    func testRPCRejectsMissingSession() async throws {
        let delegate = TestAssociationDelegate()
        delegate.failSessionLookup = true
        let harness = try await AssociationHarness(delegate: delegate)

        let response = try await harness.rpcResponse(
            sessionId: delegate.sessionId,
            sessionToken: delegate.sessionToken,
            origin: origin,
            payload: .message(requestId: "1", token: delegate.sessionToken)
        )

        XCTAssertEqual(response.status, 403)
        XCTAssertEqual(try response.errorCode(), "session_invalid")
    }

    func testRPCRejectsBadSessionToken() async throws {
        let delegate = TestAssociationDelegate()
        let harness = try await AssociationHarness(delegate: delegate)
        let badToken = Data(repeating: 9, count: 32)

        let response = try await harness.rpcResponse(
            sessionId: delegate.sessionId,
            sessionToken: delegate.sessionToken,
            origin: origin,
            payload: .message(requestId: "1", token: badToken)
        )

        XCTAssertEqual(response.status, 403)
        XCTAssertEqual(try response.errorCode(), "session_invalid")
    }

    func testRPCRejectsDuplicateRequestId() async throws {
        let delegate = TestAssociationDelegate()
        let harness = try await AssociationHarness(delegate: delegate)
        _ = try await harness.rpc(
            sessionId: delegate.sessionId,
            sessionToken: delegate.sessionToken,
            origin: origin,
            payload: .message(requestId: "duplicate", token: delegate.sessionToken)
        )
        let response = try await harness.rpcResponse(
            sessionId: delegate.sessionId,
            sessionToken: delegate.sessionToken,
            origin: origin,
            payload: .message(requestId: "duplicate", token: delegate.sessionToken)
        )

        XCTAssertEqual(response.status, 403)
        XCTAssertEqual(try response.errorCode(), "session_invalid")
    }

    func testSignMessageRPCForwardsDecodedRequestAndReturnsEncryptedResponse() async throws {
        let delegate = TestAssociationDelegate()
        let harness = try await AssociationHarness(delegate: delegate)

        let response = try await harness.rpc(
            sessionId: delegate.sessionId,
            sessionToken: delegate.sessionToken,
            origin: origin,
            payload: .message(requestId: "message", token: delegate.sessionToken)
        )

        XCTAssertEqual(delegate.lastRPCRequest?.method, "solana.signMessage")
        XCTAssertEqual(response.requestId, "message")
        if case .signMessage(let result) = response.result {
            XCTAssertEqual(result.signatureBase64, Data([1, 2, 3]).base64EncodedString())
        } else {
            XCTFail("Expected sign message result")
        }
    }

    func testSignTransactionRPCForwardsDecodedRequestAndReturnsEncryptedResponse() async throws {
        let delegate = TestAssociationDelegate()
        let harness = try await AssociationHarness(delegate: delegate)

        let response = try await harness.rpc(
            sessionId: delegate.sessionId,
            sessionToken: delegate.sessionToken,
            origin: origin,
            payload: .transaction(requestId: "tx", token: delegate.sessionToken)
        )

        XCTAssertEqual(delegate.lastRPCRequest?.method, "solana.signTransaction")
        XCTAssertEqual(response.requestId, "tx")
        if case .signTransaction(let result) = response.result {
            XCTAssertEqual(result.signedTransactionBase64, Data([4, 5, 6]).base64EncodedString())
            XCTAssertEqual(result.signature, "signature")
        } else {
            XCTFail("Expected sign transaction result")
        }
    }

    func testUnsupportedRPCMethodReturnsUnsupportedMethod() async throws {
        let delegate = TestAssociationDelegate()
        let harness = try await AssociationHarness(delegate: delegate)

        let response = try await harness.rpcResponse(
            sessionId: delegate.sessionId,
            sessionToken: delegate.sessionToken,
            origin: origin,
            payload: AssociationRPCRequestPayload(
                requestId: "unsupported",
                issuedAt: Date(),
                sessionTokenBase64: delegate.sessionToken.base64EncodedString(),
                method: "solana.unknown",
                params: .signMessage(AssociationSignMessageParams(
                    accountAddress: "account",
                    messageBase64: Data("hello".utf8).base64EncodedString()
                ))
            )
        )

        XCTAssertEqual(response.status, 400)
        XCTAssertEqual(try response.errorCode(), "unsupported_method")
    }
}

private final class TestAssociationDelegate: LocalAssociationBridgeDelegate, @unchecked Sendable {
    let sessionId = "session-id"
    let sessionToken = Data(repeating: 7, count: 32)
    var sessionExpired = false
    var failSessionLookup = false
    var lastApproveRequest: AssociationRequestPayload?
    var lastApproveContext: AssociationHandshakeContext?
    var lastRPCRequest: AssociationRPCRequestPayload?

    func associationApprove(
        _ request: AssociationRequestPayload,
        context: AssociationHandshakeContext
    ) async throws -> AssociationResponsePayload {
        lastApproveRequest = request
        lastApproveContext = context
        if sessionExpired {
            throw WalletAssociationError.sessionExpired
        }
        if request.kind == .resume {
            guard request.resumeSessionId == sessionId,
                  let resumeToken = Data(base64Encoded: request.resumeSessionTokenBase64 ?? ""),
                  resumeToken == sessionToken
            else {
                throw WalletAssociationError.sessionTokenInvalid
            }
        }
        return AssociationResponsePayload(
            sessionId: sessionId,
            sessionTokenBase64: sessionToken.base64EncodedString(),
            expiresAt: Date().addingTimeInterval(3600),
            accounts: [],
            chains: LocalAssociationBridge.supportedChains,
            features: LocalAssociationBridge.supportedFeatures,
            signingPolicy: .prompt
        )
    }

    func associationSessionToken(sessionId: String, verifiedOrigin: String) async throws -> AssociationSessionToken {
        if failSessionLookup {
            throw WalletAssociationError.sessionNotFound
        }
        guard sessionId == self.sessionId else {
            throw WalletAssociationError.sessionNotFound
        }
        return AssociationSessionToken(token: sessionToken)
    }

    func associationRPC(
        _ request: AssociationRPCRequestPayload,
        session: AssociationSessionContext
    ) async throws -> AssociationRPCResponsePayload {
        lastRPCRequest = request
        switch request.method {
        case "solana.signMessage":
            return AssociationRPCResponsePayload(
                requestId: request.requestId,
                result: .signMessage(AssociationSignMessageResponse(
                    signatureBase64: Data([1, 2, 3]).base64EncodedString()
                ))
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
}

private struct HandshakeSession {
    let dappPrivateKey: Curve25519.KeyAgreement.PrivateKey
    let handshake: AssociationHandshakeResponse
    let key: SymmetricKey
}

private final class AssociationHarness {
    private let bridge: LocalAssociationBridge
    private let delegate: LocalAssociationBridgeDelegate
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(delegate: LocalAssociationBridgeDelegate = TestAssociationDelegate()) async throws {
        self.delegate = delegate
        self.bridge = LocalAssociationBridge(port: 0, delegate: delegate)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        try bridge.start()
        try await waitForPort()
    }

    deinit {
        bridge.stop()
    }

    func handshake(origin: String) async throws -> HandshakeSession {
        let dappKey = AssociationCrypto.makePrivateKey()
        let body = AssociationHandshakeRequest(
            protocolVersion: "2",
            dappPublicKeyBase64: AssociationCrypto.publicKeyBase64(for: dappKey),
            metadata: AssociationRequestMetadata(origin: origin, appName: "App")
        )
        let response = try await jsonRequest(method: "POST", path: "/v2/handshake", origin: origin, body: body)
        XCTAssertEqual(response.status, 200)
        let handshake = try decoder.decode(AssociationHandshakeResponse.self, from: response.body)
        let key = try AssociationCrypto.handshakeKey(
            privateKey: dappKey,
            peerPublicKeyBase64: handshake.walletPublicKeyBase64,
            handshakeId: handshake.handshakeId,
            origin: origin
        )
        return HandshakeSession(dappPrivateKey: dappKey, handshake: handshake, key: key)
    }

    func associate(_ payload: AssociationRequestPayload, origin: String) async throws -> AssociationResponsePayload {
        let response = try await associateResponse(payload, origin: origin)
        XCTAssertEqual(response.status, 200)
        let envelope = try decoder.decode(AssociationEnvelope.self, from: response.body)
        let session = try XCTUnwrap(pendingAssociations.removeValue(forKey: envelope.keyId))
        return try AssociationCrypto.open(
            AssociationResponsePayload.self,
            sealedBoxBase64: envelope.sealedBoxBase64,
            key: session.key,
            decoder: decoder
        )
    }

    private var pendingAssociations: [String: HandshakeSession] = [:]

    func associateResponse(_ payload: AssociationRequestPayload, origin: String) async throws -> BridgeHTTPResponse {
        let session = try await handshake(origin: origin)
        pendingAssociations[session.handshake.handshakeId] = session
        let sealed = try AssociationCrypto.seal(payload, key: session.key, encoder: encoder)
        let envelope = AssociationEnvelope(
            protocolVersion: "2",
            keyId: session.handshake.handshakeId,
            sealedBoxBase64: sealed
        )
        return try await jsonRequest(method: "POST", path: "/v2/associate", origin: origin, body: envelope)
    }

    func rpc(
        sessionId: String,
        sessionToken: Data,
        origin: String,
        payload: AssociationRPCRequestPayload
    ) async throws -> AssociationRPCResponsePayload {
        let response = try await rpcResponse(sessionId: sessionId, sessionToken: sessionToken, origin: origin, payload: payload)
        XCTAssertEqual(response.status, 200)
        let envelope = try decoder.decode(AssociationEnvelope.self, from: response.body)
        let key = AssociationCrypto.sessionKey(sessionToken: sessionToken, sessionId: sessionId, origin: origin)
        return try AssociationCrypto.open(
            AssociationRPCResponsePayload.self,
            sealedBoxBase64: envelope.sealedBoxBase64,
            key: key,
            decoder: decoder
        )
    }

    func rpcResponse(
        sessionId: String,
        sessionToken: Data,
        origin: String,
        payload: AssociationRPCRequestPayload
    ) async throws -> BridgeHTTPResponse {
        let key = AssociationCrypto.sessionKey(sessionToken: sessionToken, sessionId: sessionId, origin: origin)
        let sealed = try AssociationCrypto.seal(payload, key: key, encoder: encoder)
        let envelope = AssociationEnvelope(protocolVersion: "2", keyId: sessionId, sealedBoxBase64: sealed)
        return try await jsonRequest(method: "POST", path: "/v2/rpc", origin: origin, body: envelope)
    }

    func jsonRequest<T: Encodable>(
        method: String,
        path: String,
        origin: String? = nil,
        body: T
    ) async throws -> BridgeHTTPResponse {
        let data = try encoder.encode(body)
        return try await request(method: method, path: path, origin: origin, body: data)
    }

    func request(method: String, path: String, origin: String? = nil, body: Data? = nil) async throws -> BridgeHTTPResponse {
        var head = "\(method) \(path) HTTP/1.1\r\n"
        head += "Host: 127.0.0.1:\(bridge.port)\r\n"
        if let origin {
            head += "Origin: \(origin)\r\n"
        }
        if let body {
            head += "Content-Type: application/json\r\n"
            head += "Content-Length: \(body.count)\r\n"
        } else {
            head += "Content-Length: 0\r\n"
        }
        head += "Connection: close\r\n\r\n"

        var requestData = Data(head.utf8)
        if let body {
            requestData.append(body)
        }
        let responseData = try await sendRawHTTP(requestData)
        return try BridgeHTTPResponse(data: responseData)
    }

    private func sendRawHTTP(_ data: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let state = RawHTTPState(continuation: continuation)
            let connection = NWConnection(
                host: .ipv4(IPv4Address("127.0.0.1")!),
                port: NWEndpoint.Port(rawValue: bridge.port)!,
                using: .tcp
            )

            func receive() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { chunk, _, isComplete, error in
                    if let chunk {
                        state.data.append(chunk)
                    }
                    if let error {
                        state.finish(.failure(error), connection: connection)
                        return
                    }
                    if isComplete {
                        state.finish(.success(state.data), connection: connection)
                        return
                    }
                    receive()
                }
            }

            connection.stateUpdateHandler = { status in
                switch status {
                case .ready:
                    connection.send(content: data, completion: .contentProcessed { error in
                        if let error {
                            state.finish(.failure(error), connection: connection)
                            return
                        }
                        receive()
                    })
                case .failed(let error):
                    state.finish(.failure(error), connection: connection)
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    private final class RawHTTPState: @unchecked Sendable {
        var data = Data()
        private var didFinish = false
        private let continuation: CheckedContinuation<Data, Error>

        init(continuation: CheckedContinuation<Data, Error>) {
            self.continuation = continuation
        }

        func finish(_ result: Result<Data, Error>, connection: NWConnection) {
            guard !didFinish else { return }
            didFinish = true
            connection.cancel()
            continuation.resume(with: result)
        }
    }

    private func waitForPort() async throws {
        for _ in 0..<50 {
            if bridge.port != 0 {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Bridge did not publish a port")
        throw WalletAssociationError.unavailable("Bridge did not publish a port.")
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
}

private struct BridgeHTTPResponse {
    let status: Int
    let headers: [String: String]
    let body: Data

    init(data: Data) throws {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8)
        else {
            throw WalletAssociationError.malformedRequest
        }

        let bodyStart = headerRange.upperBound
        self.body = data.subdata(in: bodyStart..<data.count)
        let lines = headerText.components(separatedBy: "\r\n")
        let statusParts = lines.first?.split(separator: " ") ?? []
        self.status = statusParts.count > 1 ? Int(statusParts[1]) ?? 0 : 0

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            headers[parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] =
                parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        self.headers = headers
    }

    func errorCode() throws -> String? {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let error = try XCTUnwrap(json["error"] as? [String: Any])
        return error["code"] as? String
    }
}
