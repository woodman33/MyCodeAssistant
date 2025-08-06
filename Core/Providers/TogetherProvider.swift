import Foundation

// MARK: - Together.ai Provider
/// Together.ai API implementation of LLMProviderProtocol
public class TogetherAIProvider: BaseLLMProvider {
    
    // MARK: - Initialization
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(
            providerType: .togetherAI,
            apiKey: apiKey,
            configuration: configuration
        )
    }
    
    // MARK: - LLMProviderProtocol Implementation
    
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        try validateConfiguration()
        try validateRequest(request)
        
        let httpClient = HTTPClient()
        let urlRequest = try createTogetherRequest(from: request)
        
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
        let urlRequest = try createTogetherRequest(from: request, streaming: true)
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let dataStream = try await httpClient.performStreamingRequest(urlRequest)
                    
                    for try await data in dataStream {
                        let lines = String(data: data, encoding: .utf8)?
                            .components(separatedBy: "\n")
                            .compactMap { line in
                                line.hasPrefix("data: ") ? String(line.dropFirst(6)) : nil
                            }
                            .filter { !$0.isEmpty && $0 != "[DONE]" } ?? []
                        
                        for line in lines {
                            if let chunkData = line.data(using: .utf8) {
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
        let togetherRequest = try createTogetherRequestBody(from: request)
        
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            return try encoder.encode(togetherRequest)
        } catch {
            throw ProviderError.encodingError(error)
        }
    }
    
    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let togetherResponse = try decoder.decode(TogetherResponse.self, from: data)
            return try convertToUnifiedResponse(togetherResponse, originalRequest: originalRequest)
        } catch {
            throw ProviderError.decodingError(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func createTogetherRequest(from request: UnifiedRequest, streaming: Bool = false) throws -> URLRequest {
        let endpoint = "/chat/completions"
        var urlRequest = try createBaseRequest(endpoint: endpoint)
        
        let requestBody = try createTogetherRequestBody(from: request, streaming: streaming)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(requestBody)
        
        return urlRequest
    }
    
    private func createTogetherRequestBody(from request: UnifiedRequest, streaming: Bool = false) throws -> TogetherRequest {
        // Convert UnifiedRequest messages to Together format
        var messages = request.messages.map { message in
            TogetherMessage(
                role: convertRole(message.role),
                content: message.content
            )
        }
        
        // Add system message if provided (Together.ai supports system messages)
        if let systemPrompt = request.systemPrompt {
            let systemMessage = TogetherMessage(
                role: "system",
                content: systemPrompt
            )
            messages.insert(systemMessage, at: 0)
        }
        
        // Convert functions if provided and supported
        let tools = request.functions?.map { function in
            TogetherTool(
                type: "function",
                function: TogetherFunction(
                    name: function.name,
                    description: function.description,
                    parameters: function.parameters
                )
            )
        }
        
        let toolChoice: String? = {
            guard let functionCall = request.functionCall else { return nil }
            return "auto" // Together.ai uses "auto", "none", or specific function name
        }()
        
        return TogetherRequest(
            model: request.model ?? defaultModel,
            messages: messages,
            temperature: request.temperature,
            maxTokens: request.maxTokens,
            topP: nil, // Can be added if needed
            topK: nil, // Can be added if needed
            repetitionPenalty: nil, // Can be added if needed
            stop: nil, // Can be added if needed
            tools: tools,
            toolChoice: toolChoice,
            stream: streaming,
            responseFormat: nil, // Can be set to {"type": "json_object"} for JSON mode
            safetyModel: nil, // Optional safety model
            reasoningEffort: nil // Can be "low", "medium", or "high"
        )
    }
    
    private func convertRole(_ role: MessageRole) -> String {
        switch role {
        case .user:
            return "user"
        case .assistant:
            return "assistant"
        case .system:
            return "system"
        case .function:
            return "tool" // Together.ai uses "tool" for function responses
        }
    }
    
    private func convertToUnifiedResponse(_ togetherResponse: TogetherResponse, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        guard let choice = togetherResponse.choices.first else {
            throw ProviderError.invalidRequest("No choices in response")
        }
        
        // Handle function calls if present
        var functionCall: FunctionCall? = nil
        if let toolCalls = choice.message.toolCalls?.first {
            functionCall = FunctionCall(
                name: toolCalls.function.name,
                arguments: toolCalls.function.arguments
            )
        }
        
        let message = ChatMessage(
            role: .assistant,
            content: choice.message.content ?? ""
        )
        
        let finishReason = mapFinishReason(choice.finishReason)
        
        let usage = togetherResponse.usage.map { usage in
            TokenUsage(
                promptTokens: usage.promptTokens,
                completionTokens: usage.completionTokens,
                totalTokens: usage.totalTokens,
                estimatedCost: estimateCost(for: originalRequest)
            )
        }
        
        return UnifiedResponse(
            id: togetherResponse.id,
            message: message,
            finishReason: finishReason,
            usage: usage,
            model: togetherResponse.model,
            provider: providerType,
            functionCall: functionCall
        )
    }
    
    private func transformStreamingChunk(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let chunk = try decoder.decode(TogetherStreamingChunk.self, from: data)
        
        guard let choice = chunk.choices.first else {
            throw ProviderError.invalidRequest("No choices in streaming chunk")
        }
        
        let content = choice.delta.content ?? ""
        
        // Handle function calls in streaming
        var functionCall: FunctionCall? = nil
        if let toolCalls = choice.delta.toolCalls?.first {
            functionCall = FunctionCall(
                name: toolCalls.function.name,
                arguments: toolCalls.function.arguments
            )
        }
        
        let message = ChatMessage(
            role: .assistant,
            content: content
        )
        
        let finishReason = mapFinishReason(choice.finishReason)
        
        return UnifiedResponse(
            id: chunk.id,
            message: message,
            finishReason: finishReason,
            model: chunk.model,
            provider: providerType,
            functionCall: functionCall
        )
    }
    
    private func mapFinishReason(_ finishReason: String?) -> FinishReason? {
        guard let finishReason = finishReason else { return nil }
        
        switch finishReason {
        case "stop":
            return .stop
        case "length":
            return .length
        case "tool_calls":
            return .functionCall
        case "content_filter":
            return .contentFilter
        default:
            return .stop
        }
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

// MARK: - Together.ai API Models

private struct TogetherRequest: Codable {
    let model: String
    let messages: [TogetherMessage]
    let temperature: Double?
    let maxTokens: Int?
    let topP: Double?
    let topK: Int?
    let repetitionPenalty: Double?
    let stop: [String]?
    let tools: [TogetherTool]?
    let toolChoice: String?
    let stream: Bool?
    let responseFormat: TogetherResponseFormat?
    let safetyModel: String?
    let reasoningEffort: String?
    
    private enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stop, tools, stream
        case maxTokens = "max_tokens"
        case topP = "top_p"
        case topK = "top_k"
        case repetitionPenalty = "repetition_penalty"
        case toolChoice = "tool_choice"
        case responseFormat = "response_format"
        case safetyModel = "safety_model"
        case reasoningEffort = "reasoning_effort"
    }
}

private struct TogetherMessage: Codable {
    let role: String
    let content: String
    let toolCalls: [TogetherToolCall]?
    
    init(role: String, content: String, toolCalls: [TogetherToolCall]? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
    }
    
    private enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

private struct TogetherTool: Codable {
    let type: String
    let function: TogetherFunction
}

private struct TogetherFunction: Codable {
    let name: String
    let description: String
    let parameters: FunctionParameters
}

private struct TogetherToolCall: Codable {
    let id: String?
    let type: String?
    let function: TogetherToolCallFunction
}

private struct TogetherToolCallFunction: Codable {
    let name: String
    let arguments: String
}

private struct TogetherResponseFormat: Codable {
    let type: String // "json_object"
}

private struct TogetherResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [TogetherChoice]
    let usage: TogetherUsage?
    let warnings: [String]?
    
    private enum CodingKeys: String, CodingKey {
        case id, object, created, model, choices, usage, warnings
    }
}

private struct TogetherChoice: Codable {
    let index: Int
    let message: TogetherResponseMessage
    let finishReason: String?
    
    private enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

private struct TogetherResponseMessage: Codable {
    let role: String
    let content: String?
    let toolCalls: [TogetherToolCall]?
    
    private enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

private struct TogetherUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    
    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

private struct TogetherStreamingChunk: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [TogetherStreamingChoice]
    
    private enum CodingKeys: String, CodingKey {
        case id, object, created, model, choices
    }
}

private struct TogetherStreamingChoice: Codable {
    let index: Int
    let delta: TogetherDelta
    let finishReason: String?
    
    private enum CodingKeys: String, CodingKey {
        case index, delta
        case finishReason = "finish_reason"
    }
}

private struct TogetherDelta: Codable {
    let role: String?
    let content: String?
    let toolCalls: [TogetherToolCall]?
    
    private enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}