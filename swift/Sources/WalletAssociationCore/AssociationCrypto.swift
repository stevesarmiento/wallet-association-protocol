import CryptoKit
import Foundation
import Security

public enum AssociationCrypto {
    public static func makePrivateKey() -> Curve25519.KeyAgreement.PrivateKey {
        Curve25519.KeyAgreement.PrivateKey()
    }

    public static func publicKeyBase64(for privateKey: Curve25519.KeyAgreement.PrivateKey) -> String {
        privateKey.publicKey.rawRepresentation.base64EncodedString()
    }

    public static func publicKey(fromBase64 value: String) throws -> Curve25519.KeyAgreement.PublicKey {
        guard let data = Data(base64Encoded: value), data.count == 32 else {
            throw WalletAssociationError.invalidHandshake
        }
        return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: data)
    }

    public static func handshakeKey(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        peerPublicKeyBase64: String,
        handshakeId: String,
        origin: String
    ) throws -> SymmetricKey {
        let publicKey = try publicKey(fromBase64: peerPublicKeyBase64)
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("native-wallet-association-v2:\(origin):\(handshakeId)".utf8),
            sharedInfo: Data("handshake".utf8),
            outputByteCount: 32
        )
    }

    public static func sessionKey(sessionToken: Data, sessionId: String, origin: String) throws -> SymmetricKey {
        try AssociationToken.validate(sessionToken)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: sessionToken),
            salt: Data("native-wallet-association-v2:\(origin):\(sessionId)".utf8),
            info: Data("session".utf8),
            outputByteCount: 32
        )
    }

    public static func seal<T: Encodable>(_ value: T, key: SymmetricKey, encoder: JSONEncoder) throws -> String {
        let plaintext = try encoder.encode(value)
        let sealed = try ChaChaPoly.seal(plaintext, using: key)
        return sealed.combined.base64EncodedString()
    }

    public static func open<T: Decodable>(
        _ type: T.Type,
        sealedBoxBase64: String,
        key: SymmetricKey,
        decoder: JSONDecoder
    ) throws -> T {
        guard let combined = Data(base64Encoded: sealedBoxBase64) else {
            throw WalletAssociationError.invalidEnvelope
        }
        do {
            let sealedBox = try ChaChaPoly.SealedBox(combined: combined)
            let plaintext = try ChaChaPoly.open(sealedBox, using: key)
            return try decoder.decode(type, from: plaintext)
        } catch let error as WalletAssociationError {
            throw error
        } catch {
            throw WalletAssociationError.invalidEnvelope
        }
    }

    public static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw WalletAssociationError.secureRandomUnavailable(status)
        }
        return Data(bytes)
    }
}
