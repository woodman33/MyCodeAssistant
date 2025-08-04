import Foundation
import XcodeKit
import AppKit

// MARK: - SourceEditorExtension
// This class is the entry point for the extension.
class SourceEditorExtension: NSObject, XCSourceEditorExtension {
    /*
     // If you want to provide your own command definitions, you can uncomment this method.
     // Otherwise, the command definitions from the Info.plist will be used.
    var commandDefinitions: [[XCSourceEditorCommandDefinitionKey: Any]] {
        return [[
            .nameKey: "Generate Code...",
            .classNameKey: "SourceEditorCommand",
            .identifierKey: "com.your-team.MyCodeAssistant.AICommand.SourceEditorCommand"
        ]]
    }
    */
}

// MARK: - Main Command
class SourceEditorCommand: NSObject, XCSourceEditorCommand {

    func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void) {
        let geminiAPI = GeminiAPI()

        guard let apiKey = getAPIKey() else {
            completionHandler(nil)
            return
        }
        geminiAPI.apiKey = apiKey

        showPromptDialog { prompt in
            guard let prompt = prompt, !prompt.isEmpty else {
                completionHandler(nil)
                return
            }

            Task {
                do {
                    let generatedCode = try await geminiAPI.generateCode(prompt: prompt)
                    DispatchQueue.main.async {
                        self.insertCode(generatedCode, in: invocation.buffer)
                        completionHandler(nil)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.showError(error)
                        completionHandler(error)
                    }
                }
            }
        }
    }

    private func insertCode(_ code: String, in buffer: XCSourceTextBuffer) {
        guard let selection = buffer.selections.firstObject as? XCSourceTextRange else {
            buffer.lines.add(code)
            return
        }
        
        if selection.start.line == selection.end.line && selection.start.column == selection.end.column {
            buffer.lines.insert(code, at: selection.start.line)
        } else {
            for i in (selection.start.line...selection.end.line).reversed() {
                buffer.lines.removeObject(at: i)
            }
            buffer.lines.insert(code, at: selection.start.line)
        }
    }
    
    private func showPromptDialog(completion: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Generate Swift Code"
        alert.informativeText = "Enter a description of the code you want to generate:"
        alert.addButton(withTitle: "Generate")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        alert.accessoryView = textField

        DispatchQueue.main.async {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                completion(textField.stringValue)
            } else {
                completion(nil)
            }
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        DispatchQueue.main.async {
            alert.runModal()
        }
    }
    
    private func getAPIKey() -> String? {
        let defaults = UserDefaults.standard
        if let apiKey = defaults.string(forKey: "GeminiAPIKey") {
            return apiKey
        }
        
        let alert = NSAlert()
        alert.messageText = "Gemini API Key"
        alert.informativeText = "Please enter your Gemini API key from Google AI Studio."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        
        let textField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        alert.accessoryView = textField
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            let apiKey = textField.stringValue
            defaults.set(apiKey, forKey: "GeminiAPIKey")
            return apiKey
        }
        return nil
    }
}

// MARK: - Gemini API Client
class GeminiAPI {
    var apiKey: String?
    private let apiURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!

    func generateCode(prompt: String) async throws -> String {
        guard let apiKey = apiKey else {
            throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "API Key not set."])
        }

        var request = URLRequest(url: apiURL.appending(queryItems: [URLQueryItem(name: "key", value: apiKey)]))
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // This is where the instructions for the LLM are used.
        let masterPrompt = """
        You are an expert Swift and SwiftUI programmer acting as an AI code assistant inside Xcode. Your sole purpose is to generate clean, correct, and idiomatic Swift code based on the user's request.

        Generate ONLY the raw Swift code for the following request.

        Do NOT include:
        - Explanations or introductory text.
        - Markdown formatting like `swift or `.
        - Any conversational text or pleasantries.

        The user's request is: \(prompt)
        """
        
        let requestBody = GeminiRequest(contents: [Content(parts: [Part(text: masterPrompt)])])
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "GeminiAPI", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorBody)"])
        }
        
        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let generatedText = geminiResponse.candidates.first?.content.parts.first?.text ?? ""
        return generatedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - API Data Models
struct GeminiRequest: Codable { let contents: [Content] }
struct Content: Codable { let parts: [Part] }
struct Part: Codable { let text: String }
struct GeminiResponse: Codable { let candidates: [Candidate] }
struct Candidate: Codable { let content: Content }
