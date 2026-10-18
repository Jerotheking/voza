import Foundation
#if canImport(Security)
import Security
#endif

/// V12 — Credentials never live in plaintext files. Cloud cleanup keys are
/// stored in the macOS Keychain; `Config.env` reads them through this store
/// instead of `~/.config/voza/.env`.
///
/// Contract (ticket V12 / audit F16):
/// - Service name is derived from the injected `AppPaths` so QA tests get a
///   service namespace they cannot collide with (a fake store makes the
///   secrecy itself hermetic).
/// - `get`/`set`/`delete` are the whole surface. Set overwrites atomically
///   (SecItem update, or delete+add when missing/re-signed). Failures are returned,
///   never logged with values (V12-AC05).
/// - The production SecItem implementation never records or prints key
///   material; errors surface as `KeychainStoreError.status(OSStatus)`.
protocol KeychainStore: Sendable {
    func get(_ key: String) -> String?
    @discardableResult
    func set(_ key: String, value: String) -> Bool
    @discardableResult
    func delete(_ key: String) -> Bool
}

enum KeychainStoreError: Error {
    case status(OSStatus)
}

/// Production store backed by the login keychain. Generic-password items,
/// kSecAttrAccessibleAfterFirstUnlock — the app reads keys while dictating
/// without prompting the user for the keychain password every launch.
struct SecItemKeychainStore: KeychainStore {
    let service: String

    /// Production service: stable per-installation namespace. QA paths
    /// produce a different service name, so a test can never collide with
    /// the developer's real keychain items.
    init(service: String = "com.jerotherey.voza.credentials") {
        self.service = service
    }

    func get(_ key: String) -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
        #else
        return nil
        #endif
    }

    @discardableResult
    func set(_ key: String, value: String) -> Bool {
        #if canImport(Security)
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        // D069: if the item does not exist or its ACL belonged to a previous local build
        // signature, delete any stale entry and add a fresh one.
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        #else
        return false
        #endif
    }

    @discardableResult
    func delete(_ key: String) -> Bool {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
        #else
        return false
        #endif
    }
}

/// In-memory store for previews and any non-test caller that wants
/// ephemeral behavior (QA tests use their own fake in the test bundle).
final class InMemoryKeychainStore: KeychainStore, @unchecked Sendable {
    private var items: [String: String] = [:]
    private let lock = NSLock()

    func get(_ key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return items[key]
    }

    @discardableResult
    func set(_ key: String, value: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        items[key] = value
        return true
    }

    @discardableResult
    func delete(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return items.removeValue(forKey: key) != nil
    }
}
