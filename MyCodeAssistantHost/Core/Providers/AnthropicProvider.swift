import Foundation

// MARK: - Anthropic Provider
/// Anthropic Claude API implementation of LLMProviderProtocol
public class AnthropicProvider: BaseLLMProvider {
    
    // MARK: - Initialization
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(
            providerType: .anthropic,
            apiKey: apiKey,
            configuration: configuration
        )
    }
    
    // MARK: - LLMProviderProtocol Implementation
    
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        try validateConfiguration()
        try validateRequest(request)
        
        let httpClient = HTTPClient()
        let urlRequest = try createAnthropicRequest(from: request)
        
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
        let urlRequest = try createAnthropicRequest(from: request, streaming: true)
        
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
        let anthropicRequest = try createAnthropicRequestBody(from: request)
        
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            return try encoder.encode(anthropicRequest)
        } catch {
            throw ProviderError.encodingError(error)
        }
    }
    
    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let anthropicResponse = try decoder.decode(AnthropicResponse.self, from: data)
            return try convertToUnifiedResponse(anthropicResponse, originalRequest: originalRequest)
        } catch {
            throw ProviderError.decodingError(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func createAnthropicRequest(from request: UnifiedRequest, streaming: Bool = false) throws -> URLRequest {
        let endpoint = "/messages"
        var urlRequest = try createBaseRequest(endpoint: endpoint)
        
        let requestBody = try createAnthropicRequestBody(from: request, streaming: streaming)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(requestBody)
        
        return urlRequest
    }
    
    private func createAnthropicRequestBody(from request: UnifiedRequest, streaming: Bool = false) throws -> AnthropicRequest {
        // Convert UnifiedRequest messages to Anthropic format
        let messages = request.messages.map { message in
            AnthropicMessage(
                role: convertRole(message.role),
                content: message.content
            )
        }
        
        return AnthropicRequest(
            model: request.model ?? defaultModel,
            maxTokens: request.maxTokens ?? 4096, // Anthropic requires max_tokens
            messages: messages,
            system: request.systemPrompt,
            temperature: request.temperature,
            stream: streaming
        )
    }
    
    private func convertRole(_ role: MessageRole) -> String {
        switch role {
        case .user:
            return "user"
        case .assistant:
            return "assistant"
        case .system, .function:
            // Anthropic doesn't use system/function roles in messages array
            // System prompts go in the system parameter
            return "user"
        }
    }
    
    private func convertToUnifiedResponse(_ anthropicResponse: AnthropicResponse, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        // Extract content from Anthropic's content array
        let content = anthropicResponse.content.compactMap { contentBlock in
            contentBlock.text
        }.joined(separator: "\n")
        
        let message = ChatMessage(
            role: .assistant,
            content: content
        )
        
        let finishReason = mapFinishReason(anthropicResponse.stopReason)
        
        let usage = TokenUsage(
            promptTokens: anthropicResponse.usage.inputTokens,
            completionTokens: anthropicResponse.usage.outputTokens,
            totalTokens: anthropicResponse.usage.inputTokens + anthropicResponse.usage.outputTokens,
            estimatedCost: estimateCost(for: originalRequest)
        )
        
        return UnifiedResponse(
            id: anthropicResponse.id,
            message: message,
            finishReason: finishReason,
            usage: usage,
            model: anthropicResponse.model,
            provider: providerType
        )
    }
    
    private func transformStreamingChunk(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let chunk = try decoder.decode(AnthropicStreamingChunk.self, from: data)
        
        var content = ""
        
        // Handle different chunk types
        switch chunk.type {
        case "content_block_delta":
            if let delta = chunk.delta {
                content = delta.text ?? ""
            }
        case "message_start":
            // Initial message chunk, usually empty content
            content = ""
        case "message_stop":
            // Final chunk, no content
            content = ""
        default:
            content = ""
        }
        
        let message = ChatMessage(
            role: .assistant,
            content: content
        )
        
        let finishReason = chunk.type == "message_stop" ? .stop : nil
        
        return UnifiedResponse(
            id: chunk.message?.id ?? UUID().uuidString,
            message: message,
            finishReason: finishReason,
            model: chunk.message?.model,
            provider: providerType
        )
    }
    
    private func mapFinishReason(_ stopReason: String?) -> FinishReason? {
        guard let stopReason = stopReason else { return nil }
        
        switch stopReason {
        case "end_turn":
            return .stop
        case "max_tokens":
            return .length
        case "stop_sequence":
            return .stop
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

// MARK: - Anthropic API Models

private struct AnthropicRequest: Codable {
    let model: String
    let maxTokens: Int
    let messages: [AnthropicMessage]
    let system: String?
    let temperature: Double?
    let stream: Bool?
    
    private enum CodingKeys: String, CodingKey {
        case model, messages, system, temperature, stream
        case maxTokens = "max_tokens"
    }
}

private struct AnthropicMessage: Codable {
    let role: String
    let content: String
}

private struct AnthropicResponse: Codable {
    let id: String
    let model: String
    let role: String
    let content: [AnthropicContentBlock]
    let stopReason: String?
    let stopSequence: String?
    let usage: AnthropicUsage
    
    private enum CodingKeys: String, CodingKey {
        case id, model, role, content, usage
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
    }
}

private struct AnthropicContentBlock: Codable {
    let type: String
    let text: String?
}

private struct AnthropicUsage: Codable {
    let inputTokens: Int
    let outputTokens: Int
    
    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

private struct AnthropicStreamingChunk: Codable {
    let type: String
    let message: AnthropicStreamingMessage?
    let index: Int?
    let delta: AnthropicStreamingDelta?
    
    private enum CodingKeys: String, CodingKey {
        case type, message, index, delta
    }
}

private struct AnthropicStreamingMessage: Codable {
    let id: String
    let model: String?
    let role: String?
    let content: [AnthropicContentBlock]?
    let stopReason: String?
    let stopSequence: String?
    let usage: AnthropicUsage?
    
    private enum CodingKeys: String, CodingKey {
        case id, model, role, content, usage
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
    }
}

private struct AnthropicStreamingDelta: Codable {
    let type: String?
    let text: String?
    let stopReason: String?
    let stopSequence: String?
    
    private enum CodingKeys: String, CodingKey {
        case type, text
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
    }
}