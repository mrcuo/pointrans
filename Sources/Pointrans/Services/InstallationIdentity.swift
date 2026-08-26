@preconcurrency import Security
import Foundation

actor InstallationIdentity: InstallationIdentityProviding {
    enum IdentityError: Error, Sendable {
        case keychain(OSStatus)
        case invalidValue
    }

    private enum Account {
        static let installationID = "installation-id-v2"
        static let bearerToken = "installation-token-v2"
    }

    private let service: String

    init(service: String = "com.tailcasso.Pointrans.cloud") {
        self.service = service
    }

    func installationID() throws -> UUID {
        if let stored = try read(Account.installationID), let id = UUID(uuidString: stored) {
            return id
        }
        let id = UUID()
        try write(id.uuidString.lowercased(), account: Account.installationID)
        return id
    }

    func bearerToken() throws -> String? {
        try read(Account.bearerToken)
    }

    func storeBearerToken(_ token: String) throws {
        guard !token.isEmpty else { throw IdentityError.invalidValue }
        try write(token, account: Account.bearerToken)
    }

    func clearBearerToken() throws {
        let status = SecItemDelete(query(account: Account.bearerToken) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw IdentityError.keychain(status)
        }
    }

    private func read(_ account: String) throws -> String? {
        var request = query(account: account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var raw: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &raw)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = raw as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw IdentityError.keychain(status)
        }
        return value
    }

    private func write(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let base = query(account: account)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = base
            insert[kSecValueData as String] = data
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else { throw IdentityError.keychain(insertStatus) }
        } else if status != errSecSuccess {
            throw IdentityError.keychain(status)
        }
    }

    private func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
    }
}
