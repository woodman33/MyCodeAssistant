import Foundation

// MARK: - Unified Request
/// Standardized request format for all LLM providers
public struct UnifiedRequest: Codable, Equatable {
    public let messages: [ChatMessage]
    public let model: String?
    public let temperature: Double?
    public let maxTokens: Int?
    public let systemPrompt: String?
    public let stream: Bool
    public let functions: [Function]?
    public let functionCall: FunctionCall?
    public let metadata: [String: AnyCodable]?
    
    public init(
        messages: [ChatMessage],
        model: String? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        systemPrompt: String? = nil,
        stream: Bool = false,
        functions: [Function]? = nil,
        functionCall: FunctionCall? = nil,
        metadata: [String: AnyCodable]? = nil
    ) {
        self.messages = messages
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.systemPrompt = systemPrompt
        self.stream = stream
        self.functions = functions
        self.functionCall = functionCall
        self.metadata = metadata
    }
}

// MARK: - Unified Response
/// Standardized response format from all LLM providers
public struct UnifiedResponse: Codable, Equatable {
    public let id: String
    public let message: ChatMessage
    public let finishReason: FinishReason?
    public let usage: TokenUsage?
    public let model: String?
    public let provider: LLMProvider
    public let timestamp: Date
    public let functionCall: FunctionCall?
    public let metadata: [String: AnyCodable]?
    
    public init(
        id: String,
        message: ChatMessage,
        finishReason: FinishReason? = nil,
        usage: TokenUsage? = nil,
        model: String? = nil,
        provider: LLMProvider,
        timestamp: Date = Date(),
        functionCall: FunctionCall? = nil,
        metadata: [String: AnyCodable]? = nil
    ) {
        self.id = id
        self.message = message
        self.finishReason = finishReason
        self.usage = usage
        self.model = model
        self.provider = provider
        self.timestamp = timestamp
        self.functionCall = functionCall
        self.metadata = metadata
    }
}

// MARK: - Finish Reason
/// Reason why the response generation finished
public enum FinishReason: String, Codable, CaseIterable {
    case stop = "stop"
    case length = "length"
    case functionCall = "function_call"
    case contentFilter = "content_filter"
    case error = "error"
    case cancelled = "cancelled"
    
    public var displayName: String {
        switch self {
        case .stop:
            return "Completed"
        case .length:
            return "Max Length Reached"
        case .functionCall:
            return "Function Call"
        case .contentFilter:
            return "Content Filtered"
        case .error:
            return "Error"
        case .cancelled:
            return "Cancelled"
        }
    }
}

// MARK: - Token Usage
/// Token usage statistics for a request/response
public struct TokenUsage: Codable, Equatable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let estimatedCost: Double?
    
    public init(
        promptTokens: Int,
        completionTokens: Int,
        totalTokens: Int? = nil,
        estimatedCost: Double? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens ?? (promptTokens + completionTokens)
        self.estimatedCost = estimatedCost
    }
}

// MARK: - Function
/// Function definition for function calling
public struct Function: Codable, Equatable {
    public let name: String
    public let description: String
    public let parameters: FunctionParameters
    
    public init(
        name: String,
        description: String,
        parameters: FunctionParameters
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

// MARK: - Function Parameters
/// Parameters schema for a function
public struct FunctionParameters: Codable, Equatable {
    public let type: String
    public let properties: [String: FunctionProperty]
    public let required: [String]?
    
    public init(
        type: String = "object",
        properties: [String: FunctionProperty],
        required: [String]? = nil
    ) {
        self.type = type
        self.properties = properties
        self.required = required
    }
}

// MARK: - Function Property
/// Property definition for function parameters
public struct FunctionProperty: Codable, Equatable {
    public let type: String
    public let description: String
    public let enumValues: [String]?
    
    public init(
        type: String,
        description: String,
        enumValues: [String]? = nil
    ) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
    }
}

// MARK: - Function Call
/// Function call made by the assistant
public struct FunctionCall: Codable, Equatable {
    public let name: String
    public let arguments: String
    
    public init(name: String, arguments: String) {
        self.name = name
        self.arguments = arguments
    }
}

// MARK: - AnyCodable
/// Type-erased codable wrapper for dynamic JSON values
public struct AnyCodable: Codable, Equatable {
    public let value: Any
    
    public init<T>(_ value: T?) {
        self.value = value ?? ()
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self.init(())
        } else if let bool = try? container.decode(Bool.self) {
            self.init(bool)
        } else if let int = try? container.decode(Int.self) {
            self.init(int)
        } else if let double = try? container.decode(Double.self) {
            self.init(double)
        } else if let string = try? container.decode(String.self) {
            self.init(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            self.init(array.map { $0.value })
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.init(dictionary.mapValues { $0.value })
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is Void:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            let context = EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "AnyCodable value cannot be encoded")
            throw EncodingError.invalidValue(value, context)
        }
    }
    
    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case is (Void, Void):
            return true
        case let (lhs as Bool, rhs as Bool):
            return lhs == rhs
        case let (lhs as Int, rhs as Int):
            return lhs == rhs
        case let (lhs as Double, rhs as Double):
            return lhs == rhs
        case let (lhs as String, rhs as String):
            return lhs == rhs
        default:
            return false
        }
    }
}