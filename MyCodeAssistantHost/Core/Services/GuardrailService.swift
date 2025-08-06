import Foundation

// MARK: - ParsedPrompt Model
struct ParsedPrompt: Codable {
    let language: String
    let codeOnly: Bool
    let prompt: String
    
    // Supported languages
    static let supportedLanguages = [
        "swift", "python", "javascript", "js", "typescript", "ts",
        "java", "cpp", "c", "csharp", "cs", "go", "rust", "ruby",
        "php", "kotlin", "dart", "sql", "bash", "shell", "json",
        "yaml", "xml", "html", "css", "markdown", "md"
    ]
}

// MARK: - Guardrail Errors
enum GuardrailError: LocalizedError {
    case invalidJSON
    case missingRequiredField(String)
    case unsupportedLanguage(String)
    case contentFiltered(String)
    case emptyPrompt
    
    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Invalid JSON format. Please provide a valid JSON object."
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .unsupportedLanguage(let language):
            return "Unsupported language: '\(language)'. Supported languages: \(ParsedPrompt.supportedLanguages.joined(separator: ", "))"
        case .contentFiltered(let reason):
            return "Content blocked: \(reason)"
        case .emptyPrompt:
            return "Prompt cannot be empty"
        }
    }
}

// MARK: - GuardrailService
class GuardrailService {
    
    // Singleton instance
    static let shared = GuardrailService()
    
    // Disallowed content patterns (maintainable array)
    private let disallowedKeywords = [
        // Violence/harm related
        "kill", "murder", "assault", "violence", "harm", "hurt",
        // Illegal activities
        "hack password", "crack software", "bypass security", "illegal download",
        "piracy", "malware", "virus", "ransomware",
        // Personal information patterns
        "social security", "credit card number", "bank account",
        // Inappropriate content
        "explicit content", "adult content"
    ]
    
    // Additional safety patterns
    private let sensitivePatterns = [
        // API keys and secrets
        "api[_\\s-]?key", "secret[_\\s-]?key", "private[_\\s-]?key",
        // Personal identifiers
        "\\b\\d{3}-\\d{2}-\\d{4}\\b", // SSN pattern
        "\\b\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}\\b" // Credit card pattern
    ]
    
    private init() {}
    
    // MARK: - Input Validation
    func validateInput(json: String) throws -> ParsedPrompt {
        // Check for empty input
        guard !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GuardrailError.emptyPrompt
        }
        
        // Try to parse as JSON
        guard let data = json.data(using: .utf8) else {
            throw GuardrailError.invalidJSON
        }
        
        do {
            let decoder = JSONDecoder()
            let parsed = try decoder.decode(ParsedPrompt.self, from: data)
            
            // Validate language is supported
            let normalizedLanguage = parsed.language.lowercased()
            guard ParsedPrompt.supportedLanguages.contains(normalizedLanguage) else {
                throw GuardrailError.unsupportedLanguage(parsed.language)
            }
            
            // Validate prompt is not empty
            guard !parsed.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GuardrailError.emptyPrompt
            }
            
            // Return parsed prompt with normalized language
            return ParsedPrompt(
                language: normalizedLanguage,
                codeOnly: parsed.codeOnly,
                prompt: parsed.prompt
            )
            
        } catch let decodingError as DecodingError {
            // Handle specific decoding errors
            switch decodingError {
            case .keyNotFound(let key, _):
                throw GuardrailError.missingRequiredField(key.stringValue)
            case .typeMismatch(_, _):
                throw GuardrailError.invalidJSON
            case .valueNotFound(_, let context):
                throw GuardrailError.missingRequiredField(context.codingPath.last?.stringValue ?? "unknown")
            default:
                throw GuardrailError.invalidJSON
            }
        } catch let error as GuardrailError {
            throw error
        } catch {
            throw GuardrailError.invalidJSON
        }
    }
    
    // MARK: - Content Filtering
    func filterContent(_ text: String) throws {
        let lowercasedText = text.lowercased()
        
        // Check for disallowed keywords
        for keyword in disallowedKeywords {
            if lowercasedText.contains(keyword.lowercased()) {
                throw GuardrailError.contentFiltered(
                    "Your request contains content that violates our usage guidelines. Please rephrase your request."
                )
            }
        }
        
        // Check for sensitive patterns using regex
        for pattern in sensitivePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: text.utf16.count)
                if regex.firstMatch(in: text, options: [], range: range) != nil {
                    throw GuardrailError.contentFiltered(
                        "Your request appears to contain sensitive information. Please remove any personal or confidential data."
                    )
                }
            }
        }
    }
    
    // MARK: - Output Formatting
    func formatOutput(text: String, codeOnly: Bool, language: String) -> String {
        guard codeOnly else {
            // Return plain text if not code-only mode
            return text
        }
        
        // Check if the text already has code blocks
        let hasCodeBlock = text.contains("```")
        
        if hasCodeBlock {
            // Already formatted with code blocks, return as-is
            return text
        } else {
            // Wrap in code block with specified language
            return "```\(language)\n\(text)\n```"
        }
    }
    
    // MARK: - Helper Methods
    
    /// Parse JSON directly from user input (for simpler cases)
    func parseSimplePrompt(_ input: String) -> ParsedPrompt? {
        // Check if input looks like JSON
        if input.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            // Try to parse as JSON
            if let parsed = try? validateInput(json: input) {
                return parsed
            }
        }
        
        // Otherwise, create a simple prompt with defaults
        return ParsedPrompt(
            language: "swift",
            codeOnly: false,
            prompt: input
        )
    }
    
    /// Sanitize output to remove any potentially harmful content
    func sanitizeOutput(_ text: String) -> String {
        var sanitized = text
        
        // Remove any detected API keys or secrets from output
        for pattern in sensitivePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: sanitized.utf16.count)
                sanitized = regex.stringByReplacingMatches(
                    in: sanitized,
                    options: [],
                    range: range,
                    withTemplate: "[REDACTED]"
                )
            }
        }
        
        return sanitized
    }
}

// MARK: - Extensions for Easy Integration
extension GuardrailService {
    
    /// Process a complete request with all guardrails
    func processRequest(_ input: String) throws -> ParsedPrompt {
        // Parse the input
        let parsed = try validateInput(json: input)
        
        // Filter the content
        try filterContent(parsed.prompt)
        
        return parsed
    }
    
    /// Process and format a response
    func processResponse(_ response: String, for prompt: ParsedPrompt) -> String {
        // Sanitize the output first
        let sanitized = sanitizeOutput(response)
        
        // Format according to requirements
        return formatOutput(text: sanitized, codeOnly: prompt.codeOnly, language: prompt.language)
    }
}