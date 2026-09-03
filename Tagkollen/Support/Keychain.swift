import Foundation
import Security

/// Tiny wrapper around the generic-password keychain item API.
enum Keychain {
    private static let service = "se.tagkollen.app"

    /// `<TeamID>.se.tagkollen.app`; reads search every group the process can access,
    /// so keys stored before the group existed are still found.
    private static var accessGroup: String {
        (Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String ?? "") + SharedStorage.keychainAccessGroup
    }

    static func string(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func set(_ value: String?, for account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return true }
        var attributes = base
        // Shared with the widget extension so widgets can use a user-provided key too.
        attributes[kSecAttrAccessGroup as String] = accessGroup
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}
