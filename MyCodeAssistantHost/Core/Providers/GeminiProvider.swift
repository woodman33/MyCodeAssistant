import Foundation

// MARK: - Gemini Provider
/// Google Gemini API implementation of LLMProviderProtocol
public class GeminiProvider: BaseLLMProvider {
    
    // MARK: - Initialization
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(
            providerType: .gemini,
            apiKey: apiKey,
            configuration: configuration
        )
    }
    
    // MARK: - LLMProviderProtocol Implementation
    
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        try validateConfiguration()
        try validateRequest(request)
        
        let httpClient = HTTPClient()
        let urlRequest = try createGeminiRequest(from: request)
        
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
        let urlRequest = try createGeminiRequest(from: request, streaming: true)
        
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
        let geminiRequest = try createGeminiRequestBody(from: request)
        
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            return try encoder.encode(geminiRequest)
        } catch {
            throw ProviderError.encodingError(error)
        }
    }
    
    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let geminiResponse = try decoder.decode(GeminiResponse.self, from: data)
            return try convertToUnifiedResponse(geminiResponse, originalRequest: originalRequest)
        } catch {
            throw ProviderError.decodingError(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func createGeminiRequest(from request: UnifiedRequest, streaming: Bool = false) throws -> URLRequest {
        let model = request.model ?? defaultModel
        let endpoint = streaming ? "/models/\(model):streamGenerateContent" : "/models/\(model):generateContent"
        
        var urlRequest = try createBaseRequest(endpoint: endpoint)
        
        // Add API key as query parameter for Gemini
        if let apiKey = apiKey,
           let url = urlRequest.url,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
            urlRequest.url = components.url
        }
        
        // Remove the x-goog-api-key header since we're using query parameter
        urlRequest.setValue(nil, forHTTPHeaderField: "x-goog-api-key")
        
        let requestBody = try createGeminiRequestBody(from: request, streaming: streaming)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(requestBody)
        
        return urlRequest
    }
    
    private func createGeminiRequestBody(from request: UnifiedRequest, streaming: Bool = false) throws -> GeminiRequest {
        // Convert messages to Gemini Content format
        var contents: [GeminiContent] = []
        
        // Add system prompt if present
        if let systemPrompt = request.systemPrompt {
            contents.append(GeminiContent(
                role: "user",
                parts: [GeminiPart(text: "System: \(systemPrompt)")]
            ))
        }
        
        // Convert chat messages
        for message in request.messages {
            let role = convertRole(message.role)
            let content = GeminiContent(
                role: role,
                parts: [GeminiPart(text: message.content)]
            )
            contents.append(content)
        }
        
        var generationConfig: GeminiGenerationConfig? = nil
        if request.temperature != nil || request.maxTokens != nil {
            generationConfig = GeminiGenerationConfig(
                temperature: request.temperature,
                maxOutputTokens: request.maxTokens
            )
        }
        
        return GeminiRequest(
            contents: contents,
            generationConfig: generationConfig
        )
    }
    
    private func convertRole(_ role: MessageRole) -> String {
        switch role {
        case .user, .system:
            return "user"
        case .assistant:
            return "model"
        case .function:
            return "user" // Gemini doesn't have explicit function role
        }
    }
    
    private func convertToUnifiedResponse(_ geminiResponse: GeminiResponse, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        guard let candidate = geminiResponse.candidates.first else {
            throw ProviderError.invalidRequest("No candidates in response")
        }
        
        // Extract text content from parts
        let content = candidate.content.parts.compactMap { part in
            part.text
        }.joined(separator: "\n")
        
        let message = ChatMessage(
            role: .assistant,
            content: content
        )
        
        let finishReason = mapFinishReason(candidate.finishReason)
        
        let usage = geminiResponse.usageMetadata.map { metadata in
            TokenUsage(
                promptTokens: metadata.promptTokenCount,
                completionTokens: metadata.candidatesTokenCount,
                totalTokens: metadata.totalTokenCount,
                estimatedCost: estimateCost(for: originalRequest)
            )
        }
        
        return UnifiedResponse(
            id: UUID().uuidString, // Gemini doesn't provide response ID
            message: message,
            finishReason: finishReason,
            usage: usage,
            model: originalRequest.model ?? defaultModel,
            provider: providerType
        )
    }
    
    private func transformStreamingChunk(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let chunk = try decoder.decode(GeminiResponse.self, from: data)
        
        guard let candidate = chunk.candidates.first else {
            throw ProviderError.invalidRequest("No candidates in streaming chunk")
        }
        
        let content = candidate.content.parts.compactMap { part in
            part.text
        }.joined(separator: "\n")
        
        let message = ChatMessage(
            role: .assistant,
            content: content
        )
        
        let finishReason = mapFinishReason(candidate.finishReason)
        
        return UnifiedResponse(
            id: UUID().uuidString,
            message: message,
            finishReason: finishReason,
            model: originalRequest.model ?? defaultModel,
            provider: providerType
        )
    }
    
    private func mapFinishReason(_ finishReason: String?) -> FinishReason? {
        guard let finishReason = finishReason else { return nil }
        
        switch finishReason {
        case "STOP":
            return .stop
        case "MAX_TOKENS":
            return .length
        case "SAFETY":
            return .contentFilter
        case "RECITATION":
            return .contentFilter
        case "OTHER":
            return .error
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
                case 401, 403:
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

// MARK: - Gemini API Models

private struct GeminiRequest: Codable {
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig?
    
    private enum CodingKeys: String, CodingKey {
        case contents
        case generationConfig = "generationConfig"
    }
}

private struct GeminiContent: Codable {
    let role: String
    let parts: [GeminiPart]
}

private struct GeminiPart: Codable {
    let text: String?
    
    init(text: String) {
        self.text = text
    }
}

private struct GeminiGenerationConfig: Codable {
    let temperature: Double?
    let maxOutputTokens: Int?
    
    private enum CodingKeys: String, CodingKey {
        case temperature
        case maxOutputTokens = "maxOutputTokens"
    }
}

private struct GeminiResponse: Codable {
    let candidates: [GeminiCandidate]
    let usageMetadata: GeminiUsageMetadata?
    
    private enum CodingKeys: String, CodingKey {
        case candidates
        case usageMetadata = "usageMetadata"
    }
}

private struct GeminiCandidate: Codable {
    let content: GeminiContent
    let finishReason: String?
    let index: Int?
    let safetyRatings: [GeminiSafetyRating]?
    
    private enum CodingKeys: String, CodingKey {
        case content, index
        case finishReason = "finishReason"
        case safetyRatings = "safetyRatings"
    }
}

private struct GeminiSafetyRating: Codable {
    let category: String
    let probability: String
}

private struct GeminiUsageMetadata: Codable {
    let promptTokenCount: Int
    let candidatesTokenCount: Int
    let totalTokenCount: Int
    
    private enum CodingKeys: String, CodingKey {
        case promptTokenCount = "promptTokenCount"
        case candidatesTokenCount = "candidatesTokenCount"
        case totalTokenCount = "totalTokenCount"
    }
}