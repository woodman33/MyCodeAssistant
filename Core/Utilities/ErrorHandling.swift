import Foundation

// MARK: - Error Handler
/// Centralized error handling and logging system
public class ErrorHandler {
    
    // MARK: - Singleton
    public static let shared = ErrorHandler()
    
    private let logger: LoggerProtocol
    private var errorObservers: [WeakErrorObserver] = []
    
    private init() {
        self.logger = Logger()
    }
    
    // MARK: - Error Handling
    
    /// Handles an error with optional context
    /// - Parameters:
    ///   - error: The error to handle
    ///   - context: Additional context about where the error occurred
    ///   - severity: The severity level of the error
    public func handle(_ error: Error, context: String? = nil, severity: ErrorSeverity = .medium) {
        let handledError = HandledError(
            originalError: error,
            context: context,
            severity: severity,
            timestamp: Date()
        )
        
        // Log the error
        logError(handledError)
        
        // Notify observers
        notifyObservers(handledError)
        
        // Take automatic actions based on severity
        handleBySeverity(handledError)
    }
    
    /// Creates a user-friendly error message from any error
    /// - Parameter error: The error to create a message for
    /// - Returns: User-friendly error message
    public func userFriendlyMessage(for error: Error) -> String {
        switch error {
        case let providerError as ProviderError:
            return providerError.localizedDescription
        case let keychainError as KeychainError:
            return keychainError.localizedDescription
        case let serviceError as ServiceError:
            return serviceError.localizedDescription
        case let urlError as URLError:
            return urlErrorMessage(for: urlError)
        default:
            return "An unexpected error occurred. Please try again."
        }
    }
    
    /// Creates a recovery suggestion for an error
    /// - Parameter error: The error to create a suggestion for
    /// - Returns: Recovery suggestion or nil if none available
    public func recoverySuggestion(for error: Error) -> String? {
        switch error {
        case let providerError as ProviderError:
            return providerError.recoverySuggestion
        case let keychainError as KeychainError:
            return keychainError.recoverySuggestion
        case let urlError as URLError:
            return urlErrorRecoverySuggestion(for: urlError)
        default:
            return "Please try again or restart the app if the problem persists."
        }
    }
    
    // MARK: - Error Observers
    
    /// Adds an observer for error events
    /// - Parameter observer: The observer to add
    public func addObserver(_ observer: ErrorObserverProtocol) {
        errorObservers.append(WeakErrorObserver(observer))
        cleanupObservers()
    }
    
    /// Removes an observer
    /// - Parameter observer: The observer to remove
    public func removeObserver(_ observer: ErrorObserverProtocol) {
        errorObservers.removeAll { $0.observer === observer }
    }
    
    // MARK: - Private Methods
    
    private func logError(_ error: HandledError) {
        let message = """
        Error: \(error.originalError.localizedDescription)
        Context: \(error.context ?? "None")
        Severity: \(error.severity)
        Timestamp: \(error.timestamp)
        """
        
        switch error.severity {
        case .low:
            logger.debug(message)
        case .medium:
            logger.info(message)
        case .high:
            logger.warning(message)
        case .critical:
            logger.error(message)
        }
    }
    
    private func notifyObservers(_ error: HandledError) {
        for observer in errorObservers {
            observer.observer?.errorOccurred(error)
        }
        cleanupObservers()
    }
    
    private func handleBySeverity(_ error: HandledError) {
        switch error.severity {
        case .low:
            // Just log, no other action needed
            break
        case .medium:
            // Log and potentially notify user
            break
        case .high:
            // Log, notify user, and potentially take corrective action
            break
        case .critical:
            // Log, notify user, take corrective action, and potentially crash gracefully
            break
        }
    }
    
    private func cleanupObservers() {
        errorObservers.removeAll { $0.observer == nil }
    }
    
    private func urlErrorMessage(for urlError: URLError) -> String {
        switch urlError.code {
        case .notConnectedToInternet:
            return "No internet connection available"
        case .timedOut:
            return "The request timed out"
        case .cannotFindHost:
            return "Cannot connect to the server"
        case .cannotConnectToHost:
            return "Cannot establish connection to the server"
        case .networkConnectionLost:
            return "Network connection was lost"
        case .badURL:
            return "Invalid server address"
        case .cancelled:
            return "Request was cancelled"
        default:
            return "Network error occurred"
        }
    }
    
    private func urlErrorRecoverySuggestion(for urlError: URLError) -> String? {
        switch urlError.code {
        case .notConnectedToInternet:
            return "Please check your internet connection and try again"
        case .timedOut:
            return "Please try again or check your internet connection"
        case .cannotFindHost, .cannotConnectToHost:
            return "Please check your internet connection or try again later"
        case .networkConnectionLost:
            return "Please check your internet connection and try again"
        case .cancelled:
            return "Please try the request again"
        default:
            return "Please check your internet connection and try again"
        }
    }
}

// MARK: - Handled Error
public struct HandledError {
    public let originalError: Error
    public let context: String?
    public let severity: ErrorSeverity
    public let timestamp: Date
    
    public init(originalError: Error, context: String?, severity: ErrorSeverity, timestamp: Date) {
        self.originalError = originalError
        self.context = context
        self.severity = severity
        self.timestamp = timestamp
    }
}

// MARK: - Error Severity
public enum ErrorSeverity: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
    
    public var displayName: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        case .critical:
            return "Critical"
        }
    }
}

// MARK: - Error Observer Protocol
public protocol ErrorObserverProtocol: AnyObject {
    func errorOccurred(_ error: HandledError)
}

// MARK: - Weak Error Observer
private class WeakErrorObserver {
    weak var observer: ErrorObserverProtocol?
    
    init(_ observer: ErrorObserverProtocol) {
        self.observer = observer
    }
}

// MARK: - Logger Protocol
public protocol LoggerProtocol {
    func debug(_ message: String)
    func info(_ message: String)
    func warning(_ message: String)
    func error(_ message: String)
}

// MARK: - Logger Implementation
public class Logger: LoggerProtocol {
    
    private let dateFormatter: DateFormatter
    private let enableLogging: Bool
    
    public init(enableLogging: Bool = true) {
        self.enableLogging = enableLogging
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }
    
    public func debug(_ message: String) {
        log(message, level: "DEBUG")
    }
    
    public func info(_ message: String) {
        log(message, level: "INFO")
    }
    
    public func warning(_ message: String) {
        log(message, level: "WARNING")
    }
    
    public func error(_ message: String) {
        log(message, level: "ERROR")
    }
    
    private func log(_ message: String, level: String) {
        guard enableLogging else { return }
        
        let timestamp = dateFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] [\(level)] \(message)"
        
        print(logMessage)
        
        // In a real implementation, you might also write to a file or send to a logging service
    }
}

// MARK: - Retry Handler
/// Handles automatic retry logic for failed operations
public class RetryHandler {
    
    public static let shared = RetryHandler()
    
    private init() {}
    
    /// Executes an operation with retry logic
    /// - Parameters:
    ///   - operation: The operation to retry
    ///   - maxAttempts: Maximum number of retry attempts
    ///   - delay: Initial delay between retries
    ///   - backoffMultiplier: Multiplier for exponential backoff
    ///   - shouldRetry: Closure to determine if an error should trigger a retry
    /// - Returns: The result of the operation
    /// - Throws: The last error if all retries fail
    public func executeWithRetry<T>(
        _ operation: @escaping () async throws -> T,
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        backoffMultiplier: Double = 2.0,
        shouldRetry: @escaping (Error) -> Bool = { _ in true }
    ) async throws -> T {
        var lastError: Error?
        var delay = initialDelay
        
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                // Don't retry on the last attempt
                if attempt == maxAttempts {
                    break
                }
                
                // Check if we should retry this error
                if !shouldRetry(error) {
                    throw error
                }
                
                // Wait before retry
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay *= backoffMultiplier
            }
        }
        
        throw lastError ?? NSError(
            domain: "RetryHandler",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "All retry attempts failed"]
        )
    }
    
    /// Determines if an error should trigger a retry
    /// - Parameter error: The error to check
    /// - Returns: True if the error is retryable
    public func isRetryableError(_ error: Error) -> Bool {
        switch error {
        case let urlError as URLError:
            return isRetryableURLError(urlError)
        case let providerError as ProviderError:
            return isRetryableProviderError(providerError)
        default:
            return false
        }
    }
    
    private func isRetryableURLError(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet:
            return true
        case .cannotFindHost, .cannotConnectToHost:
            return true
        default:
            return false
        }
    }
    
    private func isRetryableProviderError(_ error: ProviderError) -> Bool {
        switch error {
        case .networkError, .timeoutError, .serverError:
            return true
        case .rateLimitExceeded:
            return true // With appropriate delay
        default:
            return false
        }
    }
}

// MARK: - Validation Utilities
/// Utilities for validating input and configuration
public struct ValidationUtilities {
    
    /// Validates an email address format
    /// - Parameter email: The email to validate
    /// - Returns: True if email format is valid
    public static func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    /// Validates a URL format
    /// - Parameter urlString: The URL string to validate
    /// - Returns: True if URL format is valid
    public static func isValidURL(_ urlString: String) -> Bool {
        return URL(string: urlString) != nil
    }
    
    /// Validates that a string is not empty or whitespace only
    /// - Parameter string: The string to validate
    /// - Returns: True if string has content
    public static func hasContent(_ string: String?) -> Bool {
        return !(string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
    
    /// Validates JSON format
    /// - Parameter jsonString: The JSON string to validate
    /// - Returns: True if JSON is valid
    public static func isValidJSON(_ jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8) else { return false }
        
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [])
            return true
        } catch {
            return false
        }
    }
    
    /// Validates that a number is within a specified range
    /// - Parameters:
    ///   - value: The value to validate
    ///   - min: Minimum allowed value
    ///   - max: Maximum allowed value
    /// - Returns: True if value is within range
    public static func isInRange<T: Comparable>(_ value: T, min: T, max: T) -> Bool {
        return value >= min && value <= max
    }
}