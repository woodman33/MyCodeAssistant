import SwiftUI
import Foundation
import Combine

// MARK: - Chat View Model
@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var messages: [ChatMessage] = []
    @Published var currentProvider: LLMProvider?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var streamingContent = ""
    @Published var isStreaming = false
    
    // MARK: - Private Properties
    private let apiKeyManager: APIKeyManagerProtocol
    private let providerFactory: ProviderFactory
    private let conversationManager: ConversationManagerProtocol
    private var currentConversation: Conversation?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        self.apiKeyManager = APIKeyManager()
        self.providerFactory = ProviderFactory.shared
        self.conversationManager = ConversationManager()
        
        setupDefaultProvider()
    }
    
    func initialize(with settings: AppSettings) {
        currentProvider = settings.defaultProvider
        loadLastConversation()
    }
    
    // MARK: - Provider Management
    private func setupDefaultProvider() {
        // Find the first available provider with an API key
        let availableProviders = providerFactory.getAvailableProviders()
        currentProvider = availableProviders.first ?? .openAI
    }
    
    func switchProvider(to provider: LLMProvider) {
        guard providerFactory.canCreateProvider(provider) else {
            errorMessage = "Provider \(provider.displayName) is not available. Please check your API key configuration."
            return
        }
        
        currentProvider = provider
        errorMessage = nil
    }
    
    // MARK: - Message Management
    func sendMessage(_ content: String) async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let provider = currentProvider else {
            errorMessage = "No provider selected"
            return
        }
        
        // Add user message
        let userMessage = ChatMessage(
            role: .user,
            content: content.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        withAnimation(.easeOut(duration: 0.3)) {
            messages.append(userMessage)
        }
        
        // Create conversation if none exists
        if currentConversation == nil {
            createNewConversation(with: provider)
        }
        
        // Update conversation with new message
        updateConversation(with: userMessage)
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Get LLM provider instance
            let llmProvider = try providerFactory.createProvider(provider)
            
            // Create unified request
            let request = createUnifiedRequest(from: messages)
            
            // Check if provider supports streaming
            if llmProvider.supportsStreaming {
                await handleStreamingResponse(provider: llmProvider, request: request)
            } else {
                await handleNonStreamingResponse(provider: llmProvider, request: request)
            }
            
        } catch {
            await handleError(error)
        }
        
        isLoading = false
    }
    
    // MARK: - Streaming Support
    private func handleStreamingResponse(provider: LLMProviderProtocol, request: UnifiedRequest) async {
        do {
            isStreaming = true
            streamingContent = ""
            
            // Create placeholder assistant message
            let assistantMessage = ChatMessage(
                role: .assistant,
                content: ""
            )
            
            withAnimation(.easeOut(duration: 0.3)) {
                messages.append(assistantMessage)
            }
            
            // Handle streaming response
            let stream = try await provider.sendStreamingRequest(request)
            
            for try await response in stream {
                if !response.message.content.isEmpty {
                    streamingContent += response.message.content
                    
                    // Update the last message with accumulated content
                    if let lastIndex = messages.lastIndex(where: { $0.role == .assistant }) {
                        let updatedMessage = ChatMessage(
                            id: messages[lastIndex].id,
                            role: .assistant,
                            content: streamingContent,
                            timestamp: messages[lastIndex].timestamp
                        )
                        messages[lastIndex] = updatedMessage
                    }
                }
            }
            
            // Final update
            if let lastIndex = messages.lastIndex(where: { $0.role == .assistant }) {
                let finalMessage = ChatMessage(
                    id: messages[lastIndex].id,
                    role: .assistant,
                    content: streamingContent,
                    timestamp: messages[lastIndex].timestamp
                )
                messages[lastIndex] = finalMessage
                updateConversation(with: finalMessage)
            }
            
        } catch {
            await handleError(error)
        }
        
        isStreaming = false
        streamingContent = ""
    }
    
    private func handleNonStreamingResponse(provider: LLMProviderProtocol, request: UnifiedRequest) async {
        do {
            let response = try await provider.sendRequest(request)
            
            let assistantMessage = ChatMessage(
                role: .assistant,
                content: response.message.content
            )
            
            withAnimation(.easeOut(duration: 0.3)) {
                messages.append(assistantMessage)
            }
            
            updateConversation(with: assistantMessage)
            
        } catch {
            await handleError(error)
        }
    }
    
    // MARK: - Request Creation
    private func createUnifiedRequest(from messages: [ChatMessage]) -> UnifiedRequest {
        return UnifiedRequest(
            messages: messages,
            model: currentProvider?.primaryModel ?? "gpt-3.5-turbo",
            maxTokens: 2000,
            temperature: 0.7,
            stream: currentProvider?.supportsStreaming ?? false
        )
    }
    
    // MARK: - Error Handling
    private func handleError(_ error: Error) async {
        withAnimation(.easeOut(duration: 0.3)) {
            errorMessage = error.localizedDescription
        }
        
        // Remove any incomplete assistant message
        if let lastMessage = messages.last, lastMessage.role == .assistant && lastMessage.content.isEmpty {
            messages.removeLast()
        }
    }
    
    // MARK: - Conversation Management
    private func createNewConversation(with provider: LLMProvider) {
        let title = messages.first?.content.prefix(50).trimmingCharacters(in: .whitespacesAndNewlines) ?? "New Conversation"
        currentConversation = Conversation(
            title: String(title),
            messages: [],
            provider: provider.rawValue,
            model: provider.primaryModel
        )
    }
    
    private func updateConversation(with message: ChatMessage) {
        guard var conversation = currentConversation else { return }
        
        let updatedMessages = conversation.messages + [message]
        currentConversation = conversation.withUpdatedMessages(updatedMessages)
        
        // Save conversation asynchronously
        Task.detached { [weak self, conversation = self?.currentConversation] in
            guard let conversation = conversation else { return }
            do {
                try self?.conversationManager.saveConversation(conversation)
            } catch {
                print("Failed to save conversation: \(error)")
            }
        }
    }
    
    private func loadLastConversation() {
        Task.detached { [weak self] in
            do {
                let conversations = try self?.conversationManager.loadAllConversations() ?? []
                let lastConversation = conversations.max(by: { $0.updatedAt < $1.updatedAt })
                
                await MainActor.run {
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
                print("Failed to load conversations: \(error)")
            }
        }
    }
    
    // MARK: - Conversation Actions
    func clearConversation() {
        withAnimation(.easeOut(duration: 0.3)) {
            messages.removeAll()
        }
        currentConversation = nil
        errorMessage = nil
        streamingContent = ""
    }
    
    func newConversation() {
        clearConversation()
        if let provider = currentProvider {
            createNewConversation(with: provider)
        }
    }
    
    // MARK: - Provider Validation
    func validateCurrentProvider() -> Bool {
        guard let provider = currentProvider else { return false }
        return providerFactory.canCreateProvider(provider)
    }
    
    func getAvailableProviders() -> [LLMProvider] {
        return providerFactory.getAvailableProviders()
    }
}

// MARK: - Configuration Manager Protocol Implementation
protocol ConfigurationManagerProtocol {
    func getConfiguration(for provider: LLMProvider) -> ProviderConfiguration
    func updateConfiguration(for provider: LLMProvider, configuration: ProviderConfiguration)
    func getAllConfigurations() -> [ProviderConfiguration]
}

// MARK: - Configuration Manager
class ConfigurationManager: ConfigurationManagerProtocol {
    private var configurations: [LLMProvider: ProviderConfiguration] = [:]
    
    init() {
        setupDefaultConfigurations()
    }
    
    private func setupDefaultConfigurations() {
        for provider in LLMProvider.allCases {
            configurations[provider] = ProviderConfiguration(
                provider: provider,
                baseURL: provider.baseURL,
                apiKeyRequired: provider.requiresAPIKey,
                supportedModels: provider.defaultModels.map { model in
                    ModelConfiguration(
                        provider: provider,
                        modelName: model,
                        displayName: model,
                        maxTokens: provider.maxTokensLimit,
                        supportsSystemPrompt: provider.supportsSystemPrompt,
                        supportsFunctions: provider.supportsFunctions
                    )
                }
            )
        }
    }
    
    func getConfiguration(for provider: LLMProvider) -> ProviderConfiguration {
        return configurations[provider] ?? ProviderConfiguration(
            provider: provider,
            baseURL: provider.baseURL
        )
    }
    
    func updateConfiguration(for provider: LLMProvider, configuration: ProviderConfiguration) {
        configurations[provider] = configuration
    }
    
    func getAllConfigurations() -> [ProviderConfiguration] {
        return Array(configurations.values)
    }
}