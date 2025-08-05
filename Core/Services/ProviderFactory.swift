import Foundation

// MARK: - Provider Factory
/// Factory for creating LLM provider instances
public class ProviderFactory {
    
    // MARK: - Singleton
    public static let shared = ProviderFactory()
    
    private let apiKeyManager: APIKeyManagerProtocol
    private let configurationManager: ConfigurationManagerProtocol
    
    private init() {
        self.apiKeyManager = APIKeyManager()
        self.configurationManager = ConfigurationManager()
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
        case .anthropic:
            return AnthropicProvider(apiKey: apiKey, configuration: configuration)
        case .gemini:
            return GeminiProvider(apiKey: apiKey, configuration: configuration)
        case .mistral:
            return MistralProvider(apiKey: apiKey, configuration: configuration)
        case .togetherAI:
            return TogetherAIProvider(apiKey: apiKey, configuration: configuration)
        case .grok:
            return GrokProvider(apiKey: apiKey, configuration: configuration)
        case .openRouter:
            return OpenRouterProvider(apiKey: apiKey, configuration: configuration)
        case .portkey:
            return PortkeyProvider(apiKey: apiKey, configuration: configuration)
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
        case .anthropic:
            return AnthropicProvider(apiKey: apiKey, configuration: configuration)
        case .gemini:
            return GeminiProvider(apiKey: apiKey, configuration: configuration)
        case .mistral:
            return MistralProvider(apiKey: apiKey, configuration: configuration)
        case .togetherAI:
            return TogetherAIProvider(apiKey: apiKey, configuration: configuration)
        case .grok:
            return GrokProvider(apiKey: apiKey, configuration: configuration)
        case .openRouter:
            return OpenRouterProvider(apiKey: apiKey, configuration: configuration)
        case .portkey:
            return PortkeyProvider(apiKey: apiKey, configuration: configuration)
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