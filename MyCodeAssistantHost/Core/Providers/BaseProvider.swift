import Foundation

// MARK: - Base LLM Provider
/// Abstract base class for all LLM providers
/// Provides common functionality and enforces protocol conformance
open class BaseLLMProvider: LLMProviderProtocol {
    
    // MARK: - Properties
    public let providerType: LLMProvider
    public var apiKey: String?
    public let baseURL: String
    public let configuration: ProviderConfiguration
    
    // MARK: - Computed Properties
    public var defaultModel: String {
        return providerType.primaryModel
    }
    
    public var availableModels: [String] {
        return configuration.supportedModels.map { $0.modelName }
    }
    
    public var supportsStreaming: Bool {
        return providerType.supportsStreaming
    }
    
    public var supportsFunctions: Bool {
        return providerType.supportsFunctions
    }
    
    public var maxTokens: Int? {
        return providerType.maxTokensLimit
    }
    
    // MARK: - Initialization
    public init(providerType: LLMProvider, apiKey: String?, configuration: ProviderConfiguration) {
        self.providerType = providerType
        self.apiKey = apiKey
        self.baseURL = configuration.baseURL
        self.configuration = configuration
    }
    
    // MARK: - Protocol Requirements (Must be overridden)
    
    open func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        fatalError("sendRequest must be implemented by subclass")
    }
    
    open func sendStreamingRequest(_ request: UnifiedRequest) async throws -> AsyncThrowingStream<UnifiedResponse, Error> {
        fatalError("sendStreamingRequest must be implemented by subclass")
    }
    
    open func transformRequest(_ request: UnifiedRequest) throws -> Data {
        fatalError("transformRequest must be implemented by subclass")
    }
    
    open func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        fatalError("transformResponse must be implemented by subclass")
    }
    
    // MARK: - Common Implementation
    
    public func validateConfiguration() throws {
        // Check API key
        if configuration.apiKeyRequired && (apiKey?.isEmpty ?? true) {
            throw ProviderError.missingAPIKey(providerType)
        }
        
        // Validate API key format
        if let key = apiKey, !key.isEmpty {
            let keyManager = APIKeyManager()
            if !keyManager.validateAPIKey(key, for: providerType) {
                throw ProviderError.invalidAPIKey(providerType)
            }
        }
        
        // Validate base URL
        guard URL(string: baseURL) != nil else {
            throw ProviderError.invalidConfiguration(providerType, "Invalid base URL")
        }
    }
    
    public func estimateCost(for request: UnifiedRequest) -> Double? {
        let model = request.model ?? defaultModel
        guard let inputTokens = estimateInputTokens(for: request),
              let outputTokens = request.maxTokens else {
            return nil
        }
        
        return providerType.estimateCost(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            model: model
        )
    }
    
    // MARK: - Helper Methods
    
    /// Creates the base URLRequest with common headers
    /// - Parameter endpoint: The API endpoint path
    /// - Returns: Configured URLRequest
    func createBaseRequest(endpoint: String) throws -> URLRequest {
        guard let url = URL(string: baseURL + endpoint) else {
            throw ProviderError.invalidURL(baseURL + endpoint)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authentication header
        if let apiKey = apiKey {
            let headerName = providerType.authenticationHeaderName
            let headerValue = providerType.authenticationHeaderValue(apiKey: apiKey)
            request.setValue(headerValue, forHTTPHeaderField: headerName)
        }
        
        // Add provider-specific headers
        for (key, value) in providerType.additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        return request
    }
    
    /// Estimates the number of input tokens for a request
    /// This is a basic estimation - subclasses can override for more accurate tokenization
    /// - Parameter request: The request to estimate tokens for
    /// - Returns: Estimated input token count
    func estimateInputTokens(for request: UnifiedRequest) -> Int? {
        let messageTokens = request.messages.reduce(0) { total, message in
            total + estimateTokens(in: message.content)
        }
        
        let systemTokens = request.systemPrompt.map { estimateTokens(in: $0) } ?? 0
        
        return messageTokens + systemTokens
    }
    
    /// Basic token estimation (roughly 4 characters per token)
    /// - Parameter text: The text to estimate tokens for
    /// - Returns: Estimated token count
    func estimateTokens(in text: String) -> Int {
        return max(1, text.count / 4)
    }
    
    /// Handles common HTTP errors and converts them to ProviderError
    /// - Parameters:
    ///   - response: The HTTP response
    ///   - data: The response data
    /// - Throws: ProviderError for various HTTP error conditions
    func handleHTTPError(response: HTTPURLResponse, data: Data) throws {
        let statusCode = response.statusCode
        let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
        
        switch statusCode {
        case 401:
            throw ProviderError.authenticationFailed(providerType, errorBody)
        case 429:
            throw ProviderError.rateLimitExceeded(providerType, errorBody)
        case 400:
            throw ProviderError.invalidRequest(errorBody)
        case 500...599:
            throw ProviderError.serverError(statusCode, errorBody)
        default:
            throw ProviderError.httpError(statusCode, errorBody)
        }
    }
    
    /// Creates a standardized error response
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - originalRequest: The original request
    /// - Returns: UnifiedResponse with error information
    func createErrorResponse(from error: Error, originalRequest: UnifiedRequest) -> UnifiedResponse {
        let errorMessage = ChatMessage(
            role: .assistant,
            content: "Error: \(error.localizedDescription)"
        )
        
        return UnifiedResponse(
            id: UUID().uuidString,
            message: errorMessage,
            finishReason: .error,
            provider: providerType
        )
    }
    
    /// Validates that a model is supported by this provider
    /// - Parameter model: The model name to validate
    /// - Throws: ProviderError if model is not supported
    func validateModel(_ model: String?) throws {
        guard let model = model else { return }
        
        if !availableModels.contains(model) {
            throw ProviderError.unsupportedModel(providerType, model)
        }
    }
    
    /// Validates request parameters before sending
    /// - Parameter request: The request to validate
    /// - Throws: ProviderError if validation fails
    func validateRequest(_ request: UnifiedRequest) throws {
        // Validate model
        try validateModel(request.model)
        
        // Validate messages
        if request.messages.isEmpty {
            throw ProviderError.invalidRequest("Request must contain at least one message")
        }
        
        // Validate temperature
        if let temperature = request.temperature {
            if temperature < 0 || temperature > 2 {
                throw ProviderError.invalidRequest("Temperature must be between 0 and 2")
            }
        }
        
        // Validate max tokens
        if let maxTokens = request.maxTokens {
            if maxTokens < 1 {
                throw ProviderError.invalidRequest("Max tokens must be greater than 0")
            }
            
            if let limit = self.maxTokens, maxTokens > limit {
                throw ProviderError.invalidRequest("Max tokens (\(maxTokens)) exceeds provider limit (\(limit))")
            }
        }
        
        // Validate functions if not supported
        if let functions = request.functions, !functions.isEmpty && !supportsFunctions {
            throw ProviderError.unsupportedFeature(providerType, "Function calling")
        }
    }
}

// MARK: - Provider Error
public enum ProviderError: LocalizedError {
    case missingAPIKey(LLMProvider)
    case invalidAPIKey(LLMProvider)
    case invalidConfiguration(LLMProvider, String)
    case invalidURL(String)
    case invalidRequest(String)
    case unsupportedModel(LLMProvider, String)
    case unsupportedFeature(LLMProvider, String)
    case authenticationFailed(LLMProvider, String)
    case rateLimitExceeded(LLMProvider, String)
    case serverError(Int, String)
    case httpError(Int, String)
    case networkError(Error)
    case decodingError(Error)
    case encodingError(Error)
    case timeoutError
    case unknownError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "Missing API key for \(provider.displayName)"
        case .invalidAPIKey(let provider):
            return "Invalid API key format for \(provider.displayName)"
        case .invalidConfiguration(let provider, let message):
            return "Invalid configuration for \(provider.displayName): \(message)"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidRequest(let message):
            return "Invalid request: \(message)"
        case .unsupportedModel(let provider, let model):
            return "Model \(model) is not supported by \(provider.displayName)"
        case .unsupportedFeature(let provider, let feature):
            return "Feature \(feature) is not supported by \(provider.displayName)"
        case .authenticationFailed(let provider, let message):
            return "Authentication failed for \(provider.displayName): \(message)"
        case .rateLimitExceeded(let provider, let message):
            return "Rate limit exceeded for \(provider.displayName): \(message)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .httpError(let code, let message):
            return "HTTP error (\(code)): \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .timeoutError:
            return "Request timed out"
        case .unknownError(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .missingAPIKey:
            return "No API key has been configured for this provider"
        case .invalidAPIKey:
            return "The API key format is incorrect"
        case .invalidConfiguration:
            return "The provider configuration contains invalid settings"
        case .invalidURL:
            return "The API endpoint URL is malformed"
        case .invalidRequest:
            return "The request parameters are invalid"
        case .unsupportedModel:
            return "The specified model is not available for this provider"
        case .unsupportedFeature:
            return "The requested feature is not supported by this provider"
        case .authenticationFailed:
            return "The API key is invalid or has insufficient permissions"
        case .rateLimitExceeded:
            return "Too many requests have been made to the API"
        case .serverError:
            return "The API server encountered an internal error"
        case .httpError:
            return "The API returned an HTTP error"
        case .networkError:
            return "Unable to connect to the API server"
        case .decodingError:
            return "The API response format is unexpected"
        case .encodingError:
            return "Unable to format the request data"
        case .timeoutError:
            return "The request took too long to complete"
        case .unknownError:
            return "An unexpected error occurred"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .missingAPIKey:
            return "Please configure your API key in the app settings"
        case .invalidAPIKey:
            return "Please check and re-enter your API key"
        case .invalidConfiguration:
            return "Please reset the provider configuration to defaults"
        case .invalidURL:
            return "Please check the provider's base URL configuration"
        case .invalidRequest:
            return "Please check your request parameters and try again"
        case .unsupportedModel:
            return "Please select a different model for this provider"
        case .unsupportedFeature:
            return "Please use a provider that supports this feature"
        case .authenticationFailed:
            return "Please verify your API key and try again"
        case .rateLimitExceeded:
            return "Please wait a moment and try again"
        case .serverError, .httpError:
            return "Please try again later or contact support if the problem persists"
        case .networkError:
            return "Please check your internet connection and try again"
        case .decodingError:
            return "Please try again or report this issue if it persists"
        case .encodingError:
            return "Please try again with different parameters"
        case .timeoutError:
            return "Please try again with a shorter request or check your connection"
        case .unknownError:
            return "Please try again or restart the app"
        }
    }
}