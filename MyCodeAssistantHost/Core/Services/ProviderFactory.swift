import Foundation

// MARK: - Provider Factory
/// Factory for creating LLM provider instances with enhanced registration system
public class ProviderFactory {
    
    // MARK: - Singleton
    public static let shared = ProviderFactory()
    
    private let apiKeyManager: APIKeyManagerProtocol
    private let configurationManager: ConfigurationManagerProtocol
    
    // Enhanced registration system
    private var providerRegistry: [LLMProvider: ProviderInfo] = [:]
    
    private init() {
        self.apiKeyManager = APIKeyManager()
        self.configurationManager = ConfigurationManager()
        
        // Register all available providers
        setupProviderRegistry()
    }
    
    /// Setup the provider registry with all available providers
    private func setupProviderRegistry() {
        // MVP providers (implemented)
        registerProvider(.openAI, 
                        status: .implemented, 
                        priority: .high)
        registerProvider(.openRouter, 
                        status: .implemented, 
                        priority: .high)
    }
    
    /// Register a provider with metadata
    private func registerProvider(_ provider: LLMProvider, 
                                 status: ProviderStatus, 
                                 priority: ProviderPriority) {
        let info = ProviderInfo(
            provider: provider,
            status: status,
            priority: priority,
            registeredAt: Date()
        )
        providerRegistry[provider] = info
    }
    
    // MARK: - Provider Creation
    
    /// Creates a provider instance for the specified provider type
    /// - Parameter provider: The provider type to create
    /// - Returns: A configured provider instance
    /// - Throws: ProviderError if creation fails
    public func createProvider(_ provider: LLMProvider) throws -> LLMProviderProtocol {
        let apiKey = try apiKeyManager.getAPIKey(for: provider)
        let configuration = configurationManager.getConfiguration(for: provider)
        
        switch provider {
        case .openAI:
            return OpenAIProvider(apiKey: apiKey, configuration: configuration)
        case .openRouter:
            return OpenRouterProvider(apiKey: apiKey, configuration: configuration)
        }
    }
    
    /// Creates a provider instance with a specific API key
    /// - Parameters:
    ///   - provider: The provider type to create
    ///   - apiKey: The API key to use
    /// - Returns: A configured provider instance
    /// - Throws: ProviderError if creation fails
    public func createProvider(_ provider: LLMProvider, apiKey: String) throws -> LLMProviderProtocol {
        let configuration = configurationManager.getConfiguration(for: provider)
        
        switch provider {
        case .openAI:
            return OpenAIProvider(apiKey: apiKey, configuration: configuration)
        case .openRouter:
            return OpenRouterProvider(apiKey: apiKey, configuration: configuration)
        }
    }
    
    /// Validates that a provider can be created (has API key and valid configuration)
    /// - Parameter provider: The provider to validate
    /// - Returns: True if provider can be created, false otherwise
    public func canCreateProvider(_ provider: LLMProvider) -> Bool {
        do {
            _ = try apiKeyManager.getAPIKey(for: provider)
            let configuration = configurationManager.getConfiguration(for: provider)
            return configuration.apiKeyRequired ? true : true
        } catch {
            return false
        }
    }
    
    /// Gets all available providers that can be created
    /// - Returns: Array of providers that have valid configurations and API keys
    public func getAvailableProviders() -> [LLMProvider] {
        return LLMProvider.allCases.filter { canCreateProvider($0) }
    }
    
    // MARK: - Enhanced Registry Methods
    
    /// Get all registered providers
    /// - Returns: Array of all registered providers
    public func getAllRegisteredProviders() -> [LLMProvider] {
        return Array(providerRegistry.keys).sorted { $0.displayName < $1.displayName }
    }
    
    /// Get providers by status
    /// - Parameter status: The status to filter by
    /// - Returns: Array of providers with the specified status
    public func getProviders(withStatus status: ProviderStatus) -> [LLMProvider] {
        return providerRegistry.compactMap { key, value in
            value.status == status ? key : nil
        }.sorted { $0.displayName < $1.displayName }
    }
    
    /// Get providers by priority
    /// - Parameter priority: The priority to filter by
    /// - Returns: Array of providers with the specified priority
    public func getProviders(withPriority priority: ProviderPriority) -> [LLMProvider] {
        return providerRegistry.compactMap { key, value in
            value.priority == priority ? key : nil
        }.sorted { $0.displayName < $1.displayName }
    }
    
    /// Get provider information
    /// - Parameter provider: The provider to get info for
    /// - Returns: Provider info if registered
    public func getProviderInfo(_ provider: LLMProvider) -> ProviderInfo? {
        return providerRegistry[provider]
    }
    
    /// Check if a provider is implemented
    /// - Parameter provider: The provider to check
    /// - Returns: True if the provider is implemented
    public func isProviderImplemented(_ provider: LLMProvider) -> Bool {
        return providerRegistry[provider]?.status == .implemented
    }
    
    /// Get implementation progress statistics
    /// - Returns: Statistics about provider implementation
    public func getImplementationStats() -> ProviderImplementationStats {
        let implemented = providerRegistry.values.filter { $0.status == .implemented }.count
        let planned = providerRegistry.values.filter { $0.status == .planned }.count
        let deprecated = providerRegistry.values.filter { $0.status == .deprecated }.count
        let total = providerRegistry.count
        
        return ProviderImplementationStats(
            total: total,
            implemented: implemented,
            planned: planned,
            deprecated: deprecated,
            implementationPercentage: total > 0 ? Double(implemented) / Double(total) : 0.0
        )
    }
}

// MARK: - Provider Factory Error
public enum ProviderFactoryError: LocalizedError {
    case unsupportedProvider(LLMProvider)
    case missingAPIKey(LLMProvider)
    case invalidConfiguration(LLMProvider)
    case providerInitializationFailed(LLMProvider, Error)
    
    public var errorDescription: String? {
        switch self {
        case .unsupportedProvider(let provider):
            return "Unsupported provider: \(provider.displayName)"
        case .missingAPIKey(let provider):
            return "Missing API key for \(provider.displayName)"
        case .invalidConfiguration(let provider):
            return "Invalid configuration for \(provider.displayName)"
        case .providerInitializationFailed(let provider, let error):
            return "Failed to initialize \(provider.displayName): \(error.localizedDescription)"
        }
    }
}

// MARK: - Provider Registry
/// Registry for tracking available providers and their capabilities
public class ProviderRegistry {
    
    public static let shared = ProviderRegistry()
    
    private var registeredProviders: Set<LLMProvider> = []
    private var providerCapabilities: [LLMProvider: ProviderCapabilities] = [:]
    
    private init() {
        // Register all supported providers
        for provider in LLMProvider.allCases {
            registerProvider(provider)
        }
    }
    
    /// Register a provider and its capabilities
    /// - Parameter provider: The provider to register
    private func registerProvider(_ provider: LLMProvider) {
        registeredProviders.insert(provider)
        
        let capabilities = ProviderCapabilities(
            supportsStreaming: provider.supportsStreaming,
            supportsFunctions: provider.supportsFunctions,
            supportsSystemPrompt: provider.supportsSystemPrompt,
            maxTokens: provider.maxTokensLimit,
            supportedModels: provider.defaultModels
        )
        
        providerCapabilities[provider] = capabilities
    }
    
    /// Get all registered providers
    public func getAllProviders() -> Set<LLMProvider> {
        return registeredProviders
    }
    
    /// Get capabilities for a specific provider
    /// - Parameter provider: The provider to get capabilities for
    /// - Returns: Provider capabilities, or nil if not registered
    public func getCapabilities(for provider: LLMProvider) -> ProviderCapabilities? {
        return providerCapabilities[provider]
    }
    
    /// Get providers that support a specific capability
    /// - Parameter capability: The capability to filter by
    /// - Returns: Array of providers that support the capability
    public func getProviders(supporting capability: ProviderCapability) -> [LLMProvider] {
        return registeredProviders.filter { provider in
            guard let capabilities = providerCapabilities[provider] else { return false }
            
            switch capability {
            case .streaming:
                return capabilities.supportsStreaming
            case .functions:
                return capabilities.supportsFunctions
            case .systemPrompt:
                return capabilities.supportsSystemPrompt
            case .model(let modelName):
                return capabilities.supportedModels.contains(modelName)
            }
        }
    }
}

// MARK: - Provider Capabilities
public struct ProviderCapabilities {
    public let supportsStreaming: Bool
    public let supportsFunctions: Bool
    public let supportsSystemPrompt: Bool
    public let maxTokens: Int?
    public let supportedModels: [String]
    
    public init(
        supportsStreaming: Bool,
        supportsFunctions: Bool,
        supportsSystemPrompt: Bool,
        maxTokens: Int?,
        supportedModels: [String]
    ) {
        self.supportsStreaming = supportsStreaming
        self.supportsFunctions = supportsFunctions
        self.supportsSystemPrompt = supportsSystemPrompt
        self.maxTokens = maxTokens
        self.supportedModels = supportedModels
    }
}

// MARK: - Provider Capability
public enum ProviderCapability {
    case streaming
    case functions
    case systemPrompt
    case model(String)
}

// MARK: - Enhanced Provider Registration System

/// Provider implementation status
public enum ProviderStatus: String, Codable, CaseIterable {
    case implemented = "implemented"
    case planned = "planned"
    case deprecated = "deprecated"
    case experimental = "experimental"
    
    public var displayName: String {
        switch self {
        case .implemented:
            return "Implemented"
        case .planned:
            return "Planned"
        case .deprecated:
            return "Deprecated"
        case .experimental:
            return "Experimental"
        }
    }
}

/// Provider implementation priority
public enum ProviderPriority: String, Codable, CaseIterable {
    case high = "high"
    case medium = "medium"
    case low = "low"
    
    public var displayName: String {
        switch self {
        case .high:
            return "High"
        case .medium:
            return "Medium"
        case .low:
            return "Low"
        }
    }
}

/// Provider registration information
public struct ProviderInfo: Codable {
    public let provider: LLMProvider
    public let status: ProviderStatus
    public let priority: ProviderPriority
    public let registeredAt: Date
    
    public init(provider: LLMProvider, status: ProviderStatus, priority: ProviderPriority, registeredAt: Date) {
        self.provider = provider
        self.status = status
        self.priority = priority
        self.registeredAt = registeredAt
    }
}

/// Statistics about provider implementation
public struct ProviderImplementationStats {
    public let total: Int
    public let implemented: Int
    public let planned: Int
    public let deprecated: Int
    public let implementationPercentage: Double
    
    public init(total: Int, implemented: Int, planned: Int, deprecated: Int, implementationPercentage: Double) {
        self.total = total
        self.implemented = implemented
        self.planned = planned
        self.deprecated = deprecated
        self.implementationPercentage = implementationPercentage
    }
    
    public var summary: String {
        return "Implemented: \(implemented)/\(total) (\(String(format: "%.1f", implementationPercentage * 100))%)"
    }
}