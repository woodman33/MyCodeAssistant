import Foundation
import XcodeKit
import AppKit


// MARK: - Main Command
class SourceEditorCommand: NSObject, XCSourceEditorCommand {

    func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void) {
        guard let selection = invocation.buffer.selections.firstObject as? XCSourceTextRange else {
            completionHandler(nil)
            return
        }

        let selectedText = invocation.buffer.lines[selection.start.line] as! String

        // Route to Edge Backend instead of GPT5
        Task {
            let client = EdgeBackendClient()
            do {
                let reply = try await client.chat(selectedText)
                DispatchQueue.main.async {
                    self.insertCode(reply, in: invocation.buffer)
                    completionHandler(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    self.insertCode("Error: \(error.localizedDescription)", in: invocation.buffer)
                    completionHandler(error)
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
    
}
