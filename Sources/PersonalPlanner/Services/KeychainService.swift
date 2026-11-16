import Foundation
import Security

/// Thread-safe, serialized macOS Keychain service with in-memory session caching.
///
/// Addresses repeated macOS permission dialogs by:
/// 1. Caching credentials in memory for the session once read or written.
/// 2. Serializing all Keychain queries through a dedicated serial queue to prevent concurrent prompts.
/// 3. Updating existing Keychain items in-place with `SecItemUpdate` instead of deleting and recreating them
///    (which previously destroyed the Access Control List authorization granted by "Always Allow").
/// 4. Remembering cancelled/denied user decisions for the session to prevent dialog loops.
public final class KeychainService: KeychainServiceProtocol, @unchecked Sendable {
    private let serviceName = "com.personalplanner.credentials"
    
    // Thread-safe in-memory cache and denial tracking
    private var inMemoryStore: [String: String] = [:]
    private var deniedOrFailedKeys: Set<String> = []
    private let lock = NSLock()
    
    // Serial queue to serialize all macOS Keychain API calls
    private let queue = DispatchQueue(label: "com.personalplanner.keychain.queue", qos: .userInitiated)
    
    public init() {}
    
    public func saveCredential(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }
        
        // 1. Update in-memory session store immediately
        lock.withLock {
            inMemoryStore[key] = value
            deniedOrFailedKeys.remove(key)
        }
        
        // 2. Persist to macOS Keychain via SecItemUpdate (preserving existing ACL)
        // or SecItemAdd if it does not yet exist.
        queue.sync {
            let searchQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: key
            ]
            
            let updateAttributes: [String: Any] = [
                kSecValueData as String: data
            ]
            
            let updateStatus = SecItemUpdate(searchQuery as CFDictionary, updateAttributes as CFDictionary)
            
            if updateStatus == errSecItemNotFound {
                // Item does not exist yet: create it with SecItemAdd
                var addQuery = searchQuery
                addQuery[kSecValueData as String] = data
                let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
                if addStatus != errSecSuccess && addStatus != errSecDuplicateItem {
                    print("ℹ️ Keychain save notice: SecItemAdd returned \(addStatus). In-memory cache is active.")
                }
            } else if updateStatus != errSecSuccess {
                print("ℹ️ Keychain update notice: SecItemUpdate returned \(updateStatus). In-memory cache is active.")
            }
        }
    }
    
    public func getCredential(key: String) -> String? {
        // 1. Fast path: check in-memory session cache first
        if let cached = lock.withLock({ inMemoryStore[key] }) {
            return cached
        }
        
        // 2. If access was already denied or cancelled by user, or not found this session,
        // do not reopen the system dialog repeatedly.
        if lock.withLock({ deniedOrFailedKeys.contains(key) }) {
            return nil
        }
        
        // 3. Serialized query to macOS Keychain
        return queue.sync {
            // Re-check cache inside serialization block
            if let cached = lock.withLock({ inMemoryStore[key] }) {
                return cached
            }
            if lock.withLock({ deniedOrFailedKeys.contains(key) }) {
                return nil
            }
            
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            
            var dataTypeRef: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
            
            if status == errSecSuccess, let data = dataTypeRef as? Data, let str = String(data: data, encoding: .utf8) {
                lock.withLock {
                    inMemoryStore[key] = str
                }
                return str
            }
            
            // Handle cancellation, denial, or item not found
            lock.withLock {
                _ = deniedOrFailedKeys.insert(key)
            }
            
            if status == errSecAuthFailed || status == errSecUserCanceled || status == -128 || status == errSecInteractionNotAllowed {
                print("ℹ️ Keychain access cancelled or not granted for item. It will not be re-requested this session.")
            }
            
            return nil
        }
    }
    
    public func deleteCredential(key: String) throws {
        lock.withLock {
            inMemoryStore.removeValue(forKey: key)
            deniedOrFailedKeys.remove(key)
        }
        
        queue.sync {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: key
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
    
    /// Reset session denial cache if the user explicitly triggers an authentication or retry action.
    public func resetSessionCache() {
        lock.withLock {
            deniedOrFailedKeys.removeAll()
        }
    }
}

/// Keychain stand-in used by the command-line test suites, so tests never read the user's real
/// credentials or trigger macOS "allow access" prompts (each rebuild changes the ad-hoc signature).
public final class InMemoryKeychainService: KeychainServiceProtocol {
    private var store: [String: String] = [:]
    public init() {}
    public func saveCredential(key: String, value: String) throws { store[key] = value }
    public func getCredential(key: String) -> String? { store[key] }
    public func deleteCredential(key: String) throws { store.removeValue(forKey: key) }
}
