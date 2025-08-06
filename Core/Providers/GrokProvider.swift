import Foundation

// MARK: - Grok Provider
/// xAI's Grok API implementation of LLMProviderProtocol
public class GrokProvider: BaseLLMProvider {
    
    // MARK: - Initialization
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(
            providerType: .grok,
            apiKey: apiKey,
            configuration: configuration
        )
    }
    
    // MARK: - LLMProviderProtocol Implementation
    
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        try validateConfiguration()
        try validateRequest(request)
        
        let httpClient = HTTPClient()
        let urlRequest = try createGrokRequest(from: request)
        
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
        let urlRequest = try createGrokRequest(from: request, streaming: true)
        
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
        let grokRequest = try createGrokRequestBody(from: request)
        
        do {
            let encoder = JSONEncoder()
            return try encoder.encode(grokRequest)
        } catch {
            throw ProviderError.encodingError(error)
        }
    }
    
    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        do {
            let decoder = JSONDecoder()
            let grokResponse = try decoder.decode(GrokResponse.self, from: data)
            return try convertToUnifiedResponse(grokResponse, originalRequest: originalRequest)
        } catch {
            throw ProviderError.decodingError(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func createGrokRequest(from request: UnifiedRequest, streaming: Bool = false) throws -> URLRequest {
        let endpoint = "/chat/completions"
        var urlRequest = try createBaseRequest(endpoint: endpoint)
        
        let requestBody = try createGrokRequestBody(from: request, streaming: streaming)
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)
        
        return urlRequest
    }
    
    private func createGrokRequestBody(from request: UnifiedRequest, streaming: Bool = false) throws -> GrokRequest {
        let messages = request.messages.map { message in
            GrokMessage(
                role: message.role.rawValue,
                content: message.content
            )
        }
        
        // Add system prompt as first message if provided
        var allMessages = messages
        if let systemPrompt = request.systemPrompt {
            let systemMessage = GrokMessage(role: "system", content: systemPrompt)
            allMessages.insert(systemMessage, at: 0)
        }
        
        return GrokRequest(
            model: request.model ?? defaultModel,
            messages: allMessages,
            temperature: request.temperature,
            maxTokens: request.maxTokens,
            stream: streaming
        )
    }
    
    private func convertToUnifiedResponse(_ grokResponse: GrokResponse, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        guard let choice = grokResponse.choices.first else {
            throw ProviderError.invalidRequest("No choices in response")
        }
        
        let message = ChatMessage(
            role: MessageRole(rawValue: choice.message.role) ?? .assistant,
            content: choice.message.content ?? ""
        )
        
        let finishReason = FinishReason(rawValue: choice.finishReason ?? "stop") ?? .stop
        
        let usage = grokResponse.usage.map { grokUsage in
            TokenUsage(
                promptTokens: grokUsage.promptTokens,
                completionTokens: grokUsage.completionTokens,
                totalTokens: grokUsage.totalTokens,
                estimatedCost: estimateCost(for: originalRequest)
            )
        }
        
        return UnifiedResponse(
            id: grokResponse.id,
            message: message,
            finishReason: finishReason,
            usage: usage,
            model: grokResponse.model,
            provider: providerType
        )
    }
    
    private func transformStreamingChunk(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        let decoder = JSONDecoder()
        let chunk = try decoder.decode(GrokStreamingChunk.self, from: data)
        
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

// MARK: - Grok API Models

private struct GrokRequest: Codable {
    let model: String
    let messages: [GrokMessage]
    let temperature: Double?
    let maxTokens: Int?
    let stream: Bool?
    
    private enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
    }
}

private struct GrokMessage: Codable {
    let role: String
    let content: String?
    
    init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

private struct GrokResponse: Codable {
    let id: String
    let model: String
    let choices: [GrokChoice]
    let usage: GrokUsage?
    let created: Int?
}

private struct GrokChoice: Codable {
    let message: GrokMessage
    let finishReason: String?
    let index: Int
    
    private enum CodingKeys: String, CodingKey {
        case message, index
        case finishReason = "finish_reason"
    }
}

private struct GrokUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    
    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

private struct GrokStreamingChunk: Codable {
    let id: String
    let model: String
    let choices: [GrokStreamingChoice]
}

private struct GrokStreamingChoice: Codable {
    let delta: GrokDelta
    let finishReason: String?
    let index: Int
    
    private enum CodingKeys: String, CodingKey {
        case delta, index
        case finishReason = "finish_reason"
    }
}

private struct GrokDelta: Codable {
    let content: String?
    let role: String?
}