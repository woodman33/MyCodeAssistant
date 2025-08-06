import Foundation

// MARK: - Mistral Provider
/// Mistral AI API implementation of LLMProviderProtocol
public class MistralProvider: BaseLLMProvider {
    
    // MARK: - Initialization
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(
            providerType: .mistral,
            apiKey: apiKey,
            configuration: configuration
        )
    }
    
    // MARK: - LLMProviderProtocol Implementation
    
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        try validateConfiguration()
        try validateRequest(request)
        
        let httpClient = HTTPClient()
        let urlRequest = try createMistralRequest(from: request)
        
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
        let urlRequest = try createMistralRequest(from: request, streaming: true)
        
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
        let mistralRequest = try createMistralRequestBody(from: request)
        
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            return try encoder.encode(mistralRequest)
        } catch {
            throw ProviderError.encodingError(error)
        }
    }
    
    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let mistralResponse = try decoder.decode(MistralResponse.self, from: data)
            return try convertToUnifiedResponse(mistralResponse, originalRequest: originalRequest)
        } catch {
            throw ProviderError.decodingError(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func createMistralRequest(from request: UnifiedRequest, streaming: Bool = false) throws -> URLRequest {
        let endpoint = "/chat/completions"
        var urlRequest = try createBaseRequest(endpoint: endpoint)
        
        let requestBody = try createMistralRequestBody(from: request, streaming: streaming)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(requestBody)
        
        return urlRequest
    }
    
    private func createMistralRequestBody(from request: UnifiedRequest, streaming: Bool = false) throws -> MistralRequest {
        // Convert UnifiedRequest messages to Mistral format
        var messages = request.messages.map { message in
            MistralMessage(
                role: convertRole(message.role),
                content: message.content
            )
        }
        
        // Add system message if provided (Mistral supports system messages)
        if let systemPrompt = request.systemPrompt {
            let systemMessage = MistralMessage(
                role: "system",
                content: systemPrompt
            )
            messages.insert(systemMessage, at: 0)
        }
        
        // Convert functions if provided and supported
        let tools = request.functions?.map { function in
            MistralTool(
                type: "function",
                function: MistralFunction(
                    name: function.name,
                    description: function.description,
                    parameters: function.parameters
                )
            )
        }
        
        let toolChoice: String? = {
            guard let functionCall = request.functionCall else { return nil }
            return "auto" // Mistral uses "auto", "none", or specific function name
        }()
        
        return MistralRequest(
            model: request.model ?? defaultModel,
            messages: messages,
            temperature: request.temperature,
            maxTokens: request.maxTokens,
            tools: tools,
            toolChoice: toolChoice,
            stream: streaming
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
            return "tool" // Mistral uses "tool" for function responses
        }
    }
    
    private func convertToUnifiedResponse(_ mistralResponse: MistralResponse, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        guard let choice = mistralResponse.choices.first else {
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
        
        let usage = mistralResponse.usage.map { usage in
            TokenUsage(
                promptTokens: usage.promptTokens,
                completionTokens: usage.completionTokens,
                totalTokens: usage.totalTokens,
                estimatedCost: estimateCost(for: originalRequest)
            )
        }
        
        return UnifiedResponse(
            id: mistralResponse.id,
            message: message,
            finishReason: finishReason,
            usage: usage,
            model: mistralResponse.model,
            provider: providerType,
            functionCall: functionCall
        )
    }
    
    private func transformStreamingChunk(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let chunk = try decoder.decode(MistralStreamingChunk.self, from: data)
        
        guard let choice = chunk.choices.first else {
            throw ProviderError.invalidRequest("No choices in streaming chunk")
        }
        
        let content = choice.delta.content ?? ""
        
        // Handle function calls in streaming
        var functionCall: FunctionCall? = nil
        if let toolCalls = choice.delta.toolCalls?.first {
            functionCall = FunctionCall(
                name: toolCalls.function?.name ?? "",
                arguments: toolCalls.function?.arguments ?? ""
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

// MARK: - Mistral API Models

private struct MistralRequest: Codable {
    let model: String
    let messages: [MistralMessage]
    let temperature: Double?
    let maxTokens: Int?
    let tools: [MistralTool]?
    let toolChoice: String?
    let stream: Bool?
    
    private enum CodingKeys: String, CodingKey {
        case model, messages, temperature, tools, stream
        case maxTokens = "max_tokens"
        case toolChoice = "tool_choice"
    }
}

private struct MistralMessage: Codable {
    let role: String
    let content: String
    let toolCalls: [MistralToolCall]?
    
    init(role: String, content: String, toolCalls: [MistralToolCall]? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
    }
    
    private enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

private struct MistralTool: Codable {
    let type: String
    let function: MistralFunction
}

private struct MistralFunction: Codable {
    let name: String
    let description: String
    let parameters: FunctionParameters
}

private struct MistralToolCall: Codable {
    let id: String?
    let type: String?
    let function: MistralToolCallFunction
}

private struct MistralToolCallFunction: Codable {
    let name: String
    let arguments: String
}

private struct MistralResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [MistralChoice]
    let usage: MistralUsage?
    
    private enum CodingKeys: String, CodingKey {
        case id, object, created, model, choices, usage
    }
}

private struct MistralChoice: Codable {
    let index: Int
    let message: MistralResponseMessage
    let finishReason: String?
    
    private enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

private struct MistralResponseMessage: Codable {
    let role: String
    let content: String?
    let toolCalls: [MistralToolCall]?
    
    private enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

private struct MistralUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    
    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

private struct MistralStreamingChunk: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [MistralStreamingChoice]
    
    private enum CodingKeys: String, CodingKey {
        case id, object, created, model, choices
    }
}

private struct MistralStreamingChoice: Codable {
    let index: Int
    let delta: MistralDelta
    let finishReason: String?
    
    private enum CodingKeys: String, CodingKey {
        case index, delta
        case finishReason = "finish_reason"
    }
}

private struct MistralDelta: Codable {
    let role: String?
    let content: String?
    let toolCalls: [MistralToolCall]?
    
    private enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}