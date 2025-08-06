import SwiftUI
import Foundation

// MARK: - Formatter Test View
/// Test view for validating the ResponseFormatter with various content types
struct FormatterTestView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedTest = 0
    
    let testCases = [
        TestCase(
            title: "Markdown Formatting",
            content: """
            # Main Header
            ## Sub Header
            ### Small Header
            
            This is **bold text** and this is *italic text*.
            
            Here's some `inline code` in a sentence.
            
            ## Lists
            
            Unordered list:
            - First item
            - Second item
            - Third item
            
            Ordered list:
            1. First numbered item
            2. Second numbered item
            3. Third numbered item
            
            ## Links and Quotes
            
            Check out [this link](https://example.com) for more info.
            
            > This is a blockquote
            > that spans multiple lines
            > and shows formatting
            """
        ),
        
        TestCase(
            title: "Code Blocks",
            content: """
            Here are some code examples:
            
            ```swift
            struct ContentView: View {
                var body: some View {
                    Text("Hello, SwiftUI!")
                        .padding()
                }
            }
            ```
            
            ```python
            def hello_world():
                print("Hello, World!")
                return True
            ```
            
            ```javascript
            const greeting = (name) => {
                console.log(`Hello, ${name}!`);
                return `Welcome, ${name}`;
            }
            ```
            
            And some inline code: `let x = 42` in Swift.
            """
        ),
        
        TestCase(
            title: "JSON Response",
            content: """
            Here's a JSON response:
            
            ```json
            {
                "status": "success",
                "data": {
                    "users": [
                        {
                            "id": 1,
                            "name": "John Doe",
                            "email": "john@example.com"
                        },
                        {
                            "id": 2,
                            "name": "Jane Smith",
                            "email": "jane@example.com"
                        }
                    ],
                    "totalCount": 2
                }
            }
            ```
            
            The API returned a successful response with user data.
            """
        ),
        
        TestCase(
            title: "Mixed Content",
            content: """
            # API Documentation
            
            ## Overview
            This API provides **user management** functionality.
            
            ### Authentication
            Use `Bearer` tokens in the *Authorization* header:
            
            ```bash
            curl -H "Authorization: Bearer YOUR_TOKEN" \\
                 https://api.example.com/users
            ```
            
            ## Endpoints
            
            ### GET /users
            Returns a list of users.
            
            **Response:**
            ```json
            {
                "users": [],
                "count": 0
            }
            ```
            
            ### POST /users
            Creates a new user.
            
            > **Note:** Email addresses must be unique.
            
            For more information, visit [our docs](https://docs.example.com).
            
            ## Error Handling
            
            Common errors:
            - `400` - Bad Request
            - `401` - Unauthorized  
            - `404` - Not Found
            - `500` - Internal Server Error
            """
        ),
        
        TestCase(
            title: "Streaming Test (Incomplete)",
            content: """
            Here's some content that might be streaming...
            
            This includes **partial** formatting and some `code` but
            
            ```python
            # This code block is incomplete
            def streaming_function():
                print("This is still being typed
            """
        ),
        
        TestCase(
            title: "Edge Cases",
            content: """
            # Testing Edge Cases
            
            **Unclosed bold text
            *Unclosed italic text
            `Unclosed inline code
            
            ```
            Code block with no language
            and some content
            ```
            
            ```swift
            // Code block with language but incomplete
            func test() {
                print("incomplete
            
            [Incomplete link](
            
            > Blockquote without proper
            spacing and formatting
            
            - List item 1
            - List item 2
            Missing continuation...
            """
        )
    ]
    
    var body: some View {
        NavigationView {
            VStack {
                // Test case selector
                Picker("Test Case", selection: $selectedTest) {
                    ForEach(testCases.indices, id: \.self) { index in
                        Text(testCases[index].title).tag(index)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Test content display
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Original Content:")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text(testCases[selectedTest].content)
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        
                        Text("Formatted Result:")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        // Using our FormattedText component
                        FormattedText(
                            content: testCases[selectedTest].content,
                            colorScheme: colorScheme
                        )
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Material.ultraThickMaterial)
                                .shadow(radius: 2)
                        )
                        
                        // Code blocks extraction test
                        let codeBlocks = ResponseFormatter.shared.extractCodeBlocks(testCases[selectedTest].content)
                        if !codeBlocks.isEmpty {
                            Text("Extracted Code Blocks:")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            ForEach(codeBlocks) { codeBlock in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(codeBlock.displayName)
                                            .font(.caption)
                                            .foregroundColor(codeBlock.syntaxColor)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(
                                                Capsule()
                                                    .fill(codeBlock.syntaxColor.opacity(0.2))
                                            )
                                        
                                        Spacer()
                                        
                                        Button("Copy") {
                                            #if os(macOS)
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(codeBlock.code, forType: .string)
                                            #elseif os(iOS)
                                            UIPasteboard.general.string = codeBlock.code
                                            #endif
                                        }\n                                        .font(.caption)\n                                        .foregroundColor(.blue)\n                                    }\n                                    \n                                    Text(codeBlock.code)\n                                        .font(.system(.caption2, design: .monospaced))\n                                        .padding(8)\n                                        .background(Color(.systemGray6))\n                                        .cornerRadius(6)\n                                }\n                                .padding(.vertical, 4)\n                            }\n                        }\n                        \n                        // JSON detection test\n                        if ResponseFormatter.shared.isJSON(testCases[selectedTest].content) {\n                            Text("JSON Detected")  \n                                .font(.caption)\n                                .foregroundColor(.green)\n                                .padding(.horizontal, 8)\n                                .padding(.vertical, 2)\n                                .background(\n                                    Capsule()\n                                        .fill(Color.green.opacity(0.2))\n                                )\n                        }\n                    }\n                    .padding()\n                }\n            }\n            .navigationTitle("Formatter Tests")\n        }\n    }\n}\n\n// MARK: - Test Case Model\nstruct TestCase {\n    let title: String\n    let content: String\n}\n\n// MARK: - Preview\n#Preview {\n    FormatterTestView()\n}