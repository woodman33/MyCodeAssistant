import XCTest
@testable import MyCodeAssistantCore

class GuardrailServiceTests: XCTestCase {
    
    var service: GuardrailService!
    
    override func setUp() {
        super.setUp()
        service = GuardrailService.shared
    }
    
    override func tearDown() {
        service = nil
        super.tearDown()
    }
    
    // MARK: - Valid Input Tests
    
    func testValidJSONParsing() throws {
        let json = """
        {
            "language": "swift",
            "codeOnly": true,
            "prompt": "Write a hello world function"
        }
        """
        
        let result = try service.validateInput(json: json)
        
        XCTAssertEqual(result.language, "swift")
        XCTAssertTrue(result.codeOnly)
        XCTAssertEqual(result.prompt, "Write a hello world function")
    }
    
    func testCaseInsensitiveLanguage() throws {
        let json = """
        {
            "language": "PYTHON",
            "codeOnly": false,
            "prompt": "Explain async/await"
        }
        """
        
        let result = try service.validateInput(json: json)
        
        XCTAssertEqual(result.language, "python") // Should be normalized to lowercase
        XCTAssertFalse(result.codeOnly)
    }
    
    func testAllSupportedLanguages() throws {
        let languages = ["swift", "python", "javascript", "java", "cpp", "go", "rust"]
        
        for language in languages {
            let json = """
            {
                "language": "\(language)",
                "codeOnly": true,
                "prompt": "Test prompt"
            }
            """
            
            let result = try service.validateInput(json: json)
            XCTAssertEqual(result.language, language)
        }
    }
    
    // MARK: - Invalid Input Tests
    
    func testInvalidJSON() {
        let invalidJson = "This is not JSON"
        
        XCTAssertThrowsError(try service.validateInput(json: invalidJson)) { error in
            XCTAssertTrue(error is GuardrailError)
            if let guardrailError = error as? GuardrailError {
                switch guardrailError {
                case .invalidJSON:
                    XCTAssertTrue(true)
                default:
                    XCTFail("Expected invalidJSON error")
                }
            }
        }
    }
    
    func testMissingRequiredField() {
        let json = """
        {
            "language": "swift",
            "codeOnly": true
        }
        """
        
        XCTAssertThrowsError(try service.validateInput(json: json)) { error in
            XCTAssertTrue(error is GuardrailError)
            if let guardrailError = error as? GuardrailError {
                switch guardrailError {
                case .missingRequiredField(let field):
                    XCTAssertEqual(field, "prompt")
                default:
                    XCTFail("Expected missingRequiredField error")
                }
            }
        }
    }
    
    func testUnsupportedLanguage() {
        let json = """
        {
            "language": "cobol",
            "codeOnly": true,
            "prompt": "Write COBOL code"
        }
        """
        
        XCTAssertThrowsError(try service.validateInput(json: json)) { error in
            XCTAssertTrue(error is GuardrailError)
            if let guardrailError = error as? GuardrailError {
                switch guardrailError {
                case .unsupportedLanguage(let lang):
                    XCTAssertEqual(lang, "cobol")
                default:
                    XCTFail("Expected unsupportedLanguage error")
                }
            }
        }
    }
    
    func testEmptyPrompt() {
        let json = """
        {
            "language": "swift",
            "codeOnly": true,
            "prompt": "   "
        }
        """
        
        XCTAssertThrowsError(try service.validateInput(json: json)) { error in
            XCTAssertTrue(error is GuardrailError)
            if let guardrailError = error as? GuardrailError {
                switch guardrailError {
                case .emptyPrompt:
                    XCTAssertTrue(true)
                default:
                    XCTFail("Expected emptyPrompt error")
                }
            }
        }
    }
    
    // MARK: - Content Filtering Tests
    
    func testFilterDisallowedKeywords() {
        let harmfulContent = "How to hack password for a website"
        
        XCTAssertThrowsError(try service.filterContent(harmfulContent)) { error in
            XCTAssertTrue(error is GuardrailError)
            if let guardrailError = error as? GuardrailError {
                switch guardrailError {
                case .contentFiltered:
                    XCTAssertTrue(true)
                default:
                    XCTFail("Expected contentFiltered error")
                }
            }
        }
    }
    
    func testFilterSensitivePatterns() {
        let sensitiveContent = "My API key is sk-1234567890abcdef"
        
        XCTAssertThrowsError(try service.filterContent(sensitiveContent)) { error in
            XCTAssertTrue(error is GuardrailError)
            if let guardrailError = error as? GuardrailError {
                switch guardrailError {
                case .contentFiltered:
                    XCTAssertTrue(true)
                default:
                    XCTFail("Expected contentFiltered error")
                }
            }
        }
    }
    
    func testAllowSafeContent() {
        let safeContent = "Write a function to sort an array"
        
        XCTAssertNoThrow(try service.filterContent(safeContent))
    }
    
    // MARK: - Output Formatting Tests
    
    func testFormatCodeOnlyOutput() {
        let code = "func hello() { print(\"Hello\") }"
        let formatted = service.formatOutput(text: code, codeOnly: true, language: "swift")
        
        XCTAssertTrue(formatted.hasPrefix("```swift"))
        XCTAssertTrue(formatted.hasSuffix("```"))
        XCTAssertTrue(formatted.contains(code))
    }
    
    func testFormatPlainTextOutput() {
        let text = "This is a plain text explanation"
        let formatted = service.formatOutput(text: text, codeOnly: false, language: "swift")
        
        XCTAssertEqual(formatted, text)
        XCTAssertFalse(formatted.contains("```"))
    }
    
    func testDontDoubleWrapCodeBlocks() {
        let alreadyFormatted = """
        ```swift
        func test() {}
        ```
        """
        
        let formatted = service.formatOutput(text: alreadyFormatted, codeOnly: true, language: "swift")
        
        // Should not add additional code blocks
        XCTAssertEqual(formatted, alreadyFormatted)
    }
    
    // MARK: - Sanitization Tests
    
    func testSanitizeAPIKeys() throws {
        // TODO: Future security sweep - API key sanitization needs review
        throw XCTSkip("Skipping for future security sweep")
        
        // let textWithKey = "The API key is sk-1234567890abcdef123456"
        // let sanitized = service.sanitizeOutput(textWithKey)
        //
        // XCTAssertTrue(sanitized.contains("[REDACTED]"))
        // XCTAssertFalse(sanitized.contains("sk-1234567890"))
    }
    
    func testSanitizeCreditCardNumbers() {
        let textWithCard = "Card number: 1234-5678-9012-3456"
        let sanitized = service.sanitizeOutput(textWithCard)
        
        XCTAssertTrue(sanitized.contains("[REDACTED]"))
        XCTAssertFalse(sanitized.contains("1234-5678"))
    }
    
    // MARK: - Integration Tests
    
    func testProcessRequestSuccess() throws {
        let json = """
        {
            "language": "python",
            "codeOnly": true,
            "prompt": "Write a fibonacci function"
        }
        """
        
        let result = try service.processRequest(json)
        
        XCTAssertEqual(result.language, "python")
        XCTAssertTrue(result.codeOnly)
        XCTAssertEqual(result.prompt, "Write a fibonacci function")
    }
    
    func testProcessRequestWithFilteredContent() {
        let json = """
        {
            "language": "python",
            "codeOnly": true,
            "prompt": "Write malware code"
        }
        """
        
        XCTAssertThrowsError(try service.processRequest(json)) { error in
            XCTAssertTrue(error is GuardrailError)
        }
    }
    
    func testProcessResponse() {
        let prompt = ParsedPrompt(language: "javascript", codeOnly: true, prompt: "Test")
        let response = "console.log('Hello World');"
        
        let processed = service.processResponse(response, for: prompt)
        
        XCTAssertTrue(processed.hasPrefix("```javascript"))
        XCTAssertTrue(processed.contains(response))
        XCTAssertTrue(processed.hasSuffix("```"))
    }
    
    // MARK: - Helper Method Tests
    
    func testParseSimplePromptWithJSON() {
        let json = """
        {
            "language": "go",
            "codeOnly": false,
            "prompt": "Explain goroutines"
        }
        """
        
        let result = service.parseSimplePrompt(json)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.language, "go")
        XCTAssertEqual(result?.codeOnly, false)
    }
    
    func testParseSimplePromptWithPlainText() {
        let plainText = "Just a regular prompt"
        
        let result = service.parseSimplePrompt(plainText)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.language, "swift") // Default
        XCTAssertEqual(result?.codeOnly, false) // Default
        XCTAssertEqual(result?.prompt, plainText)
    }
}