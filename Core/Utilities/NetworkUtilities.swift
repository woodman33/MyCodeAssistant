import Foundation

// MARK: - HTTP Client
/// HTTP client with advanced features for API communication
public class HTTPClient {
    
    // MARK: - Configuration
    public struct Configuration {
        public let timeout: TimeInterval
        public let retryAttempts: Int
        public let retryDelay: TimeInterval
        public let enableLogging: Bool
        
        public init(
            timeout: TimeInterval = 30,
            retryAttempts: Int = 3,
            retryDelay: TimeInterval = 1.0,
            enableLogging: Bool = false
        ) {
            self.timeout = timeout
            self.retryAttempts = retryAttempts
            self.retryDelay = retryDelay
            self.enableLogging = enableLogging
        }
        
        public static let `default` = Configuration()
    }
    
    // MARK: - Properties
    private let urlSession: URLSession
    private let configuration: Configuration
    private let logger: LoggerProtocol
    private let retryHandler: RetryHandler
    
    // MARK: - Initialization
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.logger = Logger(enableLogging: configuration.enableLogging)
        self.retryHandler = RetryHandler.shared
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout
        sessionConfig.timeoutIntervalForResource = configuration.timeout * 2
        
        self.urlSession = URLSession(configuration: sessionConfig)
    }
    
    // MARK: - Request Methods
    
    /// Performs a JSON request with automatic retry and error handling
    /// - Parameters:
    ///   - request: The URL request to perform
    ///   - responseType: The expected response type
    /// - Returns: Decoded response object
    /// - Throws: HTTPError for various failure conditions
    public func performJSONRequest<T: Codable>(
        _ request: URLRequest,
        responseType: T.Type
    ) async throws -> T {
        let data = try await performRequest(request)
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(responseType, from: data)
        } catch {
            logger.error("Failed to decode response: \(error)")
            throw HTTPError.decodingError(error)
        }
    }
    
    /// Performs a raw data request with automatic retry and error handling
    /// - Parameter request: The URL request to perform
    /// - Returns: Response data
    /// - Throws: HTTPError for various failure conditions
    public func performRequest(_ request: URLRequest) async throws -> Data {
        logger.debug("Performing request: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "unknown")")
        
        return try await retryHandler.executeWithRetry(
            {
                try await self.performSingleRequest(request)
            },
            maxAttempts: configuration.retryAttempts,
            initialDelay: configuration.retryDelay,
            shouldRetry: { error in
                self.retryHandler.isRetryableError(error)
            }
        )
    }
    
    /// Performs a streaming request
    /// - Parameter request: The URL request to perform
    /// - Returns: Async stream of data chunks
    /// - Throws: HTTPError for various failure conditions
    public func performStreamingRequest(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error> {
        logger.debug("Performing streaming request: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "unknown")")
        
        return AsyncThrowingStream { continuation in
            let task = urlSession.dataTask(with: request) { data, response, error in
                if let error = error {
                    self.logger.error("Streaming request failed: \(error)")
                    continuation.finish(throwing: HTTPError.networkError(error))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.finish(throwing: HTTPError.invalidResponse)
                    return
                }
                
                if httpResponse.statusCode >= 400 {
                    let errorData = data ?? Data()
                    continuation.finish(throwing: HTTPError.httpStatusError(httpResponse.statusCode, errorData))
                    return
                }
                
                if let data = data, !data.isEmpty {
                    continuation.yield(data)
                }
                
                continuation.finish()
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
            
            task.resume()
        }
    }
    
    // MARK: - Private Methods
    
    private func performSingleRequest(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HTTPError.invalidResponse
            }
            
            logger.debug("Response status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode >= 400 {
                logger.error("HTTP error \(httpResponse.statusCode): \(String(data: data, encoding: .utf8) ?? "No error details")")
                throw HTTPError.httpStatusError(httpResponse.statusCode, data)
            }
            
            return data
        } catch {
            logger.error("Request failed: \(error)")
            throw HTTPError.networkError(error)
        }
    }
}

// MARK: - HTTP Error
public enum HTTPError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpStatusError(Int, Data)
    case networkError(Error)
    case decodingError(Error)
    case encodingError(Error)
    case timeout
    case cancelled
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpStatusError(let status, _):
            return "HTTP error with status \(status)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .timeout:
            return "Request timed out"
        case .cancelled:
            return "Request was cancelled"
        }
    }
    
    public var statusCode: Int? {
        switch self {
        case .httpStatusError(let status, _):
            return status
        default:
            return nil
        }
    }
    
    public var responseData: Data? {
        switch self {
        case .httpStatusError(_, let data):
            return data
        default:
            return nil
        }
    }
}

// MARK: - Request Builder
/// Utility for building HTTP requests
public struct RequestBuilder {
    
    private var urlComponents: URLComponents
    private var headers: [String: String] = [:]
    private var httpMethod: String = "GET"
    private var body: Data?
    
    public init(baseURL: String, path: String = "") {
        var components = URLComponents(string: baseURL)!
        if !path.isEmpty {
            components.path = components.path + path
        }
        self.urlComponents = components
    }
    
    // MARK: - Builder Methods
    
    public func method(_ method: String) -> RequestBuilder {
        var builder = self
        builder.httpMethod = method
        return builder
    }
    
    public func header(_ name: String, value: String) -> RequestBuilder {
        var builder = self
        builder.headers[name] = value
        return builder
    }
    
    public func headers(_ headers: [String: String]) -> RequestBuilder {
        var builder = self
        for (key, value) in headers {
            builder.headers[key] = value
        }
        return builder
    }
    
    public func queryParameter(_ name: String, value: String) -> RequestBuilder {
        var builder = self
        if builder.urlComponents.queryItems == nil {
            builder.urlComponents.queryItems = []
        }
        builder.urlComponents.queryItems?.append(URLQueryItem(name: name, value: value))
        return builder
    }
    
    public func queryParameters(_ parameters: [String: String]) -> RequestBuilder {
        var builder = self
        for (key, value) in parameters {
            builder = builder.queryParameter(key, value: value)
        }
        return builder
    }
    
    public func jsonBody<T: Codable>(_ object: T) throws -> RequestBuilder {
        var builder = self
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        builder.body = try encoder.encode(object)
        builder.headers["Content-Type"] = "application/json"
        return builder
    }
    
    public func body(_ data: Data, contentType: String) -> RequestBuilder {
        var builder = self
        builder.body = data
        builder.headers["Content-Type"] = contentType
        return builder
    }
    
    // MARK: - Build Method
    
    public func build() throws -> URLRequest {
        guard let url = urlComponents.url else {
            throw HTTPError.invalidURL(urlComponents.string ?? "Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.httpBody = body
        
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        
        return request
    }
}

// MARK: - Response Parser
/// Utility for parsing API responses
public struct ResponseParser {
    
    /// Parses a JSON response with error handling
    /// - Parameters:
    ///   - data: The response data
    ///   - type: The expected response type
    /// - Returns: Parsed object
    /// - Throws: HTTPError if parsing fails
    public static func parseJSON<T: Codable>(_ data: Data, as type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw HTTPError.decodingError(error)
        }
    }
    
    /// Parses an error response to extract error details
    /// - Parameter data: The error response data
    /// - Returns: Error message or generic message if parsing fails
    public static func parseErrorMessage(_ data: Data) -> String {
        // Try to parse as JSON error response
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Common error message fields
            let possibleKeys = ["error", "message", "detail", "error_description", "error_message"]
            
            for key in possibleKeys {
                if let errorMessage = json[key] as? String {
                    return errorMessage
                }
            }
            
            // Try nested error objects
            if let errorObj = json["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                return message
            }
        }
        
        // Fall back to raw string if available
        if let errorString = String(data: data, encoding: .utf8), !errorString.isEmpty {
            return errorString
        }
        
        return "Unknown error occurred"
    }
}

// MARK: - Connection Monitor
/// Monitors network connectivity status
public class ConnectionMonitor: ObservableObject {
    
    @Published public private(set) var isConnected: Bool = true
    @Published public private(set) var connectionType: ConnectionType = .unknown
    
    private var monitor: Any? // NWPathMonitor on iOS 12+
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    public init() {
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    private func startMonitoring() {
        // Simple connectivity check using reachability
        // In a real implementation, you would use NWPathMonitor on iOS 12+
        checkConnectivity()
        
        // Schedule periodic checks
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            self.checkConnectivity()
        }
    }
    
    private func stopMonitoring() {
        // Stop monitoring implementation
    }
    
    private func checkConnectivity() {
        Task {
            let networkManager = NetworkManager()
            let status = await networkManager.checkConnectivity()
            
            DispatchQueue.main.async {
                self.isConnected = status.isConnected
                self.connectionType = status.connectionType
            }
        }
    }
}

// MARK: - Rate Limiter Implementation
/// Implements rate limiting for API requests
public class RateLimiter: RateLimiterProtocol {
    
    private struct RateLimitState {
        var requestCount: Int = 0
        var tokenCount: Int = 0
        var windowStart: Date = Date()
        var lastRequest: Date = Date()
    }
    
    private var providerStates: [LLMProvider: RateLimitState] = [:]
    private let queue = DispatchQueue(label: "RateLimiter", attributes: .concurrent)
    
    public func isRequestAllowed(for provider: LLMProvider) -> Bool {
        return queue.sync {
            let configuration = getProviderConfiguration(provider)
            guard let rateLimit = configuration.rateLimit else { return true }
            
            let now = Date()
            var state = providerStates[provider] ?? RateLimitState()
            
            // Reset window if necessary
            let windowDuration: TimeInterval = 60 // 1 minute
            if now.timeIntervalSince(state.windowStart) >= windowDuration {
                state = RateLimitState()
                state.windowStart = now
            }
            
            // Check rate limits
            let allowed = state.requestCount < rateLimit.requestsPerMinute
            
            if allowed {
                state.requestCount += 1
                state.lastRequest = now
                providerStates[provider] = state
            }
            
            return allowed
        }
    }
    
    public func recordRequest(for provider: LLMProvider, tokens: Int?) {
        queue.async(flags: .barrier) {
            var state = self.providerStates[provider] ?? RateLimitState()
            
            if let tokens = tokens {
                state.tokenCount += tokens
            }
            
            self.providerStates[provider] = state
        }
    }
    
    public func timeUntilNextRequest(for provider: LLMProvider) -> TimeInterval? {
        return queue.sync {
            let configuration = getProviderConfiguration(provider)
            guard let rateLimit = configuration.rateLimit else { return nil }
            
            let state = providerStates[provider] ?? RateLimitState()
            
            if state.requestCount < rateLimit.requestsPerMinute {
                return nil // Request is allowed immediately
            }
            
            let windowDuration: TimeInterval = 60
            let timeInWindow = Date().timeIntervalSince(state.windowStart)
            return max(0, windowDuration - timeInWindow)
        }
    }
    
    public func resetLimits(for provider: LLMProvider) {
        queue.async(flags: .barrier) {
            self.providerStates[provider] = nil
        }
    }
    
    private func getProviderConfiguration(_ provider: LLMProvider) -> ProviderConfiguration {
        // In a real implementation, this would get the actual configuration
        return ProviderConfiguration(
            provider: provider,
            baseURL: provider.baseURL,
            rateLimit: RateLimit(requestsPerMinute: 60) // Default limit
        )
    }
}