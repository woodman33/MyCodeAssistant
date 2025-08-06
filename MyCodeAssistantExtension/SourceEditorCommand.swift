import Foundation
import XcodeKit
import AppKit


// MARK: - Main Command
class SourceEditorCommand: NSObject, XCSourceEditorCommand {

    func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void) {
        // Placeholder implementation for MVP
        let placeholderCode = "// MyCodeAssistant - Generated code will appear here"
        insertCode(placeholderCode, in: invocation.buffer)
        completionHandler(nil)
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
