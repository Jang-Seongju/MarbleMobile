import Foundation
import Security

struct SavedLogin {
    var username: String
    var password: String
    var saveEnabled: Bool
}

final class CredentialStore {
    private let defaults = UserDefaults.standard
    private let usernameKey = "savedLogin.username"
    private let saveKey = "savedLogin.enabled"
    private let service = "MarbleGame"

    func load() -> SavedLogin {
        let enabled = defaults.bool(forKey: saveKey)
        guard enabled else { return SavedLogin(username: "", password: "", saveEnabled: false) }
        let username = defaults.string(forKey: usernameKey) ?? ""
        return SavedLogin(username: username, password: loadPassword(username: username), saveEnabled: true)
    }

    func save(username: String, password: String) {
        let previous = defaults.string(forKey: usernameKey) ?? ""
        if !previous.isEmpty && previous != username { deletePassword(username: previous) }
        defaults.set(username, forKey: usernameKey)
        defaults.set(true, forKey: saveKey)
        savePassword(username: username, password: password)
    }

    func clear(currentUsername: String) {
        let previous = defaults.string(forKey: usernameKey) ?? ""
        defaults.removeObject(forKey: usernameKey)
        defaults.set(false, forKey: saveKey)
        if !previous.isEmpty { deletePassword(username: previous) }
        if !currentUsername.isEmpty && currentUsername != previous { deletePassword(username: currentUsername) }
    }

    private func savePassword(username: String, password: String) {
        deletePassword(username: username)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username,
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadPassword(username: String) -> String {
        guard !username.isEmpty else { return "" }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func deletePassword(username: String) {
        guard !username.isEmpty else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
