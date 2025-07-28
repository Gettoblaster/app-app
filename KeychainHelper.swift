//
//  KeychainHelper.swift
//  YourAppName
//
//  Created by You on YYYY/MM/DD.
//

import Foundation
import Security

/// Hilfsklasse zum Speichern und Laden von Strings in der Keychain
class KeychainHelper {
    static let standard = KeychainHelper()
    private init() {}

    func save(_ value: String, service: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        // Vorhandenen Eintrag löschen
        SecItemDelete(query as CFDictionary)
        // Neuen Eintrag anlegen
        let attributes: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData:   data
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func read(service: String, account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    func delete(service: String, account: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
