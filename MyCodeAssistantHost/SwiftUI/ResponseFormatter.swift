import SwiftUI
import Foundation

// MARK: - Response Formatter
/// Utility for formatting LLM responses with markdown, code highlighting, and rich text support
public class ResponseFormatter: ObservableObject {
    
    // MARK: - Singleton
    static let shared = ResponseFormatter()
    
    // MARK: - Formatting Configuration
    struct FormattingConfig {
        let codeBackgroundColor: Color
        let codeTextColor: Color
        let linkColor: Color
        let quoteBarColor: Color
        let quoteBgColor: Color
        let headingColor: Color
        let strongTextColor: Color
        let emphasisTextColor: Color
        
        static func light() -> FormattingConfig {
            FormattingConfig(
                codeBackgroundColor: Color.gray.opacity(0.1),
                codeTextColor: Color.red,
                linkColor: Color.blue,
                quoteBarColor: Color.gray.opacity(0.4),
                quoteBgColor: Color.gray.opacity(0.1),
                headingColor: Color.primary,
                strongTextColor: Color.primary,
                emphasisTextColor: Color.primary
            )
        }
        
        static func dark() -> FormattingConfig {
            FormattingConfig(
                codeBackgroundColor: Color.gray.opacity(0.2),
                codeTextColor: Color.orange,
                linkColor: Color.cyan,
                quoteBarColor: Color.gray.opacity(0.6),
                quoteBgColor: Color.gray.opacity(0.2),
                headingColor: Color.primary,
                strongTextColor: Color.primary,
                emphasisTextColor: Color.primary
            )
        }
    }
    
    // MARK: - Public Interface
    
    /// Format a raw response string into an AttributedString with rich formatting
    public func formatResponse(_ content: String, colorScheme: ColorScheme = .light) -> AttributedString {
        let config = colorScheme == .dark ? FormattingConfig.dark() : FormattingConfig.light()
        
        // Start with the base content
        var attributedString = AttributedString(content)
        
        // Apply formatting in order of precedence
        attributedString = formatCodeBlocks(attributedString, config: config)
        attributedString = formatInlineCode(attributedString, config: config)
        attributedString = formatHeaders(attributedString, config: config)
        attributedString = formatBoldText(attributedString, config: config)
        attributedString = formatItalicText(attributedString, config: config)
        attributedString = formatLinks(attributedString, config: config)
        attributedString = formatLists(attributedString, config: config)
        attributedString = formatBlockquotes(attributedString, config: config)
        
        return attributedString
    }
    
    /// Extract code blocks from content for copy functionality
    public func extractCodeBlocks(_ content: String) -> [CodeBlock] {
        var codeBlocks: [CodeBlock] = []
        let pattern = #"```(\w+)?\n?([\s\S]*?)```"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return codeBlocks
        }
        
        let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
        
        for match in matches {
            let languageRange = match.range(at: 1)
            let codeRange = match.range(at: 2)
            
            let language = languageRange.location != NSNotFound ? 
                String(content[Range(languageRange, in: content)!]) : "text"
            let code = String(content[Range(codeRange, in: content)!])
            
            codeBlocks.append(CodeBlock(language: language, code: code.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        
        return codeBlocks
    }
    
    /// Check if content contains JSON and format it
    public func formatJSON(_ jsonString: String) -> String? {
        guard let jsonData = jsonString.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: jsonData),
              let prettyJsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
              let prettyJsonString = String(data: prettyJsonData, encoding: .utf8) else {
            return nil
        }
        return prettyJsonString
    }
    
    /// Detect if content is primarily JSON
    public func isJSON(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
               (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
    }
    
    // MARK: - Private Formatting Methods
    
    private func formatCodeBlocks(_ attributedString: AttributedString, config: FormattingConfig) -> AttributedString {
        var result = attributedString
        let pattern = #"```(\w+)?\n?([\s\S]*?)```"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return result
        }
        
        let content = String(attributedString.characters)
        let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
        
        // Process matches in reverse order to maintain string indices
        for match in matches.reversed() {
            let fullRange = match.range
            let codeRange = match.range(at: 2)
            
            guard let fullStringRange = Range(fullRange, in: content),
                  let codeStringRange = Range(codeRange, in: content) else { continue }
            
            let code = String(content[codeStringRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Create attributed string for code block
            var codeAttributedString = AttributedString(code)
            codeAttributedString.font = .system(.body, design: .monospaced)
            codeAttributedString.foregroundColor = config.codeTextColor
            codeAttributedString.backgroundColor = config.codeBackgroundColor
            
            // Add padding and border effect (simulated with background color)
            let paddedCode = "\n\(code)\n"
            codeAttributedString = AttributedString(paddedCode)
            codeAttributedString.font = .system(.body, design: .monospaced)
            codeAttributedString.foregroundColor = config.codeTextColor
            codeAttributedString.backgroundColor = config.codeBackgroundColor
            
            // Replace the original code block with formatted version
            if let attributedRange = Range(fullStringRange, in: result) {
                result.replaceSubrange(attributedRange, with: codeAttributedString)
            }
        }
        
        return result
    }
    
    private func formatInlineCode(_ attributedString: AttributedString, config: FormattingConfig) -> AttributedString {
        var result = attributedString
        let pattern = #"`([^`\n]+)`"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return result
        }
        
        let content = String(attributedString.characters)
        let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
        
        // Process matches in reverse order to maintain string indices
        for match in matches.reversed() {
            let fullRange = match.range
            let codeRange = match.range(at: 1)
            
            guard let fullStringRange = Range(fullRange, in: content),
                  let codeStringRange = Range(codeRange, in: content) else { continue }
            
            let code = String(content[codeStringRange])
            
            // Create attributed string for inline code
            var inlineCodeAttributedString = AttributedString(code)
            inlineCodeAttributedString.font = .system(.body, design: .monospaced)
            inlineCodeAttributedString.foregroundColor = config.codeTextColor
            inlineCodeAttributedString.backgroundColor = config.codeBackgroundColor
            
            // Replace the original inline code with formatted version
            if let attributedRange = Range(fullStringRange, in: result) {
                result.replaceSubrange(attributedRange, with: inlineCodeAttributedString)
            }
        }
        
        return result
    }
    
    private func formatHeaders(_ attributedString: AttributedString, config: FormattingConfig) -> AttributedString {
        var result = attributedString
        
        // Header patterns (H1-H6)
        let headerPatterns = [
            (#"^# (.+)$"#, Font.title.bold()),
            (#"^## (.+)$"#, Font.title2.bold()),
            (#"^### (.+)$"#, Font.title3.bold()),
            (#"^#### (.+)$"#, Font.headline.bold()),
            (#"^##### (.+)$"#, Font.subheadline.bold()),
            (#"^###### (.+)$"#, Font.caption.bold())
        ]
        
        for (pattern, font) in headerPatterns {
            result = applyPattern(result, pattern: pattern, font: font, color: config.headingColor)
        }
        
        return result
    }
    
    private func formatBoldText(_ attributedString: AttributedString, config: FormattingConfig) -> AttributedString {
        var result = attributedString
        
        // Bold patterns: **text** and __text__
        let patterns = [#"\*\*([^\*\n]+)\*\*"#, #"__([^_\n]+)__"#]
        
        for pattern in patterns {
            result = applyPattern(result, pattern: pattern, font: .body.bold(), color: config.strongTextColor)
        }
        
        return result
    }
    
    private func formatItalicText(_ attributedString: AttributedString, config: FormattingConfig) -> AttributedString {
        var result = attributedString
        
        // Italic patterns: *text* and _text_
        let patterns = [#"\*([^\*\n]+)\*"#, #"_([^_\n]+)_"#]
        
        for pattern in patterns {
            result = applyPattern(result, pattern: pattern, font: .body.italic(), color: config.emphasisTextColor)
        }
        
        return result
    }
    
    private func formatLinks(_ attributedString: AttributedString, config: FormattingConfig) -> AttributedString {
        var result = attributedString
        
        // Markdown link pattern: [text](url)
        let linkPattern = #"\[([^\]]+)\]\(([^)]+)\)"#
        
        guard let regex = try? NSRegularExpression(pattern: linkPattern, options: []) else {
            return result
        }
        
        let content = String(attributedString.characters)
        let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
        
        // Process matches in reverse order to maintain string indices
        for match in matches.reversed() {
            let fullRange = match.range
            let textRange = match.range(at: 1)
            let urlRange = match.range(at: 2)
            
            guard let fullStringRange = Range(fullRange, in: content),
                  let textStringRange = Range(textRange, in: content),
                  let urlStringRange = Range(urlRange, in: content) else { continue }
            
            let linkText = String(content[textStringRange])
            let linkUrl = String(content[urlStringRange])
            
            // Create attributed string for link
            var linkAttributedString = AttributedString(linkText)
            linkAttributedString.font = .body
            linkAttributedString.foregroundColor = config.linkColor
            linkAttributedString.underlineStyle = .single
            
            // Add link attribute if it's a valid URL
            if let url = URL(string: linkUrl) {
                linkAttributedString.link = url
            }
            
            // Replace the original link markdown with formatted version
            if let attributedRange = Range(fullStringRange, in: result) {
                result.replaceSubrange(attributedRange, with: linkAttributedString)
            }
        }
        
        return result
    }
    
    private func formatLists(_ attributedString: AttributedString, config: FormattingConfig) -> AttributedString {
        var result = attributedString
        
        // Unordered list pattern: - item or * item
        let unorderedListPattern = #"^[\s]*[-\*]\s+(.+)$"#
        
        // Ordered list pattern: 1. item
        let orderedListPattern = #"^[\s]*\d+\.\s+(.+)$"#
        
        result = applyListPattern(result, pattern: unorderedListPattern, marker: "•")
        result = applyListPattern(result, pattern: orderedListPattern, marker: nil)
        
        return result
    }
    
    private func formatBlockquotes(_ attributedString: AttributedString, config: FormattingConfig) -> AttributedString {
        var result = attributedString
        let pattern = #"^>\s+(.+)$"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return result
        }
        
        let content = String(attributedString.characters)
        let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
        
        // Process matches in reverse order to maintain string indices
        for match in matches.reversed() {
            let fullRange = match.range
            let textRange = match.range(at: 1)
            
            guard let fullStringRange = Range(fullRange, in: content),
                  let textStringRange = Range(textRange, in: content) else { continue }
            
            let quoteText = String(content[textStringRange])
            
            // Create attributed string for blockquote
            var quoteAttributedString = AttributedString("│ \(quoteText)")
            quoteAttributedString.font = .body.italic()
            quoteAttributedString.foregroundColor = Color(.systemGray)
            quoteAttributedString.backgroundColor = config.quoteBgColor
            
            // Replace the original blockquote with formatted version
            if let attributedRange = Range(fullStringRange, in: result) {
                result.replaceSubrange(attributedRange, with: quoteAttributedString)
            }
        }
        
        return result
    }
    
    // MARK: - Helper Methods
    
    private func applyPattern(_ attributedString: AttributedString, pattern: String, font: Font, color: Color) -> AttributedString {
        var result = attributedString
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return result
        }
        
        let content = String(attributedString.characters)
        let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
        
        // Process matches in reverse order to maintain string indices
        for match in matches.reversed() {
            let fullRange = match.range
            let textRange = match.range(at: 1)
            
            guard let fullStringRange = Range(fullRange, in: content),
                  let textStringRange = Range(textRange, in: content) else { continue }
            
            let text = String(content[textStringRange])
            
            // Create attributed string with formatting
            var formattedAttributedString = AttributedString(text)
            formattedAttributedString.font = font
            formattedAttributedString.foregroundColor = color
            
            // Replace the original text with formatted version
            if let attributedRange = Range(fullStringRange, in: result) {
                result.replaceSubrange(attributedRange, with: formattedAttributedString)
            }
        }
        
        return result
    }
    
    private func applyListPattern(_ attributedString: AttributedString, pattern: String, marker: String?) -> AttributedString {
        var result = attributedString
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return result
        }
        
        let content = String(attributedString.characters)
        let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
        
        // Process matches in reverse order to maintain string indices
        for match in matches.reversed() {
            let fullRange = match.range
            let textRange = match.range(at: 1)
            
            guard let fullStringRange = Range(fullRange, in: content),
                  let textStringRange = Range(textRange, in: content) else { continue }
            
            let text = String(content[textStringRange])
            let displayText = marker != nil ? "\(marker!) \(text)" : text
            
            // Create attributed string for list item
            var listItemAttributedString = AttributedString(displayText)
            listItemAttributedString.font = .body
            
            // Replace the original list item with formatted version
            if let attributedRange = Range(fullStringRange, in: result) {
                result.replaceSubrange(attributedRange, with: listItemAttributedString)
            }
        }
        
        return result
    }
}

// MARK: - Code Block Model
public struct CodeBlock: Identifiable, Equatable {
    public let id = UUID()
    public let language: String
    public let code: String
    
    public init(language: String, code: String) {
        self.language = language
        self.code = code
    }
    
    /// Get syntax highlighting color for language
    public var syntaxColor: Color {
        switch language.lowercased() {
        case "swift": return .orange
        case "python", "py": return .blue
        case "javascript", "js": return .yellow
        case "typescript", "ts": return .blue
        case "html": return .red
        case "css": return .purple
        case "json": return .green
        case "xml": return .orange
        case "sql": return .cyan
        case "bash", "shell", "sh": return .gray
        case "go": return .cyan
        case "rust", "rs": return .orange
        case "java": return .red
        case "kotlin", "kt": return .purple
        case "c", "cpp", "c++": return .blue
        case "csharp", "cs": return .green
        case "php": return .indigo
        case "ruby", "rb": return .red
        default: return .primary
        }
    }
    
    /// Get display name for language
    public var displayName: String {
        switch language.lowercased() {
        case "js": return "JavaScript"
        case "ts": return "TypeScript"
        case "py": return "Python"
        case "rb": return "Ruby"
        case "cs": return "C#"
        case "cpp", "c++": return "C++"
        case "rs": return "Rust"
        case "kt": return "Kotlin"
        case "sh": return "Shell"
        default: return language.capitalized
        }
    }
}

// MARK: - Streaming Support
extension ResponseFormatter {
    /// Format content for streaming updates (optimized for performance)
    public func formatStreamingResponse(_ content: String, colorScheme: ColorScheme = .light) -> AttributedString {
        // For streaming, apply basic formatting only to avoid performance issues
        let config = colorScheme == .dark ? FormattingConfig.dark() : FormattingConfig.light()
        
        var attributedString = AttributedString(content)
        
        // Apply only inline code and basic formatting for streaming
        attributedString = formatInlineCode(attributedString, config: config)
        
        // Check if we have complete code blocks and format them
        if content.contains("```") {
            let codeBlockCount = content.components(separatedBy: "```").count - 1
            if codeBlockCount % 2 == 0 { // Even number means complete code blocks
                attributedString = formatCodeBlocks(attributedString, config: config)
            }
        }
        
        return attributedString
    }
}