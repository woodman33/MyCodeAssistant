import Foundation

// MARK: - Shared Services Container
/// Container for services shared between the main app and extension
public class SharedServices {
    
    // MARK: - Singleton
    public static let shared = SharedServices()
    
    // MARK: - Services
    public let apiKeyManager: APIKeyManagerProtocol
    public let configurationManager: ConfigurationManagerProtocol
    public let providerFactory: ProviderFactory
    public let conversationManager: ConversationManagerProtocol
    public let settingsManager: SettingsManagerProtocol
    public let networkManager: NetworkManagerProtocol
    
    private init() {
        // Initialize core services
        self.apiKeyManager = APIKeyManager()
        self.configurationManager = ConfigurationManager()
        self.providerFactory = ProviderFactory.shared
        self.conversationManager = ConversationManager()
        self.settingsManager = SettingsManager()
        self.networkManager = NetworkManager()
    }
    
    // MARK: - Service Access
    
    /// Gets a configured LLM provider for the specified type
    /// - Parameter provider: The provider type
    /// - Returns: Configured provider instance
    /// - Throws: ServiceError if provider cannot be created
    public func getProvider(_ provider: LLMProvider) throws -> LLMProviderProtocol {
        return try providerFactory.createProvider(provider)
    }
    
    /// Gets the default configured provider based on app settings
    /// - Returns: Default provider instance
    /// - Throws: ServiceError if no default provider is configured
    public func getDefaultProvider() throws -> LLMProviderProtocol {
        let settings = settingsManager.getSettings()
        return try providerFactory.createProvider(settings.defaultProvider)
    }
    
    /// Validates service configuration and connectivity
    /// - Returns: ServiceHealthStatus indicating the health of all services
    public func checkServiceHealth() async -> ServiceHealthStatus {
        var issues: [ServiceIssue] = []
        
        // Check API key availability
        let providersWithKeys = apiKeyManager.getProvidersWithKeys()
        if providersWithKeys.isEmpty {
            issues.append(.noAPIKeysConfigured)
        }
        
        // Check network connectivity
        let networkStatus = await networkManager.checkConnectivity()
        if !networkStatus.isConnected {
            issues.append(.networkUnavailable)
        }
        
        // Check default provider availability
        do {
            _ = try getDefaultProvider()
        } catch {
            issues.append(.defaultProviderUnavailable)
        }
        
        let status: ServiceHealthStatus.Status = issues.isEmpty ? .healthy : .degraded
        return ServiceHealthStatus(status: status, issues: issues, lastChecked: Date())
    }
}

// MARK: - Service Health Status
public struct ServiceHealthStatus {
    public enum Status {
        case healthy
        case degraded
        case unavailable
    }
    
    public let status: Status
    public let issues: [ServiceIssue]
    public let lastChecked: Date
    
    public init(status: Status, issues: [ServiceIssue], lastChecked: Date) {
        self.status = status
        self.issues = issues
        self.lastChecked = lastChecked
    }
}

// MARK: - Service Issue
public enum ServiceIssue {
    case noAPIKeysConfigured
    case networkUnavailable
    case defaultProviderUnavailable
    case keychainAccessDenied
    case configurationCorrupted
    case providerAuthenticationFailed(LLMProvider)
    case rateLimitExceeded(LLMProvider)
    
    public var description: String {
        switch self {
        case .noAPIKeysConfigured:
            return "No API keys are configured"
        case .networkUnavailable:
            return "Network connection is unavailable"
        case .defaultProviderUnavailable:
            return "Default provider is not available"
        case .keychainAccessDenied:
            return "Keychain access is denied"
        case .configurationCorrupted:
            return "Configuration data is corrupted"
        case .providerAuthenticationFailed(let provider):
            return "Authentication failed for \(provider.displayName)"
        case .rateLimitExceeded(let provider):
            return "Rate limit exceeded for \(provider.displayName)"
        }
    }
    
    public var severity: ServiceIssueSeverity {
        switch self {
        case .noAPIKeysConfigured, .defaultProviderUnavailable:
            return .high
        case .networkUnavailable, .keychainAccessDenied, .configurationCorrupted:
            return .critical
        case .providerAuthenticationFailed, .rateLimitExceeded:
            return .medium
        }
    }
}

// MARK: - Service Issue Severity
public enum ServiceIssueSeverity {
    case low
    case medium
    case high
    case critical
}

// MARK: - Service Error
public enum ServiceError: LocalizedError {
    case providerUnavailable(LLMProvider)
    case configurationError(String)
    case networkError(Error)
    case authenticationError(LLMProvider, Error)
    case serviceUnavailable(String)
    
    public var errorDescription: String? {
        switch self {
        case .providerUnavailable(let provider):
            return "Provider \(provider.displayName) is not available"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .authenticationError(let provider, let error):
            return "Authentication error for \(provider.displayName): \(error.localizedDescription)"
        case .serviceUnavailable(let service):
            return "Service \(service) is unavailable"
        }
    }
}

// MARK: - Settings Manager Protocol
public protocol SettingsManagerProtocol {
    func getSettings() -> AppSettings
    func updateSettings(_ settings: AppSettings) throws
    func resetToDefaults() throws
}

// MARK: - Settings Manager Implementation
public class SettingsManager: SettingsManagerProtocol {
    
    private let userDefaults: UserDefaults
    private let settingsKey = "app_settings"
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    public func getSettings() -> AppSettings {
        guard let data = userDefaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return settings
    }
    
    public func updateSettings(_ settings: AppSettings) throws {
        let data = try JSONEncoder().encode(settings)
        userDefaults.set(data, forKey: settingsKey)
    }
    
    public func resetToDefaults() throws {
        userDefaults.removeObject(forKey: settingsKey)
    }
}

// MARK: - Configuration Manager Protocol
public protocol ConfigurationManagerProtocol {
    func getConfiguration(for provider: LLMProvider) -> ProviderConfiguration
    func updateConfiguration(for provider: LLMProvider, configuration: ProviderConfiguration)
    func getAllConfigurations() -> [ProviderConfiguration]
    func resetConfiguration(for provider: LLMProvider)
}

// MARK: - Configuration Manager Implementation
public class ConfigurationManager: ConfigurationManagerProtocol {
    
    private let userDefaults: UserDefaults
    private let configurationPrefix = "provider_config_"
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    public func getConfiguration(for provider: LLMProvider) -> ProviderConfiguration {
        let key = configurationPrefix + provider.rawValue
        
        guard let data = userDefaults.data(forKey: key),
              let configuration = try? JSONDecoder().decode(ProviderConfiguration.self, from: data) else {
            return createDefaultConfiguration(for: provider)
        }
        
        return configuration
    }
    
    public func updateConfiguration(for provider: LLMProvider, configuration: ProviderConfiguration) {
        let key = configurationPrefix + provider.rawValue
        
        do {
            let data = try JSONEncoder().encode(configuration)
            userDefaults.set(data, forKey: key)
        } catch {
            print("Failed to save configuration for \(provider.displayName): \(error)")
        }
    }
    
    public func getAllConfigurations() -> [ProviderConfiguration] {
        return LLMProvider.allCases.map { getConfiguration(for: $0) }
    }
    
    public func resetConfiguration(for provider: LLMProvider) {
        let key = configurationPrefix + provider.rawValue
        userDefaults.removeObject(forKey: key)
    }
    
    private func createDefaultConfiguration(for provider: LLMProvider) -> ProviderConfiguration {
        let defaultModels = provider.defaultModels.map { modelName in
            ModelConfiguration(
                provider: provider,
                modelName: modelName,
                displayName: modelName,
                maxTokens: provider.maxTokensLimit,
                supportsSystemPrompt: provider.supportsSystemPrompt,
                supportsFunctions: provider.supportsFunctions
            )
        }
        
        return ProviderConfiguration(
            provider: provider,
            baseURL: provider.baseURL,
            apiKeyRequired: provider.requiresAPIKey,
            supportedModels: defaultModels
        )
    }
}

// MARK: - Network Manager Protocol
public protocol NetworkManagerProtocol {
    func checkConnectivity() async -> NetworkStatus
    func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse)
    func performStreamingRequest(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error>
}

// MARK: - Network Status
public struct NetworkStatus {
    public let isConnected: Bool
    public let connectionType: ConnectionType
    public let lastChecked: Date
    
    public init(isConnected: Bool, connectionType: ConnectionType, lastChecked: Date = Date()) {
        self.isConnected = isConnected
        self.connectionType = connectionType
        self.lastChecked = lastChecked
    }
}

// MARK: - Connection Type
public enum ConnectionType {
    case wifi
    case cellular
    case ethernet
    case unknown
}

// MARK: - Network Manager Implementation
public class NetworkManager: NetworkManagerProtocol {
    
    private let urlSession: URLSession
    
    public init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.urlSession = URLSession(configuration: configuration)
    }
    
    public func checkConnectivity() async -> NetworkStatus {
        // Simple connectivity check by attempting to reach a reliable endpoint
        let url = URL(string: "https://www.google.com")!
        let request = URLRequest(url: url, timeoutInterval: 10)
        
        do {
            _ = try await urlSession.data(for: request)
            return NetworkStatus(isConnected: true, connectionType: .unknown)
        } catch {
            return NetworkStatus(isConnected: false, connectionType: .unknown)
        }
    }
    
    public func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        return try await urlSession.data(for: request)
    }
    
    public func performStreamingRequest(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error> {
        return AsyncThrowingStream { continuation in
            let task = urlSession.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.finish(throwing: error)
                    return
                }
                
                if let data = data {
                    continuation.yield(data)
                }
                
                continuation.finish()
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
            
            task.resume()
        }
    }
}