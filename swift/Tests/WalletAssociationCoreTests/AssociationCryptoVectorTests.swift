import CryptoKit
import Foundation
@testable import WalletAssociationCore
import XCTest

final class AssociationCryptoVectorTests: XCTestCase {
    func testSwiftCryptoMatchesHandshakeCreateVector() throws {
        let vector = try loadVector(HandshakeCreateSessionVector.self, named: "handshake-create-session")
        let dappPrivateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data(hex: vector.dappSecretKeyHex))

        XCTAssertEqual(AssociationCrypto.publicKeyBase64(for: dappPrivateKey), vector.dappPublicKeyBase64)

        let handshakeKey = try AssociationCrypto.handshakeKey(
            privateKey: dappPrivateKey,
            peerPublicKeyBase64: vector.walletPublicKeyBase64,
            handshakeId: vector.handshakeId,
            origin: vector.origin
        )
        XCTAssertEqual(handshakeKey.hexString, vector.handshakeKeyHex)
    }

    func testSwiftCryptoMatchesSessionVector() throws {
        let vector = try loadVector(SigningRPCVector.self, named: "sign-message-rpc")
        let sessionToken = try XCTUnwrap(Data(base64Encoded: vector.sessionTokenBase64))
        let sessionKey = try AssociationCrypto.sessionKey(
            sessionToken: sessionToken,
            sessionId: vector.sessionId,
            origin: vector.origin
        )

        XCTAssertEqual(sessionKey.hexString, vector.sessionKeyHex)
    }
}

final class AssociationEnvelopeVectorTests: XCTestCase {
    func testSwiftOpensAssociationAndRPCVectors() throws {
        let createVector = try loadVector(HandshakeCreateSessionVector.self, named: "handshake-create-session")
        let dappPrivateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data(hex: createVector.dappSecretKeyHex))
        let handshakeKey = try AssociationCrypto.handshakeKey(
            privateKey: dappPrivateKey,
            peerPublicKeyBase64: createVector.walletPublicKeyBase64,
            handshakeId: createVector.handshakeId,
            origin: createVector.origin
        )

        let createPayload = try AssociationCrypto.open(
            AssociationRequestPayload.self,
            sealedBoxBase64: createVector.create.envelope.sealedBoxBase64,
            key: handshakeKey,
            decoder: Self.decoder
        )
        XCTAssertEqual(createPayload.kind, .create)
        XCTAssertEqual(createPayload.requestedChains, ["solana:devnet"])

        let createResponse = try AssociationCrypto.open(
            AssociationResponsePayload.self,
            sealedBoxBase64: createVector.createResponse.envelope.sealedBoxBase64,
            key: handshakeKey,
            decoder: Self.decoder
        )
        XCTAssertEqual(createResponse.sessionId, createVector.sessionId)

        let resumeVector = try loadVector(ResumeSessionVector.self, named: "resume-session")
        let resumePrivateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data(hex: resumeVector.dappSecretKeyHex))
        let resumeKey = try AssociationCrypto.handshakeKey(
            privateKey: resumePrivateKey,
            peerPublicKeyBase64: resumeVector.walletPublicKeyBase64,
            handshakeId: resumeVector.handshakeId,
            origin: resumeVector.origin
        )
        let resumePayload = try AssociationCrypto.open(
            AssociationRequestPayload.self,
            sealedBoxBase64: resumeVector.resume.envelope.sealedBoxBase64,
            key: resumeKey,
            decoder: Self.decoder
        )
        XCTAssertEqual(resumePayload.kind, .resume)

        try Self.assertSigningVector(named: "sign-message-rpc", expectedMethod: "solana.signMessage")
        try Self.assertSigningVector(named: "sign-transaction-rpc", expectedMethod: "solana.signTransaction")
    }

    func testSwiftRejectsInvalidEnvelopeVector() throws {
        let invalid = try loadVector(InvalidEnvelopeVector.self, named: "invalid-envelope")
        let messageVector = try loadVector(SigningRPCVector.self, named: "sign-message-rpc")
        let token = try XCTUnwrap(Data(base64Encoded: messageVector.sessionTokenBase64))
        let key = try AssociationCrypto.sessionKey(sessionToken: token, sessionId: messageVector.sessionId, origin: messageVector.origin)

        XCTAssertThrowsError(try AssociationCrypto.open(
            AssociationRPCRequestPayload.self,
            sealedBoxBase64: invalid.malformed.sealedBoxBase64,
            key: key,
            decoder: Self.decoder
        ))
    }

    private static func assertSigningVector(named name: String, expectedMethod: String) throws {
        let vector = try loadVector(SigningRPCVector.self, named: name)
        let token = try XCTUnwrap(Data(base64Encoded: vector.sessionTokenBase64))
        let key = try AssociationCrypto.sessionKey(sessionToken: token, sessionId: vector.sessionId, origin: vector.origin)
        let request = try AssociationCrypto.open(
            AssociationRPCRequestPayload.self,
            sealedBoxBase64: vector.request.envelope.sealedBoxBase64,
            key: key,
            decoder: decoder
        )
        XCTAssertEqual(request.method, expectedMethod)
        let response = try AssociationCrypto.open(
            AssociationRPCResponsePayload.self,
            sealedBoxBase64: vector.response.envelope.sealedBoxBase64,
            key: key,
            decoder: decoder
        )
        XCTAssertEqual(response.requestId, request.requestId)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = fractionalISO8601.date(from: value) ?? iso8601.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date")
        }
        return decoder
    }()

    private static let fractionalISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601 = ISO8601DateFormatter()
}

private struct HandshakeCreateSessionVector: Decodable {
    let origin: String
    let handshakeId: String
    let dappSecretKeyHex: String
    let dappPublicKeyBase64: String
    let walletPublicKeyBase64: String
    let handshakeKeyHex: String
    let sessionId: String
    let create: VectorEnvelope
    let createResponse: VectorEnvelope
}

private struct ResumeSessionVector: Decodable {
    let origin: String
    let handshakeId: String
    let dappSecretKeyHex: String
    let walletPublicKeyBase64: String
    let resume: VectorEnvelope
}

private struct SigningRPCVector: Decodable {
    let origin: String
    let sessionId: String
    let sessionTokenBase64: String
    let sessionKeyHex: String
    let request: VectorEnvelope
    let response: VectorEnvelope
}

private struct InvalidEnvelopeVector: Decodable {
    let malformed: AssociationEnvelope
}

private struct VectorEnvelope: Decodable {
    let envelope: AssociationEnvelope
}

private func loadVector<T: Decodable>(_ type: T.Type, named name: String) throws -> T {
    let packageRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let candidates = [
        packageRoot.deletingLastPathComponent().appendingPathComponent("test-vectors/v0.1/\(name).json"),
        URL(fileURLWithPath: "/Users/stevensarmi/Code/wallet-association-protocol/test-vectors/v0.1/\(name).json")
    ]
    guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
        throw XCTSkip("wallet-association-protocol test vectors are not available")
    }

    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(type, from: data)
}

private extension Data {
    init(hex: String) {
        precondition(hex.count.isMultiple(of: 2), "Hex string must contain full bytes")
        self.init()
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            append(UInt8(hex[index..<nextIndex], radix: 16)!)
            index = nextIndex
        }
    }
}

private extension SymmetricKey {
    var hexString: String {
        withUnsafeBytes { bytes in
            Data(bytes).map { String(format: "%02x", $0) }.joined()
        }
    }
}
