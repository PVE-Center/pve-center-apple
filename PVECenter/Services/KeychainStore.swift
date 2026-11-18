import Foundation
import Security

/// Errors raised when accessing the Apple Keychain for server credentials.
public enum KeychainStoreError: LocalizedError, Sendable, Equatable {
    case invalidData
    case unexpectedStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Les données d'authentification sont corrompues ou invalides."
        case .unexpectedStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Erreur Keychain (\(status)) : \(message)"
            }
            return "Erreur Keychain inattendue (code \(status))."
        }
    }
}

/// Logical secret namespaces stored per server profile in Keychain.
public enum KeychainSecretKind: String, Sendable, CaseIterable {
    case apiToken = "api_token"
    case pairingSecret = "pairing_secret"
    case proxmoxToken = "proxmox_token"
    case onboardingToken = "onboarding_token"
    case sessionToken = "session_token"
}

/// Thread-safe, `Sendable` Keychain wrapper (`kSecClassGenericPassword`) keyed by server profile ID.
/// Uses standard application Keychain items without requiring paid keychain-access-groups entitlements.
public struct KeychainStore: Sendable {
    public static let shared = KeychainStore()

    public let serviceName: String

    public init(serviceName: String = "io.ac.pvepanel.app.credentials") {
        self.serviceName = serviceName
    }

    // MARK: - Profile-Keyed Typed Secrets

    public nonisolated func saveSecret(
        _ value: String,
        kind: KeychainSecretKind,
        profileID: UUID
    ) throws {
        try saveString(value, account: accountKey(profileID: profileID, kind: kind))
    }

    public nonisolated func readSecret(
        kind: KeychainSecretKind,
        profileID: UUID
    ) throws -> String? {
        try readString(account: accountKey(profileID: profileID, kind: kind))
    }

    public nonisolated func deleteSecret(
        kind: KeychainSecretKind,
        profileID: UUID
    ) throws {
        try deleteData(account: accountKey(profileID: profileID, kind: kind))
    }

    public nonisolated func deleteAllSecrets(profileID: UUID) throws {
        for kind in KeychainSecretKind.allCases {
            try deleteSecret(kind: kind, profileID: profileID)
        }
    }

    // MARK: - Bearer Token Convenience

    public nonisolated func saveBearerToken(_ token: String, profileID: UUID) throws {
        try saveSecret(token, kind: .apiToken, profileID: profileID)
    }

    public nonisolated func readBearerToken(profileID: UUID) -> String? {
        try? readSecret(kind: .apiToken, profileID: profileID)
    }

    public nonisolated func deleteBearerToken(profileID: UUID) throws {
        try deleteSecret(kind: .apiToken, profileID: profileID)
    }

    // MARK: - Generic Account-Keyed Operations

    public nonisolated func saveString(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        try saveData(data, account: account)
    }

    public nonisolated func readString(account: String) throws -> String? {
        guard let data = try readData(account: account) else {
            return nil
        }
        guard let decoded = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.invalidData
        }
        return decoded
    }

    public nonisolated func saveData(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)
        let updateAttributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainStoreError.unexpectedStatus(addStatus)
            }
            return
        }

        throw KeychainStoreError.unexpectedStatus(updateStatus)
    }

    public nonisolated func readData(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainStoreError.invalidData
        }
        return data
    }

    public nonisolated func deleteData(account: String) throws {
        let query = baseQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }
        throw KeychainStoreError.unexpectedStatus(status)
    }

    // MARK: - Helpers

    private nonisolated func accountKey(profileID: UUID, kind: KeychainSecretKind) -> String {
        "\(profileID.uuidString.lowercased()):\(kind.rawValue)"
    }

    private nonisolated func baseQuery(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: account,
        ]
    }
}
