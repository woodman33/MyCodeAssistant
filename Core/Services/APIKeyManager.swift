import Foundation
import Security

// MARK: - API Key Manager
/// Secure API key management using Keychain Services
public class APIKeyManager: APIKeyManagerProtocol {
    
    // MARK: - Constants
    private let service = "com.mycodeassistant.apikeys"
    private let accessGroup: String? = nil // Can be set for app groups
    
    // MARK: - APIKeyManagerProtocol Implementation
    
    public func storeAPIKey(_ key: String, for provider: LLMProvider) throws {
        let account = provider.rawValue
        let data = key.data(using: .utf8) ?? Data()
        
        // First, try to update existing key
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }
        
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        if updateStatus == errSecItemNotFound {
            // Item doesn't exist, create new one
            var newQuery = query
            newQuery[kSecValueData] = data
            newQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            
            let addStatus = SecItemAdd(newQuery as CFDictionary, nil)
            
            if addStatus != errSecSuccess {
                throw KeychainError.storeFailed(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.updateFailed(updateStatus)
        }
    }
    
    public func getAPIKey(for provider: LLMProvider) throws -> String? {
        let account = provider.rawValue
        
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw KeychainError.retrieveFailed(status)
        }
        
        guard let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        
        return key
    }
    
    public func deleteAPIKey(for provider: LLMProvider) throws {
        let account = provider.rawValue
        
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    public func hasAPIKey(for provider: LLMProvider) -> Bool {
        do {
            return try getAPIKey(for: provider) != nil
        } catch {
            return false
        }
    }
    
    public func deleteAllAPIKeys() throws {
        for provider in LLMProvider.allCases {
            try deleteAPIKey(for: provider)
        }
    }
    
    // MARK: - Additional Methods
    
    /// Validates that an API key is properly formatted for the provider
    /// - Parameters:
    ///   - key: The API key to validate
    ///   - provider: The provider the key belongs to
    /// - Returns: True if the key appears valid
    public func validateAPIKey(_ key: String, for provider: LLMProvider) -> Bool {
        // Basic validation - check if key is not empty and meets basic format requirements
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        
        switch provider {
        case .openAI:
            return key.hasPrefix("sk-") && key.count > 20
        case .anthropic:
            return key.hasPrefix("sk-ant-") && key.count > 20
        case .gemini:
            return key.count > 20 // Google API keys don't have a consistent prefix
        case .mistral:
            return key.count > 20
        case .togetherAI:
            return key.count > 20
        case .grok:
            return key.hasPrefix("xai-") && key.count > 20
        case .openRouter:
            return key.hasPrefix("sk-or-") && key.count > 20
        case .portkey:
            return key.count > 20
        }
    }
    
    /// Gets all providers that have stored API keys
    /// - Returns: Array of providers with stored keys
    public func getProvidersWithKeys() -> [LLMProvider] {
        return LLMProvider.allCases.filter { hasAPIKey(for: $0) }
    }
    
    /// Backup API keys to UserDefaults (less secure, for development/testing only)
    /// - Parameter provider: The provider to backup
    /// - Throws: KeychainError if backup fails
    @available(*, deprecated, message: "Use Keychain storage for production")
    public func backupToUserDefaults(for provider: LLMProvider) throws {
        guard let key = try getAPIKey(for: provider) else {
            throw KeychainError.itemNotFound
        }
        
        UserDefaults.standard.set(key, forKey: "backup_\(provider.rawValue)_key")
    }
    
    /// Restore API keys from UserDefaults backup
    /// - Parameter provider: The provider to restore
    /// - Throws: KeychainError if restore fails
    @available(*, deprecated, message: "Use Keychain storage for production")
    public func restoreFromUserDefaults(for provider: LLMProvider) throws {
        guard let key = UserDefaults.standard.string(forKey: "backup_\(provider.rawValue)_key") else {
            throw KeychainError.itemNotFound
        }
        
        try storeAPIKey(key, for: provider)
    }
}

// MARK: - Keychain Error
public enum KeychainError: LocalizedError {
    case storeFailed(OSStatus)
    case updateFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case invalidData
    case itemNotFound
    case accessDenied
    case unexpectedData
    
    public var errorDescription: String? {
        switch self {
        case .storeFailed(let status):
            return "Failed to store API key in Keychain (status: \(status))"
        case .updateFailed(let status):
            return "Failed to update API key in Keychain (status: \(status))"
        case .retrieveFailed(let status):
            return "Failed to retrieve API key from Keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete API key from Keychain (status: \(status))"
        case .invalidData:
            return "Invalid data retrieved from Keychain"
        case .itemNotFound:
            return "API key not found in Keychain"
        case .accessDenied:
            return "Access denied to Keychain item"
        case .unexpectedData:
            return "Unexpected data format in Keychain"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .storeFailed, .updateFailed:
            return "Could not save the API key securely"
        case .retrieveFailed:
            return "Could not access the stored API key"
        case .deleteFailed:
            return "Could not remove the API key"
        case .invalidData, .unexpectedData:
            return "The stored data is corrupted or in an unexpected format"
        case .itemNotFound:
            return "No API key has been stored for this provider"
        case .accessDenied:
            return "The app does not have permission to access this Keychain item"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .storeFailed, .updateFailed:
            return "Please try storing the API key again, or check if the device has sufficient storage space"
        case .retrieveFailed:
            return "Please verify that the API key was properly stored and try again"
        case .deleteFailed:
            return "Please try deleting the API key again"
        case .invalidData, .unexpectedData:
            return "Please delete and re-enter the API key"
        case .itemNotFound:
            return "Please enter and save your API key for this provider"
        case .accessDenied:
            return "Please check the app's Keychain access permissions"
        }
    }
}

// MARK: - UserDefaults API Key Storage (Fallback)
/// Less secure fallback API key storage using UserDefaults
/// Only use this for development/testing or when Keychain is not available
public class UserDefaultsAPIKeyManager: APIKeyManagerProtocol {
    
    private let keyPrefix = "apikey_"
    
    public init() {}
    
    public func storeAPIKey(_ key: String, for provider: LLMProvider) throws {
        let storageKey = keyPrefix + provider.rawValue
        UserDefaults.standard.set(key, forKey: storageKey)
    }
    
    public func getAPIKey(for provider: LLMProvider) throws -> String? {
        let storageKey = keyPrefix + provider.rawValue
        return UserDefaults.standard.string(forKey: storageKey)
    }
    
    public func deleteAPIKey(for provider: LLMProvider) throws {
        let storageKey = keyPrefix + provider.rawValue
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
    
    public func hasAPIKey(for provider: LLMProvider) -> Bool {
        let storageKey = keyPrefix + provider.rawValue
        return UserDefaults.standard.string(forKey: storageKey) != nil
    }
    
    public func deleteAllAPIKeys() throws {
        for provider in LLMProvider.allCases {
            try deleteAPIKey(for: provider)
        }
    }
}