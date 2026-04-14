//
//  SpotifyTokenStore.swift
//  Lightify
//

import Foundation
import Security

enum SpotifyTokenStore {
    private static let service = "wss.Lightify.spotify.oauth"
    private static let account = "default"

    static func save(_ session: StoredSpotifySession) throws {
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var newQuery = query
        newQuery[kSecValueData as String] = data
        newQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(newQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TokenStoreError.keychain(status)
        }
    }

    static func load() throws -> StoredSpotifySession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw TokenStoreError.keychain(status)
        }
        return try JSONDecoder().decode(StoredSpotifySession.self, from: data)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum TokenStoreError: Error {
        case keychain(OSStatus)
    }
}
