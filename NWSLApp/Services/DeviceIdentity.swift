//
//  DeviceIdentity.swift
//  NWSLApp
//
//  A stable identifier for THIS physical device, used as the `device_id` that keys the server-side
//  token tables (`device_tokens`, `live_activity_start_tokens`). It exists to fix a real token-lifecycle
//  bug: APNs tokens rotate (reinstall, restore, iOS update), and the old design keyed rows on
//  `(user_id, token)` — so every rotation ADDED a row and never removed the old one. The watcher then
//  fanned pushes out to a pile of dead "zombie" tokens (the Live Activity V2 no-render root cause).
//
//  Keying on `(user_id, device_id)` instead makes each device keep exactly ONE current token
//  (replace-on-rotation), while still letting the SAME user receive pushes on multiple devices (iPhone +
//  iPad → two device_ids → two rows). The watcher additionally self-prunes tokens APNs rejects.
//
//  Why the Keychain (not `identifierForVendor`): the Keychain SURVIVES app reinstall, so a reinstall
//  reuses the same `device_id` and the upsert replaces the token in place — no zombie row. IDFV resets
//  on a full uninstall, which would reintroduce accumulation. The Keychain item is also never nil.
//

import Foundation
import Security

enum DeviceIdentity {
    private static let service = "com.tiffanyrieth.nwslapp.deviceid"
    private static let account = "device-uuid"

    /// This device's stable UUID — generated once on first access and cached in the Keychain forever
    /// (survives reinstall). Synchronous and non-optional: token uploads always have a `device_id`.
    static let deviceID: String = {
        if let existing = read() { return existing }
        let fresh = UUID().uuidString
        write(fresh)
        return fresh
    }()

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    private static func write(_ value: String) {
        SecItemDelete(baseQuery as CFDictionary) // idempotent — clear any prior item first
        var add = baseQuery
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
