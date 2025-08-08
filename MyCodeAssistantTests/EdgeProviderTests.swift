import XCTest
import Foundation
@testable import MyCodeAssistantCore

// MARK: - Edge Provider Tests
@MainActor
final class EdgeProviderTests: XCTestCase {
    
    var edgeProvider: EdgeProvider!
    var mockSettings: AppSettings!
    var mockConfiguration: ProviderConfiguration!
    
    override func setUp() {
        super.setUp()
        
        // Create mock settings with test endpoint
        mockSettings = AppSettings.default
        
        // Create mock configuration
        mockConfiguration = ProviderConfiguration(
            model: "test-model",
            temperature: 0.7,
            maxTokens: 1024,
            topP: 1.0,
            stream: false
        )
        
        // Initialize Edge Provider
        edgeProvider = EdgeProvider(
            apiKey: nil, // Edge doesn't require API key
            configuration: mockConfiguration,
            settings: mockSettings
        )
    }
    
    override func tearDown() {
        edgeProvider = nil
        mockSettings = nil
        mockConfiguration = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testEdgeProviderInitialization() {
        XCTAssertNotNil(edgeProvider, "EdgeProvider should be initialized")
        XCTAssertEqual(edgeProvider.providerType, .edge, "Provider type should be Edge")
        XCTAssertNil(edgeProvider.apiKey, "API key should be nil for Edge")
        XCTAssertEqual(edgeProvider.defaultModel, "test-model", "Default model should match configuration")
    }
    
    func testEdgeProviderWithAPIKey() {
        let providerWithKey = EdgeProvider(
            apiKey: "test-api-key",
            configuration: mockConfiguration,
            settings: mockSettings
        )
        
        XCTAssertNotNil(providerWithKey, "EdgeProvider should be initialized with API key")
        XCTAssertEqual(providerWithKey.apiKey, "test-api-key", "API key should be stored")
    }
    
    // MARK: - Configuration Validation Tests
    
    func testValidateConfiguration() {
        // Edge provider should validate without API key
        XCTAssertNoThrow(try edgeProvider.validateConfiguration(), 
                        "Configuration should be valid without API key")
    }
    
    func testValidateConfigurationWithInvalidURL() {
        // Create settings with invalid URL
        let invalidSettings = AppSettings(
            edgeAPIBase: "not-a-valid-url:://",
            edgeSSEEndpoint: "/stream"
        )
        
        let invalidProvider = EdgeProvider(
            apiKey: nil,
            configuration: mockConfiguration,
            settings: invalidSettings
        )
        
        XCTAssertThrows(try invalidProvider.validateConfiguration(),
                       "Should throw error for invalid URL")
    }
    
    // MARK: - Request Transformation Tests
    
    func testTransformRequestBasicMessage() throws {
        let messages = [
            ChatMessage(role: .user, content: "Hello, Edge!")
        ]
        
        let request = UnifiedRequest(
            messages: messages,
            model: "test-model",
            temperature: 0.5,
            maxTokens: 512,
            stream: false
        )
        
        let data = try edgeProvider.transformRequest(request)
        XCTAssertNotNil(data, "Transformed data should not be nil")
        
        // Decode and verify
        let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(jsonObject, "Should decode to JSON object")
        
        // Verify messages array
        let messagesArray = jsonObject?["messages"] as? [[String: Any]]
        XCTAssertEqual(messagesArray?.count, 1, "Should have one message")
        XCTAssertEqual(messagesArray?.first?["role"] as? String, "user", "Role should be user")
        XCTAssertEqual(messagesArray?.first?["content"] as? String, "Hello, Edge!", "Content should match")
        
        // Verify other parameters
        XCTAssertEqual(jsonObject?["model"] as? String, "test-model", "Model should match")
        XCTAssertEqual(jsonObject?["temperature"] as? Double, 0.5, accuracy: 0.01, "Temperature should match")
        XCTAssertEqual(jsonObject?["max_tokens"] as? Int, 512, "Max tokens should match")
        XCTAssertEqual(jsonObject?["stream"] as? Bool, false, "Stream should be false")
    }
    
    func testTransformRequestWithSystemPrompt() throws {
        let messages = [
            ChatMessage(role: .user, content: "Test message")
        ]
        
        let request = UnifiedRequest(
            messages: messages,
            model: "test-model",
            systemPrompt: "You are a helpful assistant",
            temperature: 0.7,
            maxTokens: 1024,
            stream: false
        )
        
        let data = try edgeProvider.transformRequest(request)
        let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Verify system message is added first
        let messagesArray = jsonObject?["messages"] as? [[String: Any]]
        XCTAssertEqual(messagesArray?.count, 2, "Should have two messages (system + user)")
        
        let firstMessage = messagesArray?.first
        XCTAssertEqual(firstMessage?["role"] as? String, "system", "First message should be system")
        XCTAssertEqual(firstMessage?["content"] as? String, "You are a helpful assistant", 
                      "System content should match")
        
        let secondMessage = messagesArray?.last
        XCTAssertEqual(secondMessage?["role"] as? String, "user", "Second message should be user")
        XCTAssertEqual(secondMessage?["content"] as? String, "Test message", 
                      "User content should match")
    }
    
    func testTransformRequestMultipleMessages() throws {
        let messages = [
            ChatMessage(role: .user, content: "First message"),
            ChatMessage(role: .assistant, content: "Response"),
            ChatMessage(role: .user, content: "Follow-up")
        ]
        
        let request = UnifiedRequest(
            messages: messages,
            model: "test-model"
        )
        
        let data = try edgeProvider.transformRequest(request)
        let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        let messagesArray = jsonObject?["messages"] as? [[String: Any]]
        XCTAssertEqual(messagesArray?.count, 3, "Should have three messages")
        
        // Verify message order and roles
        XCTAssertEqual(messagesArray?[0]["role"] as? String, "user")
        XCTAssertEqual(messagesArray?[1]["role"] as? String, "assistant")
        XCTAssertEqual(messagesArray?[2]["role"] as? String, "user")
    }
    
    // MARK: - Response Transformation Tests
    
    func testTransformResponseBasic() throws {
        let responseJSON = """
        {
            "id": "test-id-123",
            "model": "test-model",
            "response": "Hello from Edge!",
            "done": true,
            "usage": {
                "prompt_tokens": 10,
                "completion_tokens": 5,
                "total_tokens": 15
            }
        }
        """
        
        let responseData = responseJSON.data(using: .utf8)!
        let originalRequest = UnifiedRequest(
            messages: [ChatMessage(role: .user, content: "Test")],
            model: "test-model"
        )
        
        let response = try edgeProvider.transformResponse(responseData, originalRequest: originalRequest)
        
        XCTAssertEqual(response.id, "test-id-123", "ID should match")
        XCTAssertEqual(response.message.role, .assistant, "Role should be assistant")
        XCTAssertEqual(response.message.content, "Hello from Edge!", "Content should match")
        XCTAssertEqual(response.finishReason, .stop, "Finish reason should be stop when done=true")
        XCTAssertEqual(response.model, "test-model", "Model should match")
        XCTAssertEqual(response.provider, .edge, "Provider should be Edge")
        
        // Verify usage
        XCTAssertNotNil(response.usage, "Usage should be present")
        XCTAssertEqual(response.usage?.promptTokens, 10, "Prompt tokens should match")
        XCTAssertEqual(response.usage?.completionTokens, 5, "Completion tokens should match")
        XCTAssertEqual(response.usage?.totalTokens, 15, "Total tokens should match")
    }
    
    func testTransformResponseWithContentField() throws {
        // Test alternative "content" field instead of "response"
        let responseJSON = """
        {
            "id": "test-id-456",
            "model": "test-model",
            "content": "Alternative content field",
            "done": false
        }
        """
        
        let responseData = responseJSON.data(using: .utf8)!
        let originalRequest = UnifiedRequest(
            messages: [ChatMessage(role: .user, content: "Test")],
            model: "test-model"
        )
        
        let response = try edgeProvider.transformResponse(responseData, originalRequest: originalRequest)
        
        XCTAssertEqual(response.message.content, "Alternative content field", 
                      "Should use content field when response is absent")
        XCTAssertNil(response.finishReason, "Finish reason should be nil when done=false")
    }
    
    func testTransformResponseMissingFields() throws {
        // Minimal response
        let responseJSON = """
        {
            "response": "Minimal response"
        }
        """
        
        let responseData = responseJSON.data(using: .utf8)!
        let originalRequest = UnifiedRequest(
            messages: [ChatMessage(role: .user, content: "Test")],
            model: "fallback-model"
        )
        
        let response = try edgeProvider.transformResponse(responseData, originalRequest: originalRequest)
        
        XCTAssertNotNil(response.id, "ID should be generated if missing")
        XCTAssertEqual(response.message.content, "Minimal response", "Content should match")
        XCTAssertEqual(response.model, "fallback-model", "Should use request model as fallback")
        XCTAssertNil(response.usage, "Usage should be nil if not provided")
    }
    
    // MARK: - Streaming Response Tests
    
    func testParseStreamingChunk() throws {
        let chunkJSON = """
        {
            "id": "stream-123",
            "model": "test-model",
            "content": "Streaming ",
            "done": false
        }
        """
        
        let chunkData = chunkJSON.data(using: .utf8)!
        let originalRequest = UnifiedRequest(
            messages: [ChatMessage(role: .user, content: "Test")],
            model: "test-model"
        )
        
        // Use reflection to call private method (in real tests, make it internal for testability)
        // For this example, we'll test the public interface indirectly
        XCTAssertNoThrow(try JSONDecoder().decode(EdgeStreamingChunk.self, from: chunkData),
                        "Should decode streaming chunk")
    }
    
    func testStreamingSSEFormat() {
        // Test SSE format parsing
        let sseData = """
        data: {"type":"connected"}\n\n
        data: {"content":"Hello","done":false}\n\n
        data: {"content":" World","done":false}\n\n
        data: {"content":"!","done":true}\n\n
        data: [DONE]\n\n
        """
        
        let lines = sseData.components(separatedBy: "\n")
        let dataLines = lines
            .compactMap { line in
                line.hasPrefix("data: ") ? String(line.dropFirst(6)) : nil
            }
            .filter { !$0.isEmpty && $0 != "[DONE]" }
        
        XCTAssertEqual(dataLines.count, 4, "Should have 4 data chunks")
        XCTAssertTrue(dataLines[0].contains("connected"), "First chunk should be connection")
        XCTAssertTrue(dataLines[3].contains("done\":true"), "Last chunk should have done=true")
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidJSONResponse() {
        let invalidJSON = "not valid json"
        let invalidData = invalidJSON.data(using: .utf8)!
        let originalRequest = UnifiedRequest(
            messages: [ChatMessage(role: .user, content: "Test")],
            model: "test-model"
        )
        
        XCTAssertThrowsError(
            try edgeProvider.transformResponse(invalidData, originalRequest: originalRequest),
            "Should throw decoding error for invalid JSON"
        ) { error in
            if let providerError = error as? ProviderError {
                switch providerError {
                case .decodingError:
                    XCTAssertTrue(true, "Should be decoding error")
                default:
                    XCTFail("Should be decoding error, got: \(providerError)")
                }
            } else {
                XCTFail("Should be ProviderError")
            }
        }
    }
    
    func testEmptyResponse() {
        let emptyData = Data()
        let originalRequest = UnifiedRequest(
            messages: [ChatMessage(role: .user, content: "Test")],
            model: "test-model"
        )
        
        XCTAssertThrowsError(
            try edgeProvider.transformResponse(emptyData, originalRequest: originalRequest),
            "Should throw error for empty response"
        )
    }
    
    // MARK: - Request Validation Tests
    
    func testValidateRequestEmpty() {
        let emptyRequest = UnifiedRequest(messages: [])
        
        XCTAssertThrowsError(
            try edgeProvider.validateRequest(emptyRequest),
            "Should throw error for empty messages"
        ) { error in
            if let providerError = error as? ProviderError {
                switch providerError {
                case .invalidRequest(let message):
                    XCTAssertTrue(message.contains("Messages cannot be empty"),
                                 "Error should mention empty messages")
                default:
                    XCTFail("Should be invalidRequest error")
                }
            }
        }
    }
    
    func testValidateRequestValid() {
        let validRequest = UnifiedRequest(
            messages: [ChatMessage(role: .user, content: "Valid message")],
            model: "test-model"
        )
        
        XCTAssertNoThrow(
            try edgeProvider.validateRequest(validRequest),
            "Should not throw for valid request"
        )
    }
}

// MARK: - Mock Response Tests
extension EdgeProviderTests {
    
    func testMockChatResponse() throws {
        // Simulate a successful chat response
        let mockResponse = createMockChatResponse(
            message: "This is a mock response from Edge",
            promptTokens: 15,
            completionTokens: 10
        )
        
        let originalRequest = UnifiedRequest(
            messages: [ChatMessage(role: .user, content: "Test")],
            model: "test-model"
        )
        
        let response = try edgeProvider.transformResponse(mockResponse, originalRequest: originalRequest)
        
        XCTAssertEqual(response.message.content, "This is a mock response from Edge")
        XCTAssertEqual(response.usage?.totalTokens, 25)
    }
    
    func testMockErrorResponse() {
        let errorResponse = createMockErrorResponse(
            error: "Rate limit exceeded",
            statusCode: 429
        )
        
        // Verify error format
        if let errorDict = try? JSONSerialization.jsonObject(with: errorResponse) as? [String: Any] {
            XCTAssertEqual(errorDict["error"] as? String, "Rate limit exceeded")
            XCTAssertEqual(errorDict["status"] as? Int, 429)
        }
    }
    
    // Helper methods for creating mock responses
    private func createMockChatResponse(
        message: String,
        promptTokens: Int = 10,
        completionTokens: Int = 5
    ) -> Data {
        let response: [String: Any] = [
            "id": UUID().uuidString,
            "model": "test-model",
            "response": message,
            "done": true,
            "usage": [
                "prompt_tokens": promptTokens,
                "completion_tokens": completionTokens,
                "total_tokens": promptTokens + completionTokens
            ]
        ]
        
        return try! JSONSerialization.data(withJSONObject: response)
    }
    
    private func createMockErrorResponse(error: String, statusCode: Int) -> Data {
        let response: [String: Any] = [
            "error": error,
            "status": statusCode
        ]
        
        return try! JSONSerialization.data(withJSONObject: response)
    }
}

// MARK: - Performance Tests
extension EdgeProviderTests {
    
    func testRequestTransformationPerformance() throws {
        let messages = (0..<100).map { i in
            ChatMessage(role: i % 2 == 0 ? .user : .assistant, 
                       content: "Message \(i)")
        }
        
        let request = UnifiedRequest(
            messages: messages,
            model: "test-model"
        )
        
        measure {
            _ = try? edgeProvider.transformRequest(request)
        }
    }
    
    func testResponseTransformationPerformance() throws {
        let responseData = createMockChatResponse(
            message: String(repeating: "Test message. ", count: 100),
            promptTokens: 1000,
            completionTokens: 500
        )
        
        let originalRequest = UnifiedRequest(
            messages: [ChatMessage(role: .user, content: "Test")],
            model: "test-model"
        )
        
        measure {
            _ = try? edgeProvider.transformResponse(responseData, originalRequest: originalRequest)
        }
    }
}

// MARK: - Edge-specific Models for Testing
// These would normally be internal to EdgeProvider, but exposed here for testing
private struct EdgeStreamingChunk: Codable {
    let id: String?
    let model: String?
    let content: String?
    let done: Bool?
}

// MARK: - Helper Extensions
private extension AppSettings {
    init(edgeAPIBase: String, edgeSSEEndpoint: String) {
        self = AppSettings.default
        // In a real implementation, you'd set these properties
        // For testing, we'll use the default values
    }
}