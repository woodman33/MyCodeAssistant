import Foundation

// MARK: - Abacus.AI Provider
/// Abacus.AI predictive modeling provider implementation
public class AbacusAIProvider: BaseLLMProvider {
    
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(
            providerType: .abacusAI,
            apiKey: apiKey,
            configuration: configuration
        )
    }
    
    // MARK: - LLMProviderProtocol Implementation
    
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        try validateConfiguration()
        try validateRequest(request)
        
        let endpoint = "/chat/completions"
        var urlRequest = try createBaseRequest(endpoint: endpoint)
        urlRequest.httpBody = try transformRequest(request)
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError(NSError(domain: "Invalid response", code: -1))
        }
        
        if httpResponse.statusCode != 200 {
            try handleHTTPError(response: httpResponse, data: data)
        }
        
        return try transformResponse(data, originalRequest: request)
    }
    
    public override func sendStreamingRequest(_ request: UnifiedRequest) async throws -> AsyncThrowingStream<UnifiedResponse, Error> {
        // Abacus.AI doesn't support streaming in the traditional sense
        // We'll simulate streaming by returning the complete response as a single chunk
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await sendRequest(request)
                    continuation.yield(response)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    public override func transformRequest(_ request: UnifiedRequest) throws -> Data {
        // Abacus.AI has a different request format focused on predictive tasks
        var requestBody: [String: Any] = [
            "model": request.model ?? defaultModel,
            "prompt": formatMessagesAsPrompt(request.messages),
            "max_length": request.maxTokens ?? 2048
        ]
        
        if let temperature = request.temperature {
            requestBody["temperature"] = temperature
        }
        
        // Add system prompt if provided
        if let systemPrompt = request.systemPrompt {
            let currentPrompt = requestBody["prompt"] as? String ?? ""
            requestBody["prompt"] = "\(systemPrompt)\n\n\(currentPrompt)"
        }
        
        do {
            return try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw ProviderError.encodingError(error)
        }
    }
    
    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ProviderError.decodingError(NSError(domain: "Invalid JSON", code: -1))
            }
            
            let id = json["id"] as? String ?? UUID().uuidString
            let model = json["model"] as? String
            
            // Abacus.AI typically returns predictions in a different format
            let generatedText = json["generated_text"] as? String ?? 
                                json["prediction"] as? String ?? 
                                json["output"] as? String ?? ""
            
            let message = ChatMessage(
                role: .assistant,
                content: generatedText
            )
            
            // Parse token usage if available
            var tokenUsage: TokenUsage?
            if let usage = json["usage"] as? [String: Any] {
                let totalTokens = usage["total_tokens"] as? Int ?? estimateTokens(in: generatedText)
                let inputTokens = usage["input_tokens"] as? Int ?? 0
                let outputTokens = totalTokens - inputTokens
                
                tokenUsage = TokenUsage(
                    promptTokens: inputTokens,
                    completionTokens: outputTokens,
                    totalTokens: totalTokens
                )
            }
            
            return UnifiedResponse(
                id: id,
                message: message,
                finishReason: .stop,
                usage: tokenUsage,
                model: model,
                provider: providerType
            )
            
        } catch {
            throw ProviderError.decodingError(error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatMessagesAsPrompt(_ messages: [ChatMessage]) -> String {
        return messages.map { message in
            switch message.role {
            case .system:
                return "System: \(message.content)"
            case .user:
                return "User: \(message.content)"
            case .assistant:
                return "Assistant: \(message.content)"
            case .function:
                return "Function: \(message.content)"
            }
        }.joined(separator: "\n\n")
    }
}