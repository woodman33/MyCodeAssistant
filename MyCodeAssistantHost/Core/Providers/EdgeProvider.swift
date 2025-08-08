// EdgeProvider: routes chat to the Cloudflare Worker via EdgeBackendClient
import Foundation

public final class EdgeProvider: BaseLLMProvider {
    private let client = EdgeBackendClient()

    // MARK: - Initialization
    public init(apiKey: String?, configuration: ProviderConfiguration) {
        super.init(
            providerType: .edge,
            apiKey: apiKey,
            configuration: configuration
        )
    }

    // MARK: - LLMProviderProtocol Implementation
    // For Edge, we use a very simple mapping: send the latest user message to the backend
    public override func sendRequest(_ request: UnifiedRequest) async throws -> UnifiedResponse {
        try validateConfiguration()
        try validateRequest(request)

        let messageToSend: String
        if let lastUser = request.messages.last(where: { $0.role == .user }) {
            messageToSend = lastUser.content
        } else if let last = request.messages.last {
            messageToSend = last.content
        } else {
            throw ProviderError.invalidRequest("No messages to send")
        }

        do {
            let reply = try await client.chat(messageToSend)
            let chatMessage = ChatMessage(role: .assistant, content: reply)

            return UnifiedResponse(
                id: UUID().uuidString,
                message: chatMessage,
                finishReason: .stop,
                usage: nil,
                model: request.model ?? defaultModel,
                provider: providerType
            )
        } catch {
            throw ProviderError.networkError(error)
        }
    }

    public override func sendStreamingRequest(_ request: UnifiedRequest) async throws -> AsyncThrowingStream<UnifiedResponse, Error> {
        // Edge backend currently returns a single reply; emulate streaming by yielding once
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let full = try await self.sendRequest(request)
                    continuation.yield(full)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public override func transformRequest(_ request: UnifiedRequest) throws -> Data {
        // Minimal body expected by Edge worker: { "message": "..." }
        struct EdgeBody: Codable { let message: String }

        let messageToSend: String
        if let lastUser = request.messages.last(where: { $0.role == .user }) {
            messageToSend = lastUser.content
        } else if let last = request.messages.last {
            messageToSend = last.content
        } else {
            throw ProviderError.invalidRequest("No messages to send")
        }

        do {
            return try JSONEncoder().encode(EdgeBody(message: messageToSend))
        } catch {
            throw ProviderError.encodingError(error)
        }
    }

    public override func transformResponse(_ data: Data, originalRequest: UnifiedRequest) throws -> UnifiedResponse {
        struct EdgeReply: Codable { let reply: String }
        do {
            let decoded = try JSONDecoder().decode(EdgeReply.self, from: data)
            let chatMessage = ChatMessage(role: .assistant, content: decoded.reply)
            return UnifiedResponse(
                id: UUID().uuidString,
                message: chatMessage,
                finishReason: .stop,
                model: originalRequest.model ?? defaultModel,
                provider: providerType
            )
        } catch {
            throw ProviderError.decodingError(error)
        }
    }
}
