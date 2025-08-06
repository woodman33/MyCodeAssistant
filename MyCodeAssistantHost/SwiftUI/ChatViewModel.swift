import Foundation
import SwiftUI

// MARK: - Chat View Model
@MainActor
class ChatViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var messages: [ChatMessage] = []
    @Published var currentMessage: String = ""
    @Published var isLoading: Bool = false
    @Published var isStreaming: Bool = false
    @Published var currentProvider: LLMProvider? = .openAI
    @Published var error: String?
    @Published var streamingContent: String = ""
    
    // MARK: - Private Properties
    private let sharedServices: SharedServices
    private let conversationManager: ConversationManagerProtocol
    private let providerFactory: ProviderFactory
    private let apiKeyManager: APIKeyManagerProtocol
    
    // Current conversation
    @Published var currentConversation: Conversation?
    
    // MARK: - Initialization
    init() {
        self.sharedServices = SharedServices.shared
        self.conversationManager = sharedServices.conversationManager
        self.providerFactory = sharedServices.providerFactory
        self.apiKeyManager = sharedServices.apiKeyManager
        
        // Load previous conversation if available
        loadLastConversation()
    }
    
    // MARK: - Public Methods
    
    /// Send a message using the current provider
    func sendMessage() {
        guard !currentMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let provider = currentProvider else {
            setError("No provider selected")
            return
        }
        
        let userMessage = ChatMessage(
            role: .user,
            content: currentMessage,
            timestamp: Date()
        )
        
        messages.append(userMessage)
        let messageToSend = currentMessage
        currentMessage = ""
        
        // Create or update conversation
        if currentConversation == nil {
            currentConversation = Conversation(
                title: String(messageToSend.prefix(50)),
                messages: [userMessage],
                provider: provider.rawValue
            )
        } else {
            currentConversation?.messages.append(userMessage)
            currentConversation?.updatedAt = Date()
        }
        
        Task {
            await processMessage(messageToSend, with: provider)
        }
    }
    
    /// Switch to a different provider
    func switchProvider(_ provider: LLMProvider) {
        currentProvider = provider
        clearError()
    }
    
    /// Clear the current conversation
    func clearConversation() {
        messages.removeAll()
        currentConversation = nil
        clearError()
    }
    
    /// Validate if a provider is properly configured
    func isProviderConfigured(_ provider: LLMProvider) -> Bool {
        do {
            let apiKey = try apiKeyManager.getAPIKey(for: provider)
            return !(apiKey?.isEmpty ?? true)
        } catch {
            return false
        }
    }
    
    // MARK: - Private Methods
    
    private func processMessage(_ message: String, with provider: LLMProvider) async {
        do {
            isLoading = true
            clearError()
            
            // Get provider instance
            let llmProvider = try sharedServices.getProvider(provider)
            
            // Create request
            let request = UnifiedRequest(
                messages: messages,
                model: currentProvider?.primaryModel ?? "gpt-3.5-turbo",
                temperature: 0.7,
                maxTokens: 2000,
                stream: currentProvider?.supportsStreaming ?? false
            )
            
            if request.stream {
                await handleStreamingResponse(provider: llmProvider, request: request)
            } else {
                await handleRegularResponse(provider: llmProvider, request: request)
            }
            
        } catch {
            setError("Failed to send message: \(error.localizedDescription)")
        }
        
        isLoading = false
        
        // Save conversation asynchronously
        if let conversation = currentConversation {
            Task.detached { [weak self] in
                do {
                    try await self?.conversationManager.saveConversation(conversation)
                } catch {
                    await MainActor.run {
                        self?.setError("Failed to save conversation: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func loadLastConversation() {
        Task.detached { [weak self] in
            do {
                let conversations = try await self?.conversationManager.loadAllConversations() ?? []
                let lastConversation = conversations.max(by: { $0.updatedAt < $1.updatedAt })
                
                await MainActor.run { [weak self] in
                    if let conversation = lastConversation {
                        self?.currentConversation = conversation
                        self?.messages = conversation.messages
                        
                        // Set provider from conversation
                        if let providerRawValue = conversation.provider.isEmpty ? nil : conversation.provider,
                           let provider = LLMProvider(rawValue: providerRawValue) {
                            self?.currentProvider = provider
                        }
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.setError("Failed to load conversation: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func handleStreamingResponse(provider: any LLMProviderProtocol, request: UnifiedRequest) async {
        isStreaming = true
        streamingContent = ""
        
        // Add placeholder message for streaming
        let assistantMessage = ChatMessage(
            role: .assistant,
            content: "",
            timestamp: Date()
        )
        messages.append(assistantMessage)
        
        do {
            let stream = try await provider.sendStreamingRequest(request)
            
            for try await chunk in stream {
                // For streaming, each chunk should contain partial content
                streamingContent += chunk.message.content
                
                // Update the last message
                if let lastIndex = messages.indices.last {
                    messages[lastIndex] = ChatMessage(
                        role: .assistant,
                        content: streamingContent,
                        timestamp: assistantMessage.timestamp
                    )
                }
            }
            
            // Update conversation
            currentConversation?.messages = messages
            currentConversation?.updatedAt = Date()
            
        } catch {
            setError("Streaming failed: \(error.localizedDescription)")
            // Remove placeholder message on error
            if messages.last?.role == .assistant && messages.last?.content.isEmpty == true {
                messages.removeLast()
            }
        }
        
        isStreaming = false
        streamingContent = ""
    }
    
    private func handleRegularResponse(provider: any LLMProviderProtocol, request: UnifiedRequest) async {
        do {
            let response = try await provider.sendRequest(request)
            
            let assistantMessage = ChatMessage(
                role: .assistant,
                content: response.message.content,
                timestamp: Date()
            )
            messages.append(assistantMessage)
            
            // Update conversation
            currentConversation?.messages = messages
            currentConversation?.updatedAt = Date()
            
        } catch {
            setError("Request failed: \(error.localizedDescription)")
        }
    }
    
    private func setError(_ message: String) {
        error = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.clearError()
        }
    }
    
    private func clearError() {
        error = nil
    }
}