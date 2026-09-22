import Foundation
import Security
import LocalAuthentication

enum KeychainError: Error {
    case noData
    case unhandledError(status: OSStatus)
    case authenticationFailed(String)
}

struct Keychain {
    private static let service = "com.jondaley.calendar-sync"
    private static let account = "google-refresh-token"

    // Plain Keychain item, no kSecAttrAccessControl: an OS-enforced biometric ACL
    // requires the Data Protection Keychain, which in turn requires the app be
    // signed with a real Team ID. Without one (ad-hoc "Sign to Run Locally"
    // signing), SecItemAdd fails with errSecMissingEntitlement (-34018). Instead,
    // Touch ID is enforced here in app code via LocalAuthentication before reading.
    private static func authenticate(reason: String) throws {
        let context = LAContext()
        var evalError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evalError) else {
            // No biometrics or passcode available on this machine/session; skip gating.
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        var authError: Error?

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { result, error in
            success = result
            authError = error
            semaphore.signal()
        }

        semaphore.wait()

        guard success else {
            let message = authError?.localizedDescription ?? "Authentication failed"
            throw KeychainError.authenticationFailed(message)
        }
    }

    static func save(_ value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.noData
        }

        // Remove any existing item first; SecItemAdd fails if one is already present.
        try? delete()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    static func load() throws -> String {
        try authenticate(reason: "Unlock calendar-sync to access your Google refresh token")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.noData
            }
            throw KeychainError.unhandledError(status: status)
        }

        guard let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.noData
        }

        return token
    }

    static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }
}
