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
        // In development mode, try to load from .env file first
        if isEnvironmentFileLoadingEnabled() {
            let envVars = EnvironmentFileLoader.loadEnvironmentFile()
            if let envKey = envVars[provider.apiKeyEnvironmentVariable], !envKey.isEmpty {
                return envKey
            }
        }
        
        // Fall back to Keychain storage
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
        // In development mode, check .env file first
        if isEnvironmentFileLoadingEnabled() {
            let envVars = EnvironmentFileLoader.loadEnvironmentFile()
            if let envKey = envVars[provider.apiKeyEnvironmentVariable], !envKey.isEmpty {
                return true
            }
        }
        
        // Fall back to Keychain check
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
        case .abacusAI:
            return key.count > 16 // Abacus.AI API keys are typically shorter
        case .novita:
            return key.count > 20
        case .huggingFace:
            return key.hasPrefix("hf_") && key.count > 20
        case .moonshot:
            return key.hasPrefix("sk-") && key.count > 20
        }
    }
    
    /// Gets all providers that have stored API keys
    /// - Returns: Array of providers with stored keys
    public func getProvidersWithKeys() -> [LLMProvider] {
        return LLMProvider.allCases.filter { hasAPIKey(for: $0) }
    }
    
    /// Load API keys from .env file if available and enabled for development
    /// This method will only work in development mode and requires ENABLE_ENV_FILE_LOADING=true
    /// - Returns: Dictionary of provider to API key mappings loaded from .env file
    public func loadFromEnvironmentFile() -> [LLMProvider: String] {
        guard isEnvironmentFileLoadingEnabled() else {
            return [:]
        }
        
        var loadedKeys: [LLMProvider: String] = [:]
        let envVars = EnvironmentFileLoader.loadEnvironmentFile()
        
        for provider in LLMProvider.allCases {
            if let apiKey = envVars[provider.apiKeyEnvironmentVariable] {
                loadedKeys[provider] = apiKey
            }
        }
        
        return loadedKeys
    }
    
    /// Check if environment file loading is enabled
    /// - Returns: True if environment file loading should be used
    private func isEnvironmentFileLoadingEnabled() -> Bool {
        // Check both environment variable and process environment
        if let envValue = ProcessInfo.processInfo.environment["ENABLE_ENV_FILE_LOADING"],
           envValue.lowercased() == "true" {
            return true
        }
        
        // Also check if we're in development mode
        if let environment = ProcessInfo.processInfo.environment["ENVIRONMENT"],
           environment.lowercased() == "development" {
            return true
        }
        
        #if DEBUG
        return true // Always allow in debug builds
        #else
        return false
        #endif
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

// MARK: - Environment File Loader
/// Utility class for loading environment variables from .env files
public class EnvironmentFileLoader {
    
    /// Load environment variables from .env file
    /// - Returns: Dictionary of environment variables loaded from file
    public static func loadEnvironmentFile() -> [String: String] {
        guard let envPath = findEnvironmentFile() else {
            return [:]
        }
        
        return loadEnvironmentFile(from: envPath)
    }
    
    /// Load environment variables from a specific file path
    /// - Parameter path: Path to the .env file
    /// - Returns: Dictionary of environment variables
    public static func loadEnvironmentFile(from path: String) -> [String: String] {
        var envVars: [String: String] = [:]
        
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return envVars
        }
        
        let lines = contents.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines and comments
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }
            
            // Parse KEY=VALUE format
            let components = trimmedLine.components(separatedBy: "=")
            guard components.count >= 2 else {
                continue
            }
            
            let key = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = components.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Remove quotes if present
            let cleanValue = value.replacingOccurrences(of: "^[\"']|[\"']$", with: "", options: .regularExpression)
            
            envVars[key] = cleanValue
        }
        
        return envVars
    }
    
    /// Find the .env file in the project hierarchy
    /// - Returns: Path to .env file if found
    private static func findEnvironmentFile() -> String? {
        let fileManager = FileManager.default
        var currentPath = fileManager.currentDirectoryPath
        
        // Try to find .env file in current directory and parent directories
        for _ in 0..<5 { // Limit search to 5 levels up
            let envPath = (currentPath as NSString).appendingPathComponent(".env")
            
            if fileManager.fileExists(atPath: envPath) {
                return envPath
            }
            
            // Move up one directory
            let parentPath = (currentPath as NSString).deletingLastPathComponent
            if parentPath == currentPath {
                break // Reached root directory
            }
            currentPath = parentPath
        }
        
        // Also check common project locations
        let commonPaths = [
            Bundle.main.bundlePath,
            Bundle.main.resourcePath ?? "",
            NSHomeDirectory(),
        ]
        
        for basePath in commonPaths {
            let envPath = (basePath as NSString).appendingPathComponent(".env")
            if fileManager.fileExists(atPath: envPath) {
                return envPath
            }
        }
        
        return nil
    }
}