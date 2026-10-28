import Foundation
import Security

/// Stores app passwords and the API key in the macOS login keychain.
enum Keychain {
    private static let service = "com.clutterclear.app"
    /// Items saved before the app was renamed from Inbox Cleaner.
    private static let legacyService = "com.inboxcleaner.app"

    private static func baseQuery(_ key: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    static func set(_ value: String, for key: String) {
        SecItemDelete(baseQuery(key, service: service) as CFDictionary)
        SecItemDelete(baseQuery(key, service: legacyService) as CFDictionary)
        guard !value.isEmpty else { return }
        var add = baseQuery(key, service: service)
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func read(_ key: String, service: String) -> String? {
        var query = baseQuery(key, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func get(_ key: String) -> String? {
        if let value = read(key, service: service) { return value }
        // Move a pre-rename item over the first time it's read.
        guard let legacy = read(key, service: legacyService) else { return nil }
        set(legacy, for: key)
        return legacy
    }

    static func delete(_ key: String) { set("", for: key) }
}
