import Foundation

// MARK: - Moonshot Provider
/// Moonshot AI provider implementation (Chinese LLM with multilingual support)
public class MoonshotProvider: BaseLLMProvider {
    
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(
            providerType: .moonshot,
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
        try validateConfiguration()
        try validateRequest(request)
        
        let streamingRequest = UnifiedRequest(
            messages: request.messages,
            model: request.model,
            temperature: request.temperature,
            maxTokens: request.maxTokens,
            systemPrompt: request.systemPrompt,
            stream: true,
            functions: request.functions,
            functionCall: request.functionCall,
            metadata: request.metadata
        )
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let endpoint = "/chat/completions"
                    var urlRequest = try createBaseRequest(endpoint: endpoint)
                    urlRequest.httpBody = try transformRequest(streamingRequest)
                    
                    let (asyncBytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: ProviderError.networkError(NSError(domain: "Invalid response", code: -1)))
                        return
                    }
                    
                    if httpResponse.statusCode != 200 {
                        let data = Data()
                        try handleHTTPError(response: httpResponse, data: data)
                    }
                    
                    for try await line in asyncBytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))
                            if jsonString.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
                                continuation.finish()
                                return
                            }
                            
                            if let data = jsonString.data(using: .utf8) {
                                do {
                                    let response = try transformResponse(data, originalRequest: request)
                                    continuation.yield(response)
                                } catch {
                                    // Skip malformed chunks
                                    continue
                                }
                            }
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    public override func transformRequest(_ request: UnifiedRequest) throws -> Data {
        var requestBody: [String: Any] = [
            "model": request.model ?? defaultModel,
            "messages": try request.messages.map { message in
                [
                    "role": message.role.rawValue,
                    "content": message.content
                ]
            },
            "stream": request.stream
        ]
        
        if let temperature = request.temperature {
            requestBody["temperature"] = temperature
        }
        
        if let maxTokens = request.maxTokens {
            requestBody["max_tokens"] = maxTokens
        }
        
        if let systemPrompt = request.systemPrompt {
            var messages = requestBody["messages"] as! [[String: Any]]
            messages.insert(["role": "system", "content": systemPrompt], at: 0)
            requestBody["messages"] = messages
        }
        
        // Moonshot-specific parameters
        requestBody["top_p"] = 0.8 // Nucleus sampling parameter
        
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
            
            // Handle streaming response
            if let choices = json["choices"] as? [[String: Any]], let choice = choices.first {
                if let delta = choice["delta"] as? [String: Any] {
                    let role = delta["role"] as? String ?? "assistant"
                    let content = delta["content"] as? String ?? ""
                    
                    let message = ChatMessage(
                        role: MessageRole(rawValue: role) ?? .assistant,
                        content: content
                    )
                    
                    let finishReason = choice["finish_reason"] as? String
                    
                    return UnifiedResponse(
                        id: id,
                        message: message,
                        finishReason: finishReason.flatMap { FinishReason(rawValue: $0) },
                        model: model,
                        provider: providerType
                    )
                }
            }
            
            // Handle non-streaming response
            if let choices = json["choices"] as? [[String: Any]], let choice = choices.first,
               let message = choice["message"] as? [String: Any] {
                let role = message["role"] as? String ?? "assistant"
                let content = message["content"] as? String ?? ""
                
                let chatMessage = ChatMessage(
                    role: MessageRole(rawValue: role) ?? .assistant,
                    content: content
                )
                
                let finishReason = choice["finish_reason"] as? String
                
                // Parse usage if available
                var tokenUsage: TokenUsage?
                if let usage = json["usage"] as? [String: Any] {
                    let promptTokens = usage["prompt_tokens"] as? Int ?? 0
                    let completionTokens = usage["completion_tokens"] as? Int ?? 0
                    let totalTokens = usage["total_tokens"] as? Int ?? (promptTokens + completionTokens)
                    
                    // Estimate cost for Moonshot models
                    let estimatedCost = providerType.estimateCost(
                        inputTokens: promptTokens,
                        outputTokens: completionTokens,
                        model: model ?? defaultModel
                    )
                    
                    tokenUsage = TokenUsage(
                        promptTokens: promptTokens,
                        completionTokens: completionTokens,
                        totalTokens: totalTokens,
                        estimatedCost: estimatedCost
                    )
                }
                
                return UnifiedResponse(
                    id: id,
                    message: chatMessage,
                    finishReason: finishReason.flatMap { FinishReason(rawValue: $0) },
                    usage: tokenUsage,
                    model: model,
                    provider: providerType
                )
            }
            
            throw ProviderError.decodingError(NSError(domain: "No valid message found in response", code: -1))
            
        } catch {
            throw ProviderError.decodingError(error)
        }
    }
}