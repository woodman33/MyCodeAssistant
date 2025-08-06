import Foundation

// MARK: - Conversation Manager
/// Manages conversation storage, retrieval, and synchronization
public class ConversationManager: ConversationManagerProtocol {
    
    // MARK: - Storage
    private let userDefaults: UserDefaults
    private let conversationsKey = "stored_conversations"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // MARK: - Cache
    private var conversationCache: [UUID: Conversation] = [:]
    private let cacheQueue = DispatchQueue(label: "ConversationCache", attributes: .concurrent)
    
    // MARK: - Initialization
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        
        // Configure date handling
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        
        // Load existing conversations into cache
        loadCacheFromStorage()
    }
    
    // MARK: - ConversationManagerProtocol Implementation
    
    public func saveConversation(_ conversation: Conversation) async throws {
        return try await Task {
            try cacheQueue.sync(flags: .barrier) {
                // Update cache
                conversationCache[conversation.id] = conversation
                
                // Persist to storage
                try persistConversations()
            }
        }.value
    }
    
    public func loadConversation(id: UUID) throws -> Conversation? {
        return cacheQueue.sync {
            return conversationCache[id]
        }
    }
    
    public func loadAllConversations() async throws -> [Conversation] {
        return await Task {
            return cacheQueue.sync {
                return Array(conversationCache.values).sorted {
                    $0.updatedAt > $1.updatedAt
                }
            }
        }.value
    }
    
    public func deleteConversation(id: UUID) throws {
        try cacheQueue.sync(flags: .barrier) {
            // Remove from cache
            conversationCache.removeValue(forKey: id)
            
            // Persist changes
            try persistConversations()
        }
    }
    
    public func deleteAllConversations() throws {
        try cacheQueue.sync(flags: .barrier) {
            // Clear cache
            conversationCache.removeAll()
            
            // Clear storage
            userDefaults.removeObject(forKey: conversationsKey)
        }
    }
    
    public func searchConversations(query: String) throws -> [Conversation] {
        let searchQuery = query.lowercased()
        
        return try cacheQueue.sync {
            return conversationCache.values.filter { conversation in
                // Search in title
                if conversation.title.lowercased().contains(searchQuery) {
                    return true
                }
                
                // Search in message content
                return conversation.messages.contains { message in
                    message.content.lowercased().contains(searchQuery)
                }
            }.sorted {
                $0.updatedAt > $1.updatedAt
            }
        }
    }
    
    // MARK: - Additional Methods
    
    /// Creates a new conversation with the given title and initial message
    /// - Parameters:
    ///   - title: The conversation title
    ///   - initialMessage: Optional initial message
    ///   - provider: The provider name
    ///   - model: Optional model name
    /// - Returns: The created conversation
    /// - Throws: StorageError if creation fails
    public func createConversation(
        title: String,
        initialMessage: ChatMessage? = nil,
        provider: String,
        model: String? = nil
    ) async throws -> Conversation {
        let messages = initialMessage.map { [$0] } ?? []
        
        let conversation = Conversation(
            title: title,
            messages: messages,
            provider: provider,
            model: model
        )
        
        try await saveConversation(conversation)
        return conversation
    }
    
    /// Adds a message to an existing conversation
    /// - Parameters:
    ///   - message: The message to add
    ///   - conversationId: The ID of the conversation to update
    /// - Returns: The updated conversation
    /// - Throws: StorageError if the conversation doesn't exist or update fails
    public func addMessage(_ message: ChatMessage, to conversationId: UUID) async throws -> Conversation {
        guard var conversation = try loadConversation(id: conversationId) else {
            throw StorageError.conversationNotFound(conversationId)
        }
        
        let updatedMessages = conversation.messages + [message]
        conversation = conversation.withUpdatedMessages(updatedMessages)
        
        try await saveConversation(conversation)
        return conversation
    }
    
    /// Updates the title of an existing conversation
    /// - Parameters:
    ///   - conversationId: The ID of the conversation to update
    ///   - newTitle: The new title
    /// - Returns: The updated conversation
    /// - Throws: StorageError if the conversation doesn't exist or update fails
    public func updateConversationTitle(_ conversationId: UUID, newTitle: String) async throws -> Conversation {
        guard let conversation = try loadConversation(id: conversationId) else {
            throw StorageError.conversationNotFound(conversationId)
        }
        
        let updatedConversation = Conversation(
            id: conversation.id,
            title: newTitle,
            messages: conversation.messages,
            createdAt: conversation.createdAt,
            updatedAt: Date(),
            provider: conversation.provider,
            model: conversation.model
        )
        
        try await saveConversation(updatedConversation)
        return updatedConversation
    }
    
    /// Gets conversations created within a specific date range
    /// - Parameters:
    ///   - startDate: The start date
    ///   - endDate: The end date
    /// - Returns: Array of conversations within the date range
    /// - Throws: StorageError if loading fails
    public func getConversations(from startDate: Date, to endDate: Date) throws -> [Conversation] {
        return try cacheQueue.sync {
            return conversationCache.values.filter { conversation in
                conversation.createdAt >= startDate && conversation.createdAt <= endDate
            }.sorted {
                $0.updatedAt > $1.updatedAt
            }
        }
    }
    
    /// Gets conversations by provider
    /// - Parameter provider: The provider name to filter by
    /// - Returns: Array of conversations for the specified provider
    /// - Throws: StorageError if loading fails
    public func getConversations(for provider: String) throws -> [Conversation] {
        return try cacheQueue.sync {
            return conversationCache.values.filter { conversation in
                conversation.provider == provider
            }.sorted {
                $0.updatedAt > $1.updatedAt
            }
        }
    }
    
    /// Gets conversation statistics
    /// - Returns: ConversationStatistics with various metrics
    public func getStatistics() -> ConversationStatistics {
        return cacheQueue.sync {
            let conversations = Array(conversationCache.values)
            
            let totalConversations = conversations.count
            let totalMessages = conversations.reduce(0) { $0 + $1.messages.count }
            
            let providerCounts = Dictionary(grouping: conversations, by: { $0.provider })
                .mapValues { $0.count }
            
            let recentConversations = conversations.filter {
                $0.updatedAt > Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            }.count
            
            return ConversationStatistics(
                totalConversations: totalConversations,
                totalMessages: totalMessages,
                providerCounts: providerCounts,
                recentConversations: recentConversations,
                lastUpdated: Date()
            )
        }
    }
    
    /// Exports conversations to JSON data
    /// - Parameter conversationIds: Optional array of specific conversation IDs to export. If nil, exports all.
    /// - Returns: JSON data containing the conversations
    /// - Throws: StorageError if export fails
    public func exportConversations(_ conversationIds: [UUID]? = nil) async throws -> Data {
        let conversations: [Conversation]
        
        if let ids = conversationIds {
            conversations = try ids.compactMap { try loadConversation(id: $0) }
        } else {
            conversations = try await loadAllConversations()
        }
        
        do {
            return try encoder.encode(conversations)
        } catch {
            throw StorageError.exportFailed(error)
        }
    }
    
    /// Imports conversations from JSON data
    /// - Parameter data: JSON data containing conversations
    /// - Returns: Number of conversations imported
    /// - Throws: StorageError if import fails
    public func importConversations(from data: Data) throws -> Int {
        do {
            let conversations = try decoder.decode([Conversation].self, from: data)
            
            try cacheQueue.sync(flags: .barrier) {
                for conversation in conversations {
                    conversationCache[conversation.id] = conversation
                }
                
                try persistConversations()
            }
            
            return conversations.count
        } catch {
            throw StorageError.importFailed(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func loadCacheFromStorage() {
        guard let data = userDefaults.data(forKey: conversationsKey) else { return }
        
        do {
            let conversations = try decoder.decode([Conversation].self, from: data)
            conversationCache = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
        } catch {
            // Handle corrupted data by starting fresh
            userDefaults.removeObject(forKey: conversationsKey)
        }
    }
    
    private func persistConversations() throws {
        let conversations = Array(conversationCache.values)
        
        do {
            let data = try encoder.encode(conversations)
            userDefaults.set(data, forKey: conversationsKey)
        } catch {
            throw StorageError.saveFailed(error)
        }
    }
}

// MARK: - Conversation Statistics
public struct ConversationStatistics {
    public let totalConversations: Int
    public let totalMessages: Int
    public let providerCounts: [String: Int]
    public let recentConversations: Int
    public let lastUpdated: Date
    
    public init(
        totalConversations: Int,
        totalMessages: Int,
        providerCounts: [String: Int],
        recentConversations: Int,
        lastUpdated: Date
    ) {
        self.totalConversations = totalConversations
        self.totalMessages = totalMessages
        self.providerCounts = providerCounts
        self.recentConversations = recentConversations
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Storage Error
public enum StorageError: LocalizedError {
    case conversationNotFound(UUID)
    case saveFailed(Error)
    case loadFailed(Error)
    case deleteFailed(Error)
    case exportFailed(Error)
    case importFailed(Error)
    case corruptedData
    case insufficientStorage
    
    public var errorDescription: String? {
        switch self {
        case .conversationNotFound(let id):
            return "Conversation with ID \(id) not found"
        case .saveFailed(let error):
            return "Failed to save conversation: \(error.localizedDescription)"
        case .loadFailed(let error):
            return "Failed to load conversation: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete conversation: \(error.localizedDescription)"
        case .exportFailed(let error):
            return "Failed to export conversations: \(error.localizedDescription)"
        case .importFailed(let error):
            return "Failed to import conversations: \(error.localizedDescription)"
        case .corruptedData:
            return "Conversation data is corrupted"
        case .insufficientStorage:
            return "Insufficient storage space"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .conversationNotFound:
            return "The requested conversation does not exist"
        case .saveFailed:
            return "Unable to save the conversation data"
        case .loadFailed:
            return "Unable to load the conversation data"
        case .deleteFailed:
            return "Unable to delete the conversation"
        case .exportFailed:
            return "Unable to export conversation data"
        case .importFailed:
            return "Unable to import conversation data"
        case .corruptedData:
            return "The stored conversation data is in an invalid format"
        case .insufficientStorage:
            return "Not enough storage space available"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .conversationNotFound:
            return "Please check that the conversation ID is correct"
        case .saveFailed:
            return "Please try again or free up storage space"
        case .loadFailed:
            return "Please try restarting the app or check available storage"
        case .deleteFailed:
            return "Please try again or restart the app"
        case .exportFailed:
            return "Please check available storage space and try again"
        case .importFailed:
            return "Please check that the import data is valid and try again"
        case .corruptedData:
            return "Please try resetting the app data or contact support"
        case .insufficientStorage:
            return "Please free up storage space and try again"
        }
    }
}