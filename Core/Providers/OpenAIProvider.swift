import Foundation

// MARK: - OpenAI Provider
/// OpenAI API implementation of LLMProviderProtocol
public class OpenAIProvider: BaseLLMProvider {
    
    // MARK: - Initialization
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(
            providerType: .openAI,
            apiKey: apiKey,
            configuration: configuration
        )
    }
    
    // MARK: - LLMProviderProtocol Implementation
    
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        try validateConfiguration()
        try validateRequest(request)
        
        let httpClient = HTTPClient()
        let urlRequest = try createOpenAIRequest(from: request)
        
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
        let urlRequest = try createOpenAIRequest(from: request, streaming: true)
        
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
        let openAIRequest = try createOpenAIRequestBody(from: request)
        
        do {
            let encoder = JSONEncoder()
            return try encoder.encode(openAIRequest)
        } catch {
            throw ProviderError.encodingError(error)
        }
    }
    
    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        do {
            let decoder = JSONDecoder()
            let openAIResponse = try decoder.decode(OpenAIResponse.self, from: data)
            return try convertToUnifiedResponse(openAIResponse, originalRequest: originalRequest)
        } catch {
            throw ProviderError.decodingError(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func createOpenAIRequest(from request: UnifiedRequest, streaming: Bool = false) throws -> URLRequest {
        let endpoint = "/chat/completions"
        var urlRequest = try createBaseRequest(endpoint: endpoint)
        
        let requestBody = try createOpenAIRequestBody(from: request, streaming: streaming)
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)
        
        return urlRequest
    }
    
    private func createOpenAIRequestBody(from request: UnifiedRequest, streaming: Bool = false) throws -> OpenAIRequest {
        let messages = request.messages.map { message in
            OpenAIMessage(
                role: message.role.rawValue,
                content: message.content
            )
        }
        
        // Add system prompt as first message if provided
        var allMessages = messages
        if let systemPrompt = request.systemPrompt {
            let systemMessage = OpenAIMessage(role: "system", content: systemPrompt)
            allMessages.insert(systemMessage, at: 0)
        }
        
        return OpenAIRequest(
            model: request.model ?? defaultModel,
            messages: allMessages,
            temperature: request.temperature,
            maxTokens: request.maxTokens,
            stream: streaming,
            functions: request.functions?.map { convertToOpenAIFunction($0) },
            functionCall: request.functionCall.map { convertToOpenAIFunctionCall($0) }
        )
    }
    
    private func convertToOpenAIFunction(_ function: Function) -> OpenAIFunction {
        return OpenAIFunction(
            name: function.name,
            description: function.description,
            parameters: function.parameters
        )
    }
    
    private func convertToOpenAIFunctionCall(_ functionCall: FunctionCall) -> OpenAIFunctionCall {
        return OpenAIFunctionCall(
            name: functionCall.name,
            arguments: functionCall.arguments
        )
    }
    
    private func convertToUnifiedResponse(_ openAIResponse: OpenAIResponse, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        guard let choice = openAIResponse.choices.first else {
            throw ProviderError.invalidRequest("No choices in response")
        }
        
        let message = ChatMessage(
            role: MessageRole(rawValue: choice.message.role) ?? .assistant,
            content: choice.message.content ?? ""
        )
        
        let finishReason = FinishReason(rawValue: choice.finishReason ?? "stop") ?? .stop
        
        let usage = openAIResponse.usage.map { openAIUsage in
            TokenUsage(
                promptTokens: openAIUsage.promptTokens,
                completionTokens: openAIUsage.completionTokens,
                totalTokens: openAIUsage.totalTokens,
                estimatedCost: estimateCost(for: originalRequest)
            )
        }
        
        return UnifiedResponse(
            id: openAIResponse.id,
            message: message,
            finishReason: finishReason,
            usage: usage,
            model: openAIResponse.model,
            provider: providerType,
            functionCall: choice.message.functionCall.map { convertFromOpenAIFunctionCall($0) }
        )
    }
    
    private func transformStreamingChunk(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        let decoder = JSONDecoder()
        let chunk = try decoder.decode(OpenAIStreamingChunk.self, from: data)
        
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
    
    private func convertFromOpenAIFunctionCall(_ functionCall: OpenAIFunctionCall) -> FunctionCall {
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

// MARK: - OpenAI API Models

private struct OpenAIRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let temperature: Double?
    let maxTokens: Int?
    let stream: Bool?
    let functions: [OpenAIFunction]?
    let functionCall: OpenAIFunctionCall?
    
    private enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, functions
        case maxTokens = "max_tokens"
        case functionCall = "function_call"
    }
}

private struct OpenAIMessage: Codable {
    let role: String
    let content: String?
    let functionCall: OpenAIFunctionCall?
    
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

private struct OpenAIFunction: Codable {
    let name: String
    let description: String
    let parameters: FunctionParameters
}

private struct OpenAIFunctionCall: Codable {
    let name: String
    let arguments: String
}

private struct OpenAIResponse: Codable {
    let id: String
    let model: String
    let choices: [OpenAIChoice]
    let usage: OpenAIUsage?
    let created: Int?
}

private struct OpenAIChoice: Codable {
    let message: OpenAIMessage
    let finishReason: String?
    let index: Int
    
    private enum CodingKeys: String, CodingKey {
        case message, index
        case finishReason = "finish_reason"
    }
}

private struct OpenAIUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    
    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

private struct OpenAIStreamingChunk: Codable {
    let id: String
    let model: String
    let choices: [OpenAIStreamingChoice]
}

private struct OpenAIStreamingChoice: Codable {
    let delta: OpenAIDelta
    let finishReason: String?
    let index: Int
    
    private enum CodingKeys: String, CodingKey {
        case delta, index
        case finishReason = "finish_reason"
    }
}

private struct OpenAIDelta: Codable {
    let content: String?
    let role: String?
}

// MARK: - Provider Implementations
// Complete implementations for the final 5 providers

// MARK: - Portkey Provider
/// Portkey AI gateway implementation with multi-provider support
public class PortkeyProvider: BaseLLMProvider {
    
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(providerType: .portkey, apiKey: apiKey, configuration: configuration)
    }
    
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        try validateConfiguration()
        try validateRequest(request)
        
        let httpClient = HTTPClient()
        let urlRequest = try createPortkeyRequest(from: request)
        
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
        let urlRequest = try createPortkeyRequest(from: request, streaming: true)
        
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
        let portkeyRequest = try createPortkeyRequestBody(from: request)
        
        do {
            let encoder = JSONEncoder()
            return try encoder.encode(portkeyRequest)
        } catch {
            throw ProviderError.encodingError(error)
        }
    }
    
    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        do {
            let decoder = JSONDecoder()
            let portkeyResponse = try decoder.decode(PortkeyResponse.self, from: data)
            return try convertToUnifiedResponse(portkeyResponse, originalRequest: originalRequest)
        } catch {
            throw ProviderError.decodingError(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func createPortkeyRequest(from request: UnifiedRequest, streaming: Bool = false) throws -> URLRequest {
        let endpoint = "/chat/completions"
        var urlRequest = try createBaseRequest(endpoint: endpoint)
        
        // Add Portkey-specific headers
        if let metadata = request.metadata?["portkey_config"] {
            urlRequest.setValue("application/json", forHTTPHeaderField: "x-portkey-config")
        }
        
        let requestBody = try createPortkeyRequestBody(from: request, streaming: streaming)
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)
        
        return urlRequest
    }
    
    private func createPortkeyRequestBody(from request: UnifiedRequest, streaming: Bool = false) throws -> PortkeyRequest {
        let messages = request.messages.map { message in
            PortkeyMessage(
                role: message.role.rawValue,
                content: message.content
            )
        }
        
        var allMessages = messages
        if let systemPrompt = request.systemPrompt {
            let systemMessage = PortkeyMessage(role: "system", content: systemPrompt)
            allMessages.insert(systemMessage, at: 0)
        }
        
        return PortkeyRequest(
            model: request.model ?? defaultModel,
            messages: allMessages,
            temperature: request.temperature,
            maxTokens: request.maxTokens,
            stream: streaming
        )
    }
    
    private func convertToUnifiedResponse(_ portkeyResponse: PortkeyResponse, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        guard let choice = portkeyResponse.choices.first else {
            throw ProviderError.invalidRequest("No choices in response")
        }
        
        let message = ChatMessage(
            role: MessageRole(rawValue: choice.message.role) ?? .assistant,
            content: choice.message.content ?? ""
        )
        
        let finishReason = FinishReason(rawValue: choice.finishReason ?? "stop") ?? .stop
        
        let usage = portkeyResponse.usage.map { portkeyUsage in
            TokenUsage(
                promptTokens: portkeyUsage.promptTokens,
                completionTokens: portkeyUsage.completionTokens,
                totalTokens: portkeyUsage.totalTokens,
                estimatedCost: estimateCost(for: originalRequest)
            )
        }
        
        return UnifiedResponse(
            id: portkeyResponse.id,
            message: message,
            finishReason: finishReason,
            usage: usage,
            model: portkeyResponse.model,
            provider: providerType
        )
    }
    
    private func transformStreamingChunk(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        let decoder = JSONDecoder()
        let chunk = try decoder.decode(PortkeyStreamingChunk.self, from: data)
        
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

// MARK: - Abacus AI Provider
/// Abacus.AI predictive modeling platform provider
public class AbacusAIProvider: BaseLLMProvider {
    
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(providerType: .abacusAI, apiKey: apiKey, configuration: configuration)
    }
    
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        try validateConfiguration()
        try validateRequest(request)
        
        let httpClient = HTTPClient()
        let urlRequest = try createAbacusRequest(from: request)
        
        do {
            let responseData = try await httpClient.performRequest(urlRequest)
            return try transformResponse(responseData, originalRequest: request)
        } catch {
            throw mapError(error)
        }
    }
    
    public override func sendStreamingRequest(_ request: UnifiedRequest) async throws -> AsyncThrowingStream<UnifiedResponse, Error> {
        // AbacusAI doesn't support streaming, so we'll simulate it with a single response
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
        let abacusRequest = try createAbacusRequestBody(from: request)
        
        do {
            let encoder = JSONEncoder()
            return try encoder.encode(abacusRequest)
        } catch {
            throw ProviderError.encodingError(error)
        }
    }
    
    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        do {
            let decoder = JSONDecoder()
            let abacusResponse = try decoder.decode(AbacusResponse.self, from: data)
            return try convertToUnifiedResponse(abacusResponse, originalRequest: originalRequest)
        } catch {
            throw ProviderError.decodingError(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func createAbacusRequest(from request: UnifiedRequest) throws -> URLRequest {
        let endpoint = "/chat/completions"
        var urlRequest = try createBaseRequest(endpoint: endpoint)
        
        let requestBody = try createAbacusRequestBody(from: request)
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)
        
        return urlRequest
    }
    
    private func createAbacusRequestBody(from request: UnifiedRequest) throws -> AbacusRequest {
        let messages = request.messages.map { message in
            AbacusMessage(
                role: message.role.rawValue,
                content: message.content
            )
        }
        
        var allMessages = messages
        if let systemPrompt = request.systemPrompt {
            let systemMessage = AbacusMessage(role: "system", content: systemPrompt)
            allMessages.insert(systemMessage, at: 0)
        }
        
        return AbacusRequest(
            model: request.model ?? defaultModel,
            messages: allMessages,
            temperature: request.temperature,
            maxTokens: request.maxTokens
        )
    }
    
    private func convertToUnifiedResponse(_ abacusResponse: AbacusResponse, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        let message = ChatMessage(
            role: .assistant,
            content: abacusResponse.response ?? ""
        )
        
        let usage = TokenUsage(
            promptTokens: abacusResponse.usage?.promptTokens ?? 0,
            completionTokens: abacusResponse.usage?.completionTokens ?? 0,
            estimatedCost: estimateCost(for: originalRequest)
        )
        
        return UnifiedResponse(
            id: abacusResponse.id ?? UUID().uuidString,
            message: message,
            finishReason: .stop,
            usage: usage,
            model: abacusResponse.model,
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

// MARK: - Novita Provider
/// Novita AI cloud GPU inference platform provider
public class NovitaProvider: BaseLLMProvider {
    
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(providerType: .novita, apiKey: apiKey, configuration: configuration)
    }
    
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        try validateConfiguration()
        try validateRequest(request)
        
        let httpClient = HTTPClient()
        let urlRequest = try createNovitaRequest(from: request)
        
        do {
            let responseData = try await httpClient.performRequest(urlRequest)
            return try transformResponse(responseData, originalRequest: request)
        } catch {
            throw mapError(error)
        }
    }
    
    public override func sendStreamingRequest(_ request: UnifiedRequest) async throws -> AsyncThrowingStream<UnifiedResponse, Error> {
        // Novita doesn't support streaming, so we'll simulate it with a single response
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
        let novitaRequest = try createNovitaRequestBody(from: request)
        
        do {
            let encoder = JSONEncoder()
            return try encoder.encode(novitaRequest)
        } catch {
            throw ProviderError.encodingError(error)
        }
    }
    
    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        do {
            let decoder = JSONDecoder()
            let novitaResponse = try decoder.decode(NovitaResponse.self, from: data)
            return try convertToUnifiedResponse(novitaResponse, originalRequest: originalRequest)
        } catch {
            throw ProviderError.decodingError(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func createNovitaRequest(from request: UnifiedRequest) throws -> URLRequest {
        let endpoint = "/openai/chat/completions"
        var urlRequest = try createBaseRequest(endpoint: endpoint)
        
        let requestBody = try createNovitaRequestBody(from: request)
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)
        
        return urlRequest
    }
    
    private func createNovitaRequestBody(from request: UnifiedRequest) throws -> NovitaRequest {
        let messages = request.messages.map { message in
            NovitaMessage(
                role: message.role.rawValue,
                content: message.content
            )
        }
        
        var allMessages = messages
        if let systemPrompt = request.systemPrompt {
            let systemMessage = NovitaMessage(role: "system", content: systemPrompt)
            allMessages.insert(systemMessage, at: 0)
        }
        
        return NovitaRequest(
            model: request.model ?? defaultModel,
            messages: allMessages,
            temperature: request.temperature,
            maxTokens: request.maxTokens
        )
    }
    
    private func convertToUnifiedResponse(_ novitaResponse: NovitaResponse, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        guard let choice = novitaResponse.choices.first else {
            throw ProviderError.invalidRequest("No choices in response")
        }
        
        let message = ChatMessage(
            role: MessageRole(rawValue: choice.message.role) ?? .assistant,
            content: choice.message.content ?? ""
        )
        
        let finishReason = FinishReason(rawValue: choice.finishReason ?? "stop") ?? .stop
        
        let usage = novitaResponse.usage.map { novitaUsage in
            TokenUsage(
                promptTokens: novitaUsage.promptTokens,
                completionTokens: novitaUsage.completionTokens,
                totalTokens: novitaUsage.totalTokens,
                estimatedCost: estimateCost(for: originalRequest)
            )
        }
        
        return UnifiedResponse(
            id: novitaResponse.id,
            message: message,
            finishReason: finishReason,
            usage: usage,
            model: novitaResponse.model,
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

// MARK: - Hugging Face Provider
/// Hugging Face Inference API provider
public class HuggingFaceProvider: BaseLLMProvider {
    
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(providerType: .huggingFace, apiKey: apiKey, configuration: configuration)
    }
    
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        try validateConfiguration()
        try validateRequest(request)
        
        let httpClient = HTTPClient()
        let urlRequest = try createHuggingFaceRequest(from: request)
        
        do {
            let responseData = try await httpClient.performRequest(urlRequest)
            return try transformResponse(responseData, originalRequest: request)
        } catch {
            throw mapError(error)
        }
    }
    
    public override func sendStreamingRequest(_ request: UnifiedRequest) async throws -> AsyncThrowingStream<UnifiedResponse, Error> {
        // HuggingFace Inference API doesn't support streaming in the same way
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
        let hfRequest = try createHuggingFaceRequestBody(from: request)
        
        do {
            let encoder = JSONEncoder()
            return try encoder.encode(hfRequest)
        } catch {
            throw ProviderError.encodingError(error)
        }
    }
    
    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        do {
            let decoder = JSONDecoder()
            let hfResponse = try decoder.decode(HuggingFaceResponse.self, from: data)
            return try convertToUnifiedResponse(hfResponse, originalRequest: originalRequest)
        } catch {
            throw ProviderError.decodingError(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func createHuggingFaceRequest(from request: UnifiedRequest) throws -> URLRequest {
        // Use the router endpoint for chat completions
        let endpoint = "/v1/chat/completions"
        var baseUrl = "https://router.huggingface.co"
        
        guard let url = URL(string: baseUrl + endpoint) else {
            throw ProviderError.invalidURL(baseUrl + endpoint)
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let apiKey = apiKey {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let requestBody = try createHuggingFaceRequestBody(from: request)
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)
        
        return urlRequest
    }
    
    private func createHuggingFaceRequestBody(from request: UnifiedRequest) throws -> HuggingFaceRequest {
        let messages = request.messages.map { message in
            HuggingFaceMessage(
                role: message.role.rawValue,
                content: message.content
            )
        }
        
        var allMessages = messages
        if let systemPrompt = request.systemPrompt {
            let systemMessage = HuggingFaceMessage(role: "system", content: systemPrompt)
            allMessages.insert(systemMessage, at: 0)
        }
        
        return HuggingFaceRequest(
            model: request.model ?? defaultModel,
            messages: allMessages,
            temperature: request.temperature,
            maxTokens: request.maxTokens,
            stream: false
        )
    }
    
    private func convertToUnifiedResponse(_ hfResponse: HuggingFaceResponse, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        guard let choice = hfResponse.choices.first else {
            throw ProviderError.invalidRequest("No choices in response")
        }
        
        let message = ChatMessage(
            role: MessageRole(rawValue: choice.message.role) ?? .assistant,
            content: choice.message.content ?? ""
        )
        
        let finishReason = FinishReason(rawValue: choice.finishReason ?? "stop") ?? .stop
        
        let usage = hfResponse.usage.map { hfUsage in
            TokenUsage(
                promptTokens: hfUsage.promptTokens,
                completionTokens: hfUsage.completionTokens,
                totalTokens: hfUsage.totalTokens
            )
        }
        
        return UnifiedResponse(
            id: hfResponse.id,
            message: message,
            finishReason: finishReason,
            usage: usage,
            model: hfResponse.model,
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

// MARK: - Moonshot Provider
/// Moonshot AI (Kimi K2) Chinese language model provider
public class MoonshotProvider: BaseLLMProvider {
    
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(providerType: .moonshot, apiKey: apiKey, configuration: configuration)
    }
    
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        try validateConfiguration()
        try validateRequest(request)
        
        let httpClient = HTTPClient()
        let urlRequest = try createMoonshotRequest(from: request)
        
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
        let urlRequest = try createMoonshotRequest(from: request, streaming: true)
        
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
        let moonshotRequest = try createMoonshotRequestBody(from: request)
        
        do {
            let encoder = JSONEncoder()
            return try encoder.encode(moonshotRequest)
        } catch {
            throw ProviderError.encodingError(error)
        }
    }
    
    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        do {
            let decoder = JSONDecoder()
            let moonshotResponse = try decoder.decode(MoonshotResponse.self, from: data)
            return try convertToUnifiedResponse(moonshotResponse, originalRequest: originalRequest)
        } catch {
            throw ProviderError.decodingError(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func createMoonshotRequest(from request: UnifiedRequest, streaming: Bool = false) throws -> URLRequest {
        let endpoint = "/chat/completions"
        var urlRequest = try createBaseRequest(endpoint: endpoint)
        
        let requestBody = try createMoonshotRequestBody(from: request, streaming: streaming)
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)
        
        return urlRequest
    }
    
    private func createMoonshotRequestBody(from request: UnifiedRequest, streaming: Bool = false) throws -> MoonshotRequest {
        let messages = request.messages.map { message in
            MoonshotMessage(
                role: message.role.rawValue,
                content: message.content
            )
        }
        
        var allMessages = messages
        if let systemPrompt = request.systemPrompt {
            let systemMessage = MoonshotMessage(role: "system", content: systemPrompt)
            allMessages.insert(systemMessage, at: 0)
        }
        
        // Adjust temperature for Moonshot's 0.6 scaling factor
        let adjustedTemperature = request.temperature.map { $0 * 0.6 }
        
        return MoonshotRequest(
            model: request.model ?? defaultModel,
            messages: allMessages,
            temperature: adjustedTemperature,
            maxTokens: request.maxTokens,
            stream: streaming
        )
    }
    
    private func convertToUnifiedResponse(_ moonshotResponse: MoonshotResponse, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        guard let choice = moonshotResponse.choices.first else {
            throw ProviderError.invalidRequest("No choices in response")
        }
        
        let message = ChatMessage(
            role: MessageRole(rawValue: choice.message.role) ?? .assistant,
            content: choice.message.content ?? ""
        )
        
        let finishReason = FinishReason(rawValue: choice.finishReason ?? "stop") ?? .stop
        
        let usage = moonshotResponse.usage.map { moonshotUsage in
            TokenUsage(
                promptTokens: moonshotUsage.promptTokens,
                completionTokens: moonshotUsage.completionTokens,
                totalTokens: moonshotUsage.totalTokens,
                estimatedCost: estimateCost(for: originalRequest)
            )
        }
        
        return UnifiedResponse(
            id: moonshotResponse.id,
            message: message,
            finishReason: finishReason,
            usage: usage,
            model: moonshotResponse.model,
            provider: providerType
        )
    }
    
    private func transformStreamingChunk(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        let decoder = JSONDecoder()
        let chunk = try decoder.decode(MoonshotStreamingChunk.self, from: data)
        
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
// MARK: - API Models for All Providers

// MARK: - Portkey API Models
private struct PortkeyRequest: Codable {
    let model: String
    let messages: [PortkeyMessage]
    let temperature: Double?
    let maxTokens: Int?
    let stream: Bool?
    
    private enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
    }
}

private struct PortkeyMessage: Codable {
    let role: String
    let content: String
}

private struct PortkeyResponse: Codable {
    let id: String
    let model: String
    let choices: [PortkeyChoice]
    let usage: PortkeyUsage?
}

private struct PortkeyChoice: Codable {
    let message: PortkeyMessage
    let finishReason: String?
    let index: Int
    
    private enum CodingKeys: String, CodingKey {
        case message, index
        case finishReason = "finish_reason"
    }
}

private struct PortkeyUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    
    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

private struct PortkeyStreamingChunk: Codable {
    let id: String
    let model: String
    let choices: [PortkeyStreamingChoice]
}

private struct PortkeyStreamingChoice: Codable {
    let delta: PortkeyDelta
    let finishReason: String?
    let index: Int
    
    private enum CodingKeys: String, CodingKey {
        case delta, index
        case finishReason = "finish_reason"
    }
}

private struct PortkeyDelta: Codable {
    let content: String?
    let role: String?
}

// MARK: - Abacus AI API Models
private struct AbacusRequest: Codable {
    let model: String
    let messages: [AbacusMessage]
    let temperature: Double?
    let maxTokens: Int?
    
    private enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

private struct AbacusMessage: Codable {
    let role: String
    let content: String
}

private struct AbacusResponse: Codable {
    let id: String?
    let model: String?
    let response: String?
    let usage: AbacusUsage?
}

private struct AbacusUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    
    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
    }
}

// MARK: - Novita API Models
private struct NovitaRequest: Codable {
    let model: String
    let messages: [NovitaMessage]
    let temperature: Double?
    let maxTokens: Int?
    
    private enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

private struct NovitaMessage: Codable {
    let role: String
    let content: String
}

private struct NovitaResponse: Codable {
    let id: String
    let model: String
    let choices: [NovitaChoice]
    let usage: NovitaUsage?
}

private struct NovitaChoice: Codable {
    let message: NovitaMessage
    let finishReason: String?
    let index: Int
    
    private enum CodingKeys: String, CodingKey {
        case message, index
        case finishReason = "finish_reason"
    }
}

private struct NovitaUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    
    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Hugging Face API Models
private struct HuggingFaceRequest: Codable {
    let model: String
    let messages: [HuggingFaceMessage]
    let temperature: Double?
    let maxTokens: Int?
    let stream: Bool?
    
    private enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
    }
}

private struct HuggingFaceMessage: Codable {
    let role: String
    let content: String
}

private struct HuggingFaceResponse: Codable {
    let id: String
    let model: String
    let choices: [HuggingFaceChoice]
    let usage: HuggingFaceUsage?
}

private struct HuggingFaceChoice: Codable {
    let message: HuggingFaceMessage
    let finishReason: String?
    let index: Int
    
    private enum CodingKeys: String, CodingKey {
        case message, index
        case finishReason = "finish_reason"
    }
}

private struct HuggingFaceUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    
    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Moonshot API Models
private struct MoonshotRequest: Codable {
    let model: String
    let messages: [MoonshotMessage]
    let temperature: Double?
    let maxTokens: Int?
    let stream: Bool?
    
    private enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
    }
}

private struct MoonshotMessage: Codable {
    let role: String
    let content: String
}

private struct MoonshotResponse: Codable {
    let id: String
    let model: String
    let choices: [MoonshotChoice]
    let usage: MoonshotUsage?
}

private struct MoonshotChoice: Codable {
    let message: MoonshotMessage
    let finishReason: String?
    let index: Int
    
    private enum CodingKeys: String, CodingKey {
        case message, index
        case finishReason = "finish_reason"
    }
}

private struct MoonshotUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    
    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

private struct MoonshotStreamingChunk: Codable {
    let id: String
    let model: String
    let choices: [MoonshotStreamingChoice]
}

private struct MoonshotStreamingChoice: Codable {
    let delta: MoonshotDelta
    let finishReason: String?
    let index: Int
    
    private enum CodingKeys: String, CodingKey {
        case delta, index
        case finishReason = "finish_reason"
    }
}

private struct MoonshotDelta: Codable {
    let content: String?
    let role: String?
}
EOF < /dev/null