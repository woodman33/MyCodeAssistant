import Foundation

// MARK: - LLM Provider
/// Enumeration of supported LLM providers
public enum LLMProvider: String, Codable, CaseIterable, Identifiable {
    case openAI = "openai"
    case anthropic = "anthropic"
    case gemini = "gemini"
    case mistral = "mistral"
    case togetherAI = "together"
    case grok = "grok"
    case openRouter = "openrouter"
    case portkey = "portkey"
    
    public var id: String { rawValue }
    
    // MARK: - Display Properties
    
    public var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .anthropic:
            return "Anthropic"
        case .gemini:
            return "Google Gemini"
        case .mistral:
            return "Mistral AI"
        case .togetherAI:
            return "Together AI"
        case .grok:
            return "Grok (xAI)"
        case .openRouter:
            return "OpenRouter"
        case .portkey:
            return "Portkey"
        }
    }
    
    public var description: String {
        switch self {
        case .openAI:
            return "OpenAI's GPT models including GPT-4, GPT-3.5, and more"
        case .anthropic:
            return "Anthropic's Claude models for safe, helpful AI assistance"
        case .gemini:
            return "Google's Gemini models for multimodal AI capabilities"
        case .mistral:
            return "Mistral AI's efficient and powerful language models"
        case .togetherAI:
            return "Together AI's platform with access to various open-source models"
        case .grok:
            return "xAI's Grok models with real-time information access"
        case .openRouter:
            return "OpenRouter's unified API for multiple AI providers"
        case .portkey:
            return "Portkey's AI gateway with advanced features and analytics"
        }
    }
    
    // MARK: - Configuration Properties
    
    public var baseURL: String {
        switch self {
        case .openAI:
            return "https://api.openai.com/v1"
        case .anthropic:
            return "https://api.anthropic.com/v1"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta"
        case .mistral:
            return "https://api.mistral.ai/v1"
        case .togetherAI:
            return "https://api.together.xyz/v1"
        case .grok:
            return "https://api.x.ai/v1"
        case .openRouter:
            return "https://openrouter.ai/api/v1"
        case .portkey:
            return "https://api.portkey.ai/v1"
        }
    }
    
    public var defaultModels: [String] {
        switch self {
        case .openAI:
            return ["gpt-4-turbo", "gpt-4", "gpt-3.5-turbo", "gpt-4o", "gpt-4o-mini"]
        case .anthropic:
            return ["claude-3-5-sonnet-20241022", "claude-3-haiku-20240307", "claude-3-opus-20240229"]
        case .gemini:
            return ["gemini-1.5-pro", "gemini-1.5-flash", "gemini-pro", "gemini-pro-vision"]
        case .mistral:
            return ["mistral-large-latest", "mistral-medium-latest", "mistral-small-latest", "codestral-latest"]
        case .togetherAI:
            return ["meta-llama/Llama-2-70b-chat-hf", "mistralai/Mixtral-8x7B-Instruct-v0.1", "NousResearch/Nous-Hermes-2-Mixtral-8x7B-DPO"]
        case .grok:
            return ["grok-beta", "grok-vision-beta"]
        case .openRouter:
            return ["openai/gpt-4-turbo", "anthropic/claude-3-sonnet", "google/gemini-pro-1.5"]
        case .portkey:
            return ["gpt-4-turbo", "claude-3-sonnet", "gemini-pro"]
        }
    }
    
    public var primaryModel: String {
        return defaultModels.first ?? "default"
    }
    
    public var supportsStreaming: Bool {
        switch self {
        case .openAI, .anthropic, .mistral, .togetherAI, .grok, .openRouter, .portkey:
            return true
        case .gemini:
            return false // Gemini API doesn't support streaming in the same way
        }
    }
    
    public var supportsFunctions: Bool {
        switch self {
        case .openAI, .mistral, .togetherAI, .openRouter, .portkey:
            return true
        case .anthropic, .gemini, .grok:
            return false
        }
    }
    
    public var supportsSystemPrompt: Bool {
        switch self {
        case .openAI, .mistral, .togetherAI, .grok, .openRouter, .portkey:
            return true
        case .anthropic:
            return false // Anthropic uses system parameter differently
        case .gemini:
            return true
        }
    }
    
    public var maxTokensLimit: Int? {
        switch self {
        case .openAI:
            return 128000 // GPT-4 Turbo
        case .anthropic:
            return 200000 // Claude 3
        case .gemini:
            return 2097152 // Gemini 1.5 Pro
        case .mistral:
            return 32000 // Mistral Large
        case .togetherAI:
            return 32768 // Varies by model
        case .grok:
            return 131072 // Grok
        case .openRouter:
            return nil // Varies by underlying model
        case .portkey:
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
        case .anthropic:
            return "ANTHROPIC_API_KEY"
        case .gemini:
            return "GEMINI_API_KEY"
        case .mistral:
            return "MISTRAL_API_KEY"
        case .togetherAI:
            return "TOGETHER_API_KEY"
        case .grok:
            return "GROK_API_KEY"
        case .openRouter:
            return "OPENROUTER_API_KEY"
        case .portkey:
            return "PORTKEY_API_KEY"
        }
    }
    
    // MARK: - Headers
    
    public var authenticationHeaderName: String {
        switch self {
        case .openAI, .mistral, .togetherAI, .grok, .openRouter:
            return "Authorization"
        case .anthropic:
            return "x-api-key"
        case .gemini:
            return "x-goog-api-key"
        case .portkey:
            return "Authorization"
        }
    }
    
    public func authenticationHeaderValue(apiKey: String) -> String {
        switch self {
        case .openAI, .mistral, .togetherAI, .grok, .openRouter, .portkey:
            return "Bearer \(apiKey)"
        case .anthropic, .gemini:
            return apiKey
        }
    }
    
    public var additionalHeaders: [String: String] {
        switch self {
        case .anthropic:
            return ["anthropic-version": "2023-06-01"]
        case .openRouter:
            return ["HTTP-Referer": "https://mycodeassistant.app"]
        default:
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
        case .anthropic:
            return [
                "claude-3-5-sonnet-20241022": 0.003,
                "claude-3-haiku-20240307": 0.00025,
                "claude-3-opus-20240229": 0.015
            ]
        case .gemini:
            return [
                "gemini-1.5-pro": 0.0035,
                "gemini-1.5-flash": 0.00035,
                "gemini-pro": 0.0005
            ]
        case .mistral:
            return [
                "mistral-large-latest": 0.008,
                "mistral-medium-latest": 0.0027,
                "mistral-small-latest": 0.002
            ]
        default:
            return [:] // Pricing varies or is not publicly available
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
        case .anthropic:
            return [
                "claude-3-5-sonnet-20241022": 0.015,
                "claude-3-haiku-20240307": 0.00125,
                "claude-3-opus-20240229": 0.075
            ]
        case .gemini:
            return [
                "gemini-1.5-pro": 0.0105,
                "gemini-1.5-flash": 0.0014,
                "gemini-pro": 0.0015
            ]
        case .mistral:
            return [
                "mistral-large-latest": 0.024,
                "mistral-medium-latest": 0.0081,
                "mistral-small-latest": 0.006
            ]
        default:
            return [:] // Pricing varies or is not publicly available
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