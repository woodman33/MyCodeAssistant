import Foundation

// MARK: - App Settings
/// Global application settings and configuration
public struct AppSettings: Codable, Equatable {
    public let defaultProvider: LLMProvider
    public let defaultModel: String?
    public let temperature: Double
    public let maxTokens: Int?
    public let systemPrompt: String?
    public let autoSave: Bool
    public let theme: AppTheme
    public let apiTimeoutSeconds: TimeInterval
    public let retryAttempts: Int
    public let enableLogging: Bool
    
    // Edge backend configuration
    public let edgeAPIBase: String
    public let edgeSSEEndpoint: String
    
    public init(
        defaultProvider: LLMProvider = .openAI,
        defaultModel: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int? = nil,
        systemPrompt: String? = nil,
        autoSave: Bool = true,
        theme: AppTheme = .system,
        apiTimeoutSeconds: TimeInterval = 30,
        retryAttempts: Int = 3,
        enableLogging: Bool = false,
        edgeAPIBase: String = "https://agents-starter.wmeldman33.workers.dev",
        edgeSSEEndpoint: String = "/stream"
    ) {
        self.defaultProvider = defaultProvider
        self.defaultModel = defaultModel
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.systemPrompt = systemPrompt
        self.autoSave = autoSave
        self.theme = theme
        self.apiTimeoutSeconds = apiTimeoutSeconds
        self.retryAttempts = retryAttempts
        self.enableLogging = enableLogging
        self.edgeAPIBase = edgeAPIBase
        self.edgeSSEEndpoint = edgeSSEEndpoint
    }
    
    public static let `default` = AppSettings()
}

// MARK: - App Theme
/// Application theme options
public enum AppTheme: String, Codable, CaseIterable {
    case light = "light"
    case dark = "dark"
    case system = "system"
    
    public var displayName: String {
        switch self {
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        case .system:
            return "System"
        }
    }
}

// MARK: - Model Configuration
/// Configuration for a specific model
public struct ModelConfiguration: Codable, Equatable {
    public let provider: LLMProvider
    public let modelName: String
    public let displayName: String
    public let maxTokens: Int?
    public let supportsSystemPrompt: Bool
    public let supportsFunctions: Bool
    public let costPer1kTokens: Double?
    
    public init(
        provider: LLMProvider,
        modelName: String,
        displayName: String,
        maxTokens: Int? = nil,
        supportsSystemPrompt: Bool = true,
        supportsFunctions: Bool = false,
        costPer1kTokens: Double? = nil
    ) {
        self.provider = provider
        self.modelName = modelName
        self.displayName = displayName
        self.maxTokens = maxTokens
        self.supportsSystemPrompt = supportsSystemPrompt
        self.supportsFunctions = supportsFunctions
        self.costPer1kTokens = costPer1kTokens
    }
}

// MARK: - Provider Configuration
/// Configuration for a specific provider
public struct ProviderConfiguration: Codable, Equatable {
    public let provider: LLMProvider
    public let baseURL: String
    public let apiKeyRequired: Bool
    public let supportedModels: [ModelConfiguration]
    public let rateLimit: RateLimit?
    
    public init(
        provider: LLMProvider,
        baseURL: String,
        apiKeyRequired: Bool = true,
        supportedModels: [ModelConfiguration] = [],
        rateLimit: RateLimit? = nil
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.apiKeyRequired = apiKeyRequired
        self.supportedModels = supportedModels
        self.rateLimit = rateLimit
    }
}

// MARK: - Rate Limit
/// Rate limiting configuration
public struct RateLimit: Codable, Equatable {
    public let requestsPerMinute: Int
    public let requestsPerDay: Int?
    public let tokensPerMinute: Int?
    
    public init(
        requestsPerMinute: Int,
        requestsPerDay: Int? = nil,
        tokensPerMinute: Int? = nil
    ) {
        self.requestsPerMinute = requestsPerMinute
        self.requestsPerDay = requestsPerDay
        self.tokensPerMinute = tokensPerMinute
    }
}