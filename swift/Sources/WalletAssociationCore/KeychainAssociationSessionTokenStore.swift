import Foundation
import Security

public final class KeychainAssociationSessionTokenStore: AssociationSessionTokenStore, @unchecked Sendable {
    private let service: String

    public init(service: String = "com.walletassociation.sessions") {
        self.service = service
    }

    public func store(sessionId: String, token: Data) throws {
        try delete(sessionId: sessionId)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(sessionId),
            kSecValueData as String: token,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        var status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecMissingEntitlement {
            var fallback = query
            fallback[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            status = SecItemAdd(fallback as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw WalletAssociationError.keychainStoreFailed(status)
        }
    }

    public func load(sessionId: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(sessionId),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw WalletAssociationError.sessionNotFound
            }
            throw WalletAssociationError.keychainReadFailed(status)
        }
        guard let data = result as? Data else {
            throw WalletAssociationError.keychainReadFailed(errSecDecode)
        }
        return data
    }

    public func delete(sessionId: String) throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(sessionId)
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound || status == errSecMissingEntitlement else {
            throw WalletAssociationError.keychainDeleteFailed(status)
        }
    }

    public func deleteAll(sessionIds: [String]) throws {
        for sessionId in sessionIds {
            try delete(sessionId: sessionId)
        }
    }

    private func account(_ sessionId: String) -> String {
        "session-\(sessionId)"
    }
}

