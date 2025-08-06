import Foundation

// MARK: - Novita AI Provider
/// Novita AI cloud-based GPU inference provider implementation
public class NovitaProvider: BaseLLMProvider {
    
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(
            providerType: .novita,
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
        // Novita AI doesn't support streaming in the same way as OpenAI
        // We'll simulate streaming by chunking the response
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await sendRequest(request)
                    
                    // Simulate streaming by sending the content in chunks
                    let content = response.message.content
                    let chunkSize = max(1, content.count / 10) // Split into ~10 chunks
                    
                    var startIndex = content.startIndex
                    var chunkContent = ""
                    
                    while startIndex < content.endIndex {
                        let endIndex = content.index(startIndex, offsetBy: chunkSize, limitedBy: content.endIndex) ?? content.endIndex
                        let chunk = String(content[startIndex..<endIndex])
                        chunkContent += chunk
                        
                        let chunkMessage = ChatMessage(
                            id: response.message.id,
                            role: response.message.role,
                            content: chunkContent,
                            timestamp: response.message.timestamp
                        )
                        
                        let chunkResponse = UnifiedResponse(
                            id: response.id,
                            message: chunkMessage,
                            finishReason: startIndex == content.endIndex ? response.finishReason : nil,
                            usage: startIndex == content.endIndex ? response.usage : nil,
                            model: response.model,
                            provider: response.provider,
                            timestamp: response.timestamp
                        )
                        
                        continuation.yield(chunkResponse)
                        
                        // Small delay to simulate streaming
                        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        
                        startIndex = endIndex
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
            }
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
            
            // Handle different response formats from Novita AI
            var content = ""
            
            if let choices = json["choices"] as? [[String: Any]], let choice = choices.first {
                if let message = choice["message"] as? [String: Any] {
                    content = message["content"] as? String ?? ""
                } else if let text = choice["text"] as? String {
                    content = text
                }
            } else if let generatedText = json["generated_text"] as? String {
                content = generatedText
            } else if let output = json["output"] as? String {
                content = output
            }
            
            let message = ChatMessage(
                role: .assistant,
                content: content
            )
            
            // Parse token usage if available
            var tokenUsage: TokenUsage?
            if let usage = json["usage"] as? [String: Any] {
                let promptTokens = usage["prompt_tokens"] as? Int ?? 0
                let completionTokens = usage["completion_tokens"] as? Int ?? 0
                tokenUsage = TokenUsage(
                    promptTokens: promptTokens,
                    completionTokens: completionTokens
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
}