import Foundation

// MARK: - LLM Provider
/// Enumeration of supported LLM providers
public enum LLMProvider: String, Codable, CaseIterable, Identifiable {
    case openAI = "openai"
    case openRouter = "openrouter"
    
    public var id: String { rawValue }
    
    // MARK: - Display Properties
    
    public var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .openRouter:
            return "OpenRouter"
        }
    }
    
    public var description: String {
        switch self {
        case .openAI:
            return "OpenAI's GPT models including GPT-4, GPT-3.5, and more"
        case .openRouter:
            return "OpenRouter's unified API for multiple AI providers"
        }
    }
    
    // MARK: - Configuration Properties
    
    public var baseURL: String {
        switch self {
        case .openAI:
            return "https://api.openai.com/v1"
        case .openRouter:
            return "https://openrouter.ai/api/v1"
        }
    }
    
    public var defaultModels: [String] {
        switch self {
        case .openAI:
            return ["gpt-4-turbo", "gpt-4", "gpt-3.5-turbo", "gpt-4o", "gpt-4o-mini"]
        case .openRouter:
            return ["openai/gpt-4-turbo", "anthropic/claude-3-sonnet", "google/gemini-pro-1.5"]
        }
    }
    
    public var primaryModel: String {
        return defaultModels.first ?? "default"
    }
    
    public var supportsStreaming: Bool {
        switch self {
        case .openAI, .openRouter:
            return true
        }
    }
    
    public var supportsFunctions: Bool {
        switch self {
        case .openAI, .openRouter:
            return true
        }
    }
    
    public var supportsSystemPrompt: Bool {
        switch self {
        case .openAI, .openRouter:
            return true
        }
    }
    
    public var maxTokensLimit: Int? {
        switch self {
        case .openAI:
            return 128000 // GPT-4 Turbo
        case .openRouter:
            return nil // Varies by underlying model
        }
    }
    
    // MARK: - Authentication
    
    public var requiresAPIKey: Bool {
        return true // All providers currently require API keys
    }
    
    public var apiKeyEnvironmentVariable: String {
        switch self {
        case .openAI:
            return "OPENAI_API_KEY"
        case .openRouter:
            return "OPENROUTER_API_KEY"
        }
    }
    
    // MARK: - Headers
    
    public var authenticationHeaderName: String {
        switch self {
        case .openAI, .openRouter:
            return "Authorization"
        }
    }
    
    public func authenticationHeaderValue(apiKey: String) -> String {
        switch self {
        case .openAI, .openRouter:
            return "Bearer \(apiKey)"
        }
    }
    
    public var additionalHeaders: [String: String] {
        switch self {
        case .openRouter:
            return ["HTTP-Referer": "https://mycodeassistant.app"]
        case .openAI:
            return [:]
        }
    }
    
    // MARK: - Pricing (per 1K tokens)
    
    public var inputPricing: [String: Double] {
        switch self {
        case .openAI:
            return [
                "gpt-4-turbo": 0.01,
                "gpt-4": 0.03,
                "gpt-3.5-turbo": 0.001,
                "gpt-4o": 0.005,
                "gpt-4o-mini": 0.00015
            ]
        case .openRouter:
            return [:] // Pricing varies by underlying model
        }
    }
    
    public var outputPricing: [String: Double] {
        switch self {
        case .openAI:
            return [
                "gpt-4-turbo": 0.03,
                "gpt-4": 0.06,
                "gpt-3.5-turbo": 0.002,
                "gpt-4o": 0.015,
                "gpt-4o-mini": 0.0006
            ]
        case .openRouter:
            return [:] // Pricing varies by underlying model
        }
    }
    
    // MARK: - Helper Methods
    
    public func estimateCost(inputTokens: Int, outputTokens: Int, model: String) -> Double? {
        guard let inputPrice = inputPricing[model],
              let outputPrice = outputPricing[model] else {
            return nil
        }
        
        let inputCost = (Double(inputTokens) / 1000.0) * inputPrice
        let outputCost = (Double(outputTokens) / 1000.0) * outputPrice
        
        return inputCost + outputCost
    }
    
    public func isModelSupported(_ model: String) -> Bool {
        return defaultModels.contains(model)
    }
}