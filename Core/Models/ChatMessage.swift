import Foundation

// MARK: - Chat Message
/// Represents a message in a chat conversation
public struct ChatMessage: Codable, Equatable, Identifiable {
    public let id: UUID
    public let role: MessageRole
    public let content: String
    public let timestamp: Date
    public let metadata: [String: String]?
    
    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

// MARK: - Message Role
/// Represents the role of a message sender
public enum MessageRole: String, Codable, CaseIterable {
    case system = "system"
    case user = "user"
    case assistant = "assistant"
    case function = "function"
    
    public var displayName: String {
        switch self {
        case .system:
            return "System"
        case .user:
            return "User"
        case .assistant:
            return "Assistant"
        case .function:
            return "Function"
        }
    }
}

// MARK: - Conversation
/// Represents a conversation containing multiple messages
public struct Conversation: Codable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let messages: [ChatMessage]
    public let createdAt: Date
    public let updatedAt: Date
    public let provider: String
    public let model: String?
    
    public init(
        id: UUID = UUID(),
        title: String,
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        provider: String,
        model: String? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.provider = provider
        self.model = model
    }
    
    /// Creates a new conversation with an updated message list
    public func withUpdatedMessages(_ messages: [ChatMessage]) -> Conversation {
        return Conversation(
            id: self.id,
            title: self.title,
            messages: messages,
            createdAt: self.createdAt,
            updatedAt: Date(),
            provider: self.provider,
            model: self.model
        )
    }
}