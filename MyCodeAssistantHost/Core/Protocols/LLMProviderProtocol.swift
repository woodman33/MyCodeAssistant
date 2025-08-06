import Foundation

// MARK: - LLM Provider Protocol
/// Protocol that all LLM providers must conform to
public protocol LLMProviderProtocol: AnyObject {
    /// The provider type this implementation represents
    var providerType: LLMProvider { get }
    
    /// The API key for this provider
    var apiKey: String? { get set }
    
    /// Base URL for the provider's API
    var baseURL: String { get }
    
    /// Default model for this provider
    var defaultModel: String { get }
    
    /// Available models for this provider
    var availableModels: [String] { get }
    
    /// Whether this provider supports streaming responses
    var supportsStreaming: Bool { get }
    
    /// Whether this provider supports function calling
    var supportsFunctions: Bool { get }
    
    /// Maximum tokens supported by this provider
    var maxTokens: Int? { get }
    
    /// Send a request to the provider and return a response
    /// - Parameter request: The unified request to send
    /// - Returns: A unified response from the provider
    /// - Throws: ProviderError if the request fails
    func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse
    
    /// Send a streaming request to the provider
    /// - Parameter request: The unified request to send
    /// - Returns: An async sequence of partial responses
    /// - Throws: ProviderError if the request fails
    func sendStreamingRequest(_ request: UnifiedRequest) async throws -> AsyncThrowingStream<UnifiedResponse, Error>
    
    /// Validate the current configuration
    /// - Throws: ProviderError if the configuration is invalid
    func validateConfiguration() throws
    
    /// Get estimated cost for a request
    /// - Parameter request: The request to estimate cost for
    /// - Returns: Estimated cost in USD, or nil if cost estimation is not supported
    func estimateCost(for request: UnifiedRequest) -> Double?
    
    /// Transform the unified request to provider-specific format
    /// - Parameter request: The unified request
    /// - Returns: Provider-specific request data
    func transformRequest(_ request: UnifiedRequest) throws -> Data
    
    /// Transform provider-specific response to unified format
    /// - Parameter data: Provider-specific response data
    /// - Parameter originalRequest: The original request for context
    /// - Returns: Unified response
    func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse
}

// MARK: - Provider Configuration Protocol
/// Protocol for provider configuration management
public protocol ProviderConfigurationProtocol {
    /// Get configuration for a specific provider
    /// - Parameter provider: The provider to get configuration for
    /// - Returns: The provider configuration
    func getConfiguration(for provider: LLMProvider) -> ProviderConfiguration
    
    /// Update configuration for a specific provider
    /// - Parameters:
    ///   - provider: The provider to update configuration for
    ///   - configuration: The new configuration
    func updateConfiguration(for provider: LLMProvider, configuration: ProviderConfiguration)
    
    /// Get all available configurations
    /// - Returns: All provider configurations
    func getAllConfigurations() -> [ProviderConfiguration]
}

// MARK: - API Key Management Protocol
/// Protocol for secure API key management
public protocol APIKeyManagerProtocol {
    /// Store an API key for a provider
    /// - Parameters:
    ///   - key: The API key to store
    ///   - provider: The provider the key belongs to
    /// - Throws: KeychainError if storage fails
    func storeAPIKey(_ key: String, for provider: LLMProvider) throws
    
    /// Retrieve an API key for a provider
    /// - Parameter provider: The provider to get the key for
    /// - Returns: The API key, or nil if not found
    /// - Throws: KeychainError if retrieval fails
    func getAPIKey(for provider: LLMProvider) throws -> String?
    
    /// Delete an API key for a provider
    /// - Parameter provider: The provider to delete the key for
    /// - Throws: KeychainError if deletion fails
    func deleteAPIKey(for provider: LLMProvider) throws
    
    /// Get all providers that have API keys configured
    /// - Returns: Array of providers with stored API keys
    func getProvidersWithKeys() -> [LLMProvider]
    
    /// Check if an API key exists for a provider
    /// - Parameter provider: The provider to check for
    /// - Returns: True if a key exists, false otherwise
    func hasAPIKey(for provider: LLMProvider) -> Bool
    
    /// Delete all stored API keys
    /// - Throws: KeychainError if deletion fails
    func deleteAllAPIKeys() throws
}

// MARK: - Request Middleware Protocol
/// Protocol for request middleware that can modify requests/responses
public protocol RequestMiddlewareProtocol {
    /// Process a request before sending to provider
    /// - Parameter request: The request to process
    /// - Returns: The potentially modified request
    /// - Throws: MiddlewareError if processing fails
    func processRequest(_ request: UnifiedRequest) async throws -> UnifiedRequest
    
    /// Process a response after receiving from provider
    /// - Parameter response: The response to process
    /// - Returns: The potentially modified response
    /// - Throws: MiddlewareError if processing fails
    func processResponse(_ response: UnifiedResponse) async throws -> UnifiedResponse
    
    /// Priority of this middleware (higher number = higher priority)
    var priority: Int { get }
    
    /// Whether this middleware should be applied to the given provider
    /// - Parameter provider: The provider to check
    /// - Returns: True if middleware should be applied
    func shouldApply(to provider: LLMProvider) -> Bool
}

// MARK: - Rate Limiter Protocol
/// Protocol for rate limiting provider requests
public protocol RateLimiterProtocol {
    /// Check if a request is allowed under current rate limits
    /// - Parameter provider: The provider to check rate limits for
    /// - Returns: True if request is allowed, false otherwise
    func isRequestAllowed(for provider: LLMProvider) -> Bool
    
    /// Record a successful request for rate limiting purposes
    /// - Parameters:
    ///   - provider: The provider the request was made to
    ///   - tokens: Number of tokens used in the request
    func recordRequest(for provider: LLMProvider, tokens: Int?)
    
    /// Get the time until the next request is allowed
    /// - Parameter provider: The provider to check
    /// - Returns: Time interval until next request is allowed, or nil if immediately allowed
    func timeUntilNextRequest(for provider: LLMProvider) -> TimeInterval?
    
    /// Reset rate limits for a provider
    /// - Parameter provider: The provider to reset limits for
    func resetLimits(for provider: LLMProvider)
}

// MARK: - Conversation Manager Protocol
/// Protocol for managing conversations
public protocol ConversationManagerProtocol {
    /// Save a conversation
    /// - Parameter conversation: The conversation to save
    /// - Throws: StorageError if saving fails
    func saveConversation(_ conversation: Conversation) async throws
    
    /// Load a conversation by ID
    /// - Parameter id: The conversation ID
    /// - Returns: The conversation, or nil if not found
    /// - Throws: StorageError if loading fails
    func loadConversation(id: UUID) throws -> Conversation?
    
    /// Load all conversations
    /// - Returns: Array of all conversations
    /// - Throws: StorageError if loading fails
    func loadAllConversations() async throws -> [Conversation]
    
    /// Delete a conversation
    /// - Parameter id: The conversation ID to delete
    /// - Throws: StorageError if deletion fails
    func deleteConversation(id: UUID) throws
    
    /// Delete all conversations
    /// - Throws: StorageError if deletion fails
    func deleteAllConversations() throws
    
    /// Search conversations by title or content
    /// - Parameter query: The search query
    /// - Returns: Array of matching conversations
    /// - Throws: StorageError if search fails
    func searchConversations(query: String) throws -> [Conversation]
}