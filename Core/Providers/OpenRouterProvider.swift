import Foundation

// MARK: - OpenRouter Provider
/// OpenRouter's unified API implementation of LLMProviderProtocol
public class OpenRouterProvider: BaseLLMProvider {
    
    // MARK: - Initialization
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(
            providerType: .openRouter,
            apiKey: apiKey,
            configuration: configuration
        )
    }
    
    // MARK: - LLMProviderProtocol Implementation
    
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        try validateConfiguration()
        try validateRequest(request)
        
        let httpClient = HTTPClient()
        let urlRequest = try createOpenRouterRequest(from: request)
        
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
        let urlRequest = try createOpenRouterRequest(from: request, streaming: true)
        
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
        let openRouterRequest = try createOpenRouterRequestBody(from: request)
        
        do {
            let encoder = JSONEncoder()
            return try encoder.encode(openRouterRequest)
        } catch {
            throw ProviderError.encodingError(error)
        }
    }
    
    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        do {
            let decoder = JSONDecoder()
            let openRouterResponse = try decoder.decode(OpenRouterResponse.self, from: data)
            return try convertToUnifiedResponse(openRouterResponse, originalRequest: originalRequest)
        } catch {
            throw ProviderError.decodingError(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func createOpenRouterRequest(from request: UnifiedRequest, streaming: Bool = false) throws -> URLRequest {
        let endpoint = "/chat/completions"
        var urlRequest = try createBaseRequest(endpoint: endpoint)
        
        let requestBody = try createOpenRouterRequestBody(from: request, streaming: streaming)
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)
        
        return urlRequest
    }
    
    private func createOpenRouterRequestBody(from request: UnifiedRequest, streaming: Bool = false) throws -> OpenRouterRequest {
        let messages = request.messages.map { message in
            OpenRouterMessage(
                role: message.role.rawValue,
                content: message.content
            )
        }
        
        // Add system prompt as first message if provided
        var allMessages = messages
        if let systemPrompt = request.systemPrompt {
            let systemMessage = OpenRouterMessage(role: "system", content: systemPrompt)
            allMessages.insert(systemMessage, at: 0)
        }
        
        return OpenRouterRequest(
            model: request.model ?? defaultModel,
            messages: allMessages,
            temperature: request.temperature,
            maxTokens: request.maxTokens,
            stream: streaming,
            functions: request.functions?.map { convertToOpenRouterFunction($0) },
            functionCall: request.functionCall.map { convertToOpenRouterFunctionCall($0) }
        )
    }
    
    private func convertToOpenRouterFunction(_ function: Function) -> OpenRouterFunction {
        return OpenRouterFunction(
            name: function.name,
            description: function.description,
            parameters: function.parameters
        )
    }
    
    private func convertToOpenRouterFunctionCall(_ functionCall: FunctionCall) -> OpenRouterFunctionCall {
        return OpenRouterFunctionCall(
            name: functionCall.name,
            arguments: functionCall.arguments
        )
    }
    
    private func convertToUnifiedResponse(_ openRouterResponse: OpenRouterResponse, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        guard let choice = openRouterResponse.choices.first else {
            throw ProviderError.invalidRequest("No choices in response")
        }
        
        let message = ChatMessage(
            role: MessageRole(rawValue: choice.message.role) ?? .assistant,
            content: choice.message.content ?? ""
        )
        
        let finishReason = FinishReason(rawValue: choice.finishReason ?? "stop") ?? .stop
        
        let usage = openRouterResponse.usage.map { openRouterUsage in
            TokenUsage(
                promptTokens: openRouterUsage.promptTokens,
                completionTokens: openRouterUsage.completionTokens,
                totalTokens: openRouterUsage.totalTokens,
                estimatedCost: estimateCost(for: originalRequest)
            )
        }
        
        return UnifiedResponse(
            id: openRouterResponse.id,
            message: message,
            finishReason: finishReason,
            usage: usage,
            model: openRouterResponse.model,
            provider: providerType,
            functionCall: choice.message.functionCall.map { convertFromOpenRouterFunctionCall($0) }
        )
    }
    
    private func transformStreamingChunk(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        let decoder = JSONDecoder()
        let chunk = try decoder.decode(OpenRouterStreamingChunk.self, from: data)
        
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
    
    private func convertFromOpenRouterFunctionCall(_ functionCall: OpenRouterFunctionCall) -> FunctionCall {
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
                case 502, 503:
                    // OpenRouter specific: Provider routing errors
                    return .serverError(status, "Provider routing error: \(errorMessage)")
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

// MARK: - OpenRouter API Models

private struct OpenRouterRequest: Codable {
    let model: String
    let messages: [OpenRouterMessage]
    let temperature: Double?
    let maxTokens: Int?
    let stream: Bool?
    let functions: [OpenRouterFunction]?
    let functionCall: OpenRouterFunctionCall?
    
    private enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, functions
        case maxTokens = "max_tokens"
        case functionCall = "function_call"
    }
}

private struct OpenRouterMessage: Codable {
    let role: String
    let content: String?
    let functionCall: OpenRouterFunctionCall?
    
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

private struct OpenRouterFunction: Codable {
    let name: String
    let description: String
    let parameters: FunctionParameters
}

private struct OpenRouterFunctionCall: Codable {
    let name: String
    let arguments: String
}

private struct OpenRouterResponse: Codable {
    let id: String
    let model: String
    let choices: [OpenRouterChoice]
    let usage: OpenRouterUsage?
    let created: Int?
}

private struct OpenRouterChoice: Codable {
    let message: OpenRouterMessage
    let finishReason: String?
    let index: Int
    
    private enum CodingKeys: String, CodingKey {
        case message, index
        case finishReason = "finish_reason"
    }
}

private struct OpenRouterUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    
    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

private struct OpenRouterStreamingChunk: Codable {
    let id: String
    let model: String
    let choices: [OpenRouterStreamingChoice]
}

private struct OpenRouterStreamingChoice: Codable {
    let delta: OpenRouterDelta
    let finishReason: String?
    let index: Int
    
    private enum CodingKeys: String, CodingKey {
        case delta, index
        case finishReason = "finish_reason"
    }
}

private struct OpenRouterDelta: Codable {
    let content: String?
    let role: String?
}