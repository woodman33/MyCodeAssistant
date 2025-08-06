import Foundation

// MARK: - Hugging Face Provider
/// Hugging Face inference API provider implementation
public class HuggingFaceProvider: BaseLLMProvider {
    
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(
            providerType: .huggingFace,
            apiKey: apiKey,
            configuration: configuration
        )
    }
    
    // MARK: - LLMProviderProtocol Implementation
    
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        try validateConfiguration()
        try validateRequest(request)
        
        let model = request.model ?? defaultModel
        let endpoint = "/models/\(model)"
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
        // Hugging Face Inference API doesn't support streaming for most models
        // We'll simulate streaming by chunking the response
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await sendRequest(request)
                    
                    // Simulate streaming by sending the content word by word
                    let words = response.message.content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                    var accumulatedContent = ""
                    
                    for (index, word) in words.enumerated() {
                        if index > 0 {
                            accumulatedContent += " "
                        }
                        accumulatedContent += word
                        
                        let chunkMessage = ChatMessage(
                            id: response.message.id,
                            role: response.message.role,
                            content: accumulatedContent,
                            timestamp: response.message.timestamp
                        )
                        
                        let chunkResponse = UnifiedResponse(
                            id: response.id,
                            message: chunkMessage,
                            finishReason: index == words.count - 1 ? response.finishReason : nil,
                            usage: index == words.count - 1 ? response.usage : nil,
                            model: response.model,
                            provider: response.provider,
                            timestamp: response.timestamp
                        )
                        
                        continuation.yield(chunkResponse)
                        
                        // Small delay to simulate typing
                        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    public override func transformRequest(_ request: UnifiedRequest) throws -> Data {
        // Hugging Face Inference API typically uses different formats depending on the model
        // For text generation models, we usually send the prompt as input
        let prompt = formatMessagesAsPrompt(request.messages, systemPrompt: request.systemPrompt)
        
        var requestBody: [String: Any] = [
            "inputs": prompt,
            "parameters": [:]
        ]
        
        var parameters: [String: Any] = [:]
        
        if let temperature = request.temperature {
            parameters["temperature"] = temperature
        }
        
        if let maxTokens = request.maxTokens {
            parameters["max_new_tokens"] = maxTokens
        }
        
        // Add common parameters for text generation
        parameters["do_sample"] = true
        parameters["return_full_text"] = false
        
        requestBody["parameters"] = parameters
        
        // Some models might need specific options
        requestBody["options"] = [
            "wait_for_model": true,
            "use_cache": false
        ]
        
        do {
            return try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw ProviderError.encodingError(error)
        }
    }
    
    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        do {
            // Hugging Face can return different response formats
            if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                // Array format (common for text generation)
                guard let firstResult = jsonArray.first else {
                    throw ProviderError.decodingError(NSError(domain: "Empty response array", code: -1))
                }
                
                let generatedText = firstResult["generated_text"] as? String ?? ""
                
                let message = ChatMessage(
                    role: .assistant,
                    content: generatedText
                )
                
                return UnifiedResponse(
                    id: UUID().uuidString,
                    message: message,
                    finishReason: .stop,
                    model: originalRequest.model,
                    provider: providerType
                )
                
            } else if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Object format
                let generatedText = json["generated_text"] as? String ?? 
                                  json["output"] as? String ?? 
                                  json["text"] as? String ?? ""
                
                let message = ChatMessage(
                    role: .assistant,
                    content: generatedText
                )
                
                return UnifiedResponse(
                    id: json["id"] as? String ?? UUID().uuidString,
                    message: message,
                    finishReason: .stop,
                    model: originalRequest.model,
                    provider: providerType
                )
            } else {
                // Fallback: treat as plain text
                let text = String(data: data, encoding: .utf8) ?? ""
                
                let message = ChatMessage(
                    role: .assistant,
                    content: text
                )
                
                return UnifiedResponse(
                    id: UUID().uuidString,
                    message: message,
                    finishReason: .stop,
                    model: originalRequest.model,
                    provider: providerType
                )
            }
            
        } catch {
            throw ProviderError.decodingError(error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatMessagesAsPrompt(_ messages: [ChatMessage], systemPrompt: String?) -> String {
        var prompt = ""
        
        if let systemPrompt = systemPrompt {
            prompt += "\(systemPrompt)\n\n"
        }
        
        for message in messages {
            switch message.role {
            case .system:
                prompt += "System: \(message.content)\n"
            case .user:
                prompt += "Human: \(message.content)\n"
            case .assistant:
                prompt += "Assistant: \(message.content)\n"
            case .function:
                prompt += "Function: \(message.content)\n"
            }
        }
        
        // Add prompt for the next assistant response
        prompt += "Assistant:"
        
        return prompt
    }
}