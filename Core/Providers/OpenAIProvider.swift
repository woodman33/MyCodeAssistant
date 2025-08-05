import Foundation

// MARK: - OpenAI Provider
/// OpenAI API implementation of LLMProviderProtocol
public class OpenAIProvider: BaseLLMProvider {
    
    // MARK: - Initialization
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(
            providerType: .openAI,
            apiKey: apiKey,
            configuration: configuration
        )
    }
    
    // MARK: - LLMProviderProtocol Implementation
    
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        try validateConfiguration()
        try validateRequest(request)
        
        let httpClient = HTTPClient()
        let urlRequest = try createOpenAIRequest(from: request)
        
        do {
            let responseData = try await httpClient.performRequest(urlRequest)
            return try transformResponse(responseData, originalRequest: request)
        } catch {
            throw mapError(error)
        }
    }
    
    public override func sendStreamingRequest(_ request: UnifiedRequest) async throws -> AsyncThrowingStream<UnifiedResponse, Error> {
        try validateConfiguration()
        try validateRequest(request)
        
        let httpClient = HTTPClient()
        let urlRequest = try createOpenAIRequest(from: request, streaming: true)
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let dataStream = try await httpClient.performStreamingRequest(urlRequest)
                    
                    for try await data in dataStream {
                        let chunks = String(data: data, encoding: .utf8)?
                            .components(separatedBy: "\n")
                            .compactMap { line in
                                line.hasPrefix("data: ") ? String(line.dropFirst(6)) : nil
                            }
                            .filter { !$0.isEmpty && $0 != "[DONE]" } ?? []
                        
                        for chunk in chunks {
                            if let chunkData = chunk.data(using: .utf8) {
                                do {
                                    let response = try transformStreamingChunk(chunkData, originalRequest: request)
                                    continuation.yield(response)
                                } catch {
                                    // Skip malformed chunks but continue processing
                                    continue
                                }
                            }
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: mapError(error))
                }
            }
        }
    }
    
    public override func transformRequest(_ request: UnifiedRequest) throws -> Data {
        let openAIRequest = try createOpenAIRequestBody(from: request)
        
        do {
            let encoder = JSONEncoder()
            return try encoder.encode(openAIRequest)
        } catch {
            throw ProviderError.encodingError(error)
        }
    }
    
    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        do {
            let decoder = JSONDecoder()
            let openAIResponse = try decoder.decode(OpenAIResponse.self, from: data)
            return try convertToUnifiedResponse(openAIResponse, originalRequest: originalRequest)
        } catch {
            throw ProviderError.decodingError(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func createOpenAIRequest(from request: UnifiedRequest, streaming: Bool = false) throws -> URLRequest {
        let endpoint = "/chat/completions"
        var urlRequest = try createBaseRequest(endpoint: endpoint)
        
        let requestBody = try createOpenAIRequestBody(from: request, streaming: streaming)
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)
        
        return urlRequest
    }
    
    private func createOpenAIRequestBody(from request: UnifiedRequest, streaming: Bool = false) throws -> OpenAIRequest {
        let messages = request.messages.map { message in
            OpenAIMessage(
                role: message.role.rawValue,
                content: message.content
            )
        }
        
        // Add system prompt as first message if provided
        var allMessages = messages
        if let systemPrompt = request.systemPrompt {
            let systemMessage = OpenAIMessage(role: "system", content: systemPrompt)
            allMessages.insert(systemMessage, at: 0)
        }
        
        return OpenAIRequest(
            model: request.model ?? defaultModel,
            messages: allMessages,
            temperature: request.temperature,
            maxTokens: request.maxTokens,
            stream: streaming,
            functions: request.functions?.map { convertToOpenAIFunction($0) },
            functionCall: request.functionCall.map { convertToOpenAIFunctionCall($0) }
        )
    }
    
    private func convertToOpenAIFunction(_ function: Function) -> OpenAIFunction {
        return OpenAIFunction(
            name: function.name,
            description: function.description,
            parameters: function.parameters
        )
    }
    
    private func convertToOpenAIFunctionCall(_ functionCall: FunctionCall) -> OpenAIFunctionCall {
        return OpenAIFunctionCall(
            name: functionCall.name,
            arguments: functionCall.arguments
        )
    }
    
    private func convertToUnifiedResponse(_ openAIResponse: OpenAIResponse, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        guard let choice = openAIResponse.choices.first else {
            throw ProviderError.invalidRequest("No choices in response")
        }
        
        let message = ChatMessage(
            role: MessageRole(rawValue: choice.message.role) ?? .assistant,
            content: choice.message.content ?? ""
        )
        
        let finishReason = FinishReason(rawValue: choice.finishReason ?? "stop") ?? .stop
        
        let usage = openAIResponse.usage.map { openAIUsage in
            TokenUsage(
                promptTokens: openAIUsage.promptTokens,
                completionTokens: openAIUsage.completionTokens,
                totalTokens: openAIUsage.totalTokens,
                estimatedCost: estimateCost(for: originalRequest)
            )
        }
        
        return UnifiedResponse(
            id: openAIResponse.id,
            message: message,
            finishReason: finishReason,
            usage: usage,
            model: openAIResponse.model,
            provider: providerType,
            functionCall: choice.message.functionCall.map { convertFromOpenAIFunctionCall($0) }
        )
    }
    
    private func transformStreamingChunk(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        let decoder = JSONDecoder()
        let chunk = try decoder.decode(OpenAIStreamingChunk.self, from: data)
        
        guard let choice = chunk.choices.first else {
            throw ProviderError.invalidRequest("No choices in streaming chunk")
        }
        
        let content = choice.delta.content ?? ""
        let message = ChatMessage(
            role: .assistant,
            content: content
        )
        
        let finishReason = choice.finishReason.flatMap { FinishReason(rawValue: $0) }
        
        return UnifiedResponse(
            id: chunk.id,
            message: message,
            finishReason: finishReason,
            model: chunk.model,
            provider: providerType
        )
    }
    
    private func convertFromOpenAIFunctionCall(_ functionCall: OpenAIFunctionCall) -> FunctionCall {
        return FunctionCall(
            name: functionCall.name,
            arguments: functionCall.arguments
        )
    }
    
    private func mapError(_ error: Error) -> ProviderError {
        if let httpError = error as? HTTPError {
            switch httpError {
            case .httpStatusError(let status, let data):
                let errorMessage = ResponseParser.parseErrorMessage(data)
                
                switch status {
                case 401:
                    return .authenticationFailed(providerType, errorMessage)
                case 429:
                    return .rateLimitExceeded(providerType, errorMessage)
                case 400:
                    return .invalidRequest(errorMessage)
                case 500...599:
                    return .serverError(status, errorMessage)
                default:
                    return .httpError(status, errorMessage)
                }
            case .networkError(let networkError):
                return .networkError(networkError)
            case .timeout:
                return .timeoutError
            default:
                return .unknownError(error)
            }
        }
        
        return .unknownError(error)
    }
}

// MARK: - OpenAI API Models

private struct OpenAIRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let temperature: Double?
    let maxTokens: Int?
    let stream: Bool?
    let functions: [OpenAIFunction]?
    let functionCall: OpenAIFunctionCall?
    
    private enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, functions
        case maxTokens = "max_tokens"
        case functionCall = "function_call"
    }
}

private struct OpenAIMessage: Codable {
    let role: String
    let content: String?
    let functionCall: OpenAIFunctionCall?
    
    init(role: String, content: String) {
        self.role = role
        self.content = content
        self.functionCall = nil
    }
    
    private enum CodingKeys: String, CodingKey {
        case role, content
        case functionCall = "function_call"
    }
}

private struct OpenAIFunction: Codable {
    let name: String
    let description: String
    let parameters: FunctionParameters
}

private struct OpenAIFunctionCall: Codable {
    let name: String
    let arguments: String
}

private struct OpenAIResponse: Codable {
    let id: String
    let model: String
    let choices: [OpenAIChoice]
    let usage: OpenAIUsage?
    let created: Int?
}

private struct OpenAIChoice: Codable {
    let message: OpenAIMessage
    let finishReason: String?
    let index: Int
    
    private enum CodingKeys: String, CodingKey {
        case message, index
        case finishReason = "finish_reason"
    }
}

private struct OpenAIUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    
    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

private struct OpenAIStreamingChunk: Codable {
    let id: String
    let model: String
    let choices: [OpenAIStreamingChoice]
}

private struct OpenAIStreamingChoice: Codable {
    let delta: OpenAIDelta
    let finishReason: String?
    let index: Int
    
    private enum CodingKeys: String, CodingKey {
        case delta, index
        case finishReason = "finish_reason"
    }
}

private struct OpenAIDelta: Codable {
    let content: String?
    let role: String?
}

// MARK: - Additional Provider Examples (Stub Implementations)

/// Anthropic Provider stub - would implement Claude API
public class AnthropicProvider: BaseLLMProvider {
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(providerType: .anthropic, apiKey: apiKey, configuration: configuration)
    }
    
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        // Implementation would go here
        fatalError("AnthropicProvider not yet implemented")
    }
    
    public override func sendStreamingRequest(_ request: UnifiedRequest) async throws -> AsyncThrowingStream<UnifiedResponse, Error> {
        fatalError("AnthropicProvider not yet implemented")
    }
    
    public override func transformRequest(_ request: UnifiedRequest) throws -> Data {
        fatalError("AnthropicProvider not yet implemented")
    }
    
    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        fatalError("AnthropicProvider not yet implemented")
    }
}

/// Gemini Provider stub - would implement Google Gemini API
public class GeminiProvider: BaseLLMProvider {
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(providerType: .gemini, apiKey: apiKey, configuration: configuration)
    }
    
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        // Implementation would go here
        fatalError("GeminiProvider not yet implemented")
    }
    
    public override func sendStreamingRequest(_ request: UnifiedRequest) async throws -> AsyncThrowingStream<UnifiedResponse, Error> {
        fatalError("GeminiProvider not yet implemented")
    }
    
    public override func transformRequest(_ request: UnifiedRequest) throws -> Data {
        fatalError("GeminiProvider not yet implemented")
    }
    
    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        fatalError("GeminiProvider not yet implemented")
    }
}

// MARK: - Remaining Provider Stubs

public class MistralProvider: BaseLLMProvider {
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(providerType: .mistral, apiKey: apiKey, configuration: configuration)
    }
    
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        fatalError("MistralProvider not yet implemented")
    }
    
    public override func sendStreamingRequest(_ request: UnifiedRequest) async throws -> AsyncThrowingStream<UnifiedResponse, Error> {
        fatalError("MistralProvider not yet implemented")
    }
    
    public override func transformRequest(_ request: UnifiedRequest) throws -> Data {
        fatalError("MistralProvider not yet implemented")
    }
    
    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        fatalError("MistralProvider not yet implemented")
    }
}

public class TogetherAIProvider: BaseLLMProvider {
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(providerType: .togetherAI, apiKey: apiKey, configuration: configuration)
    }
    
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        fatalError("TogetherAIProvider not yet implemented")
    }
    
    public override func sendStreamingRequest(_ request: UnifiedRequest) async throws -> AsyncThrowingStream<UnifiedResponse, Error> {
        fatalError("TogetherAIProvider not yet implemented")
    }
    
    public override func transformRequest(_ request: UnifiedRequest) throws -> Data {
        fatalError("TogetherAIProvider not yet implemented")
    }
    
    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        fatalError("TogetherAIProvider not yet implemented")
    }
}

public class GrokProvider: BaseLLMProvider {
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(providerType: .grok, apiKey: apiKey, configuration: configuration)
    }
    
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        fatalError("GrokProvider not yet implemented")
    }
    
    public override func sendStreamingRequest(_ request: UnifiedRequest) async throws -> AsyncThrowingStream<UnifiedResponse, Error> {
        fatalError("GrokProvider not yet implemented")
    }
    
    public override func transformRequest(_ request: UnifiedRequest) throws -> Data {
        fatalError("GrokProvider not yet implemented")
    }
    
    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        fatalError("GrokProvider not yet implemented")
    }
}

public class OpenRouterProvider: BaseLLMProvider {
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(providerType: .openRouter, apiKey: apiKey, configuration: configuration)
    }
    
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        fatalError("OpenRouterProvider not yet implemented")
    }
    
    public override func sendStreamingRequest(_ request: UnifiedRequest) async throws -> AsyncThrowingStream<UnifiedResponse, Error> {
        fatalError("OpenRouterProvider not yet implemented")
    }
    
    public override func transformRequest(_ request: UnifiedRequest) throws -> Data {
        fatalError("OpenRouterProvider not yet implemented")
    }
    
    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        fatalError("OpenRouterProvider not yet implemented")
    }
}

public class PortkeyProvider: BaseLLMProvider {
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(providerType: .portkey, apiKey: apiKey, configuration: configuration)
    }
    
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        fatalError("PortkeyProvider not yet implemented")
    }
    
    public override func sendStreamingRequest(_ request: UnifiedRequest) async throws -> AsyncThrowingStream<UnifiedResponse, Error> {
        fatalError("PortkeyProvider not yet implemented")
    }
    
    public override func transformRequest(_ request: UnifiedRequest) throws -> Data {
        fatalError("PortkeyProvider not yet implemented")
    }
    
    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        fatalError("PortkeyProvider not yet implemented")
    }
}