import Foundation
import Security

enum APIKey: String, CaseIterable {
    case soniox = "soniox-api-key"
    case gemini = "gemini-api-key"
    case deepgram = "deepgram-api-key"
}

/// API keys in UserDefaults (plain plist, personal app). Not Keychain: with a self-signed
/// app every read asked for the login password. See docs/DECISIONS.md D31.
enum APIKeys {
    static func get(_ key: APIKey, defaults: UserDefaults = .standard) -> String? {
        guard let value = defaults.string(forKey: key.rawValue), !value.isEmpty else { return nil }
        return value
    }

    static func set(_ value: String?, for key: APIKey, defaults: UserDefaults = .standard) {
        if let value, !value.isEmpty {
            defaults.set(value, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    /// One-time move of keys saved by older builds from Keychain (service `ProjectRecord`).
    /// May ask for the password once; never again after that.
    static func migrateFromKeychain(defaults: UserDefaults = .standard) {
        let doneKey = "apiKeysMigratedFromKeychain"
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)
        for key in APIKey.allCases {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "ProjectRecord",
                kSecAttrAccount as String: key.rawValue,
                kSecReturnData as String: true,
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { continue }
            if get(key, defaults: defaults) == nil { set(String(decoding: data, as: UTF8.self), for: key, defaults: defaults) }
            query.removeValue(forKey: kSecReturnData as String)
            SecItemDelete(query as CFDictionary)
        }
    }
}
