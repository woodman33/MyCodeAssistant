import Foundation
import XcodeKit

class SourceEditorExtension: NSObject, XCSourceEditorExtension {
    
    func extensionDidFinishLaunching() {
        // Extension setup code here if needed
    }
    
    var commandDefinitions: [[XCSourceEditorCommandDefinitionKey : Any]] {
        // Return array of command definitions
        return [
            [
                XCSourceEditorCommandDefinitionKey.classNameKey: "SourceEditorCommand",
                XCSourceEditorCommandDefinitionKey.commandNameKey: "MyCodeAssistant.AICommand",
                XCSourceEditorCommandDefinitionKey.commandIdentifierKey: "ai-command"
            ]
        ]
    }
}