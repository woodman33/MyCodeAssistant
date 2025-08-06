import SwiftUI

// MARK: - Message Card
struct MessageCard: View {
    let message: ChatMessage
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    @State private var showCopyOptions = false
    @StateObject private var formatter = ResponseFormatter.shared
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // Role indicator
                roleHeader
                
                // Message card
                messageCardContent
                
                // Timestamp
                timestampView
            }
            .frame(maxWidth: .infinity * 0.8, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .assistant {
                Spacer()
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .overlay(
            // Copy and action buttons overlay
            HStack {
                Spacer()
                if isHovered {
                    MessageActionsView(message: message, showCopyOptions: $showCopyOptions)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .padding(.trailing, 8)
            .padding(.top, 8),
            alignment: .topTrailing
        )
    }
    
    // MARK: - Role Header
    private var roleHeader: some View {
        HStack(spacing: 6) {
            // Role icon
            Image(systemName: roleIcon)
                .font(.caption)
                .foregroundColor(roleColor)
            
            // Role name
            Text(message.role.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(roleColor)
            
            if message.role == .assistant {
                Spacer()
            }
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Message Card Content
    private var messageCardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            FormattedText(content: message.content, colorScheme: colorScheme)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .textSelection(.enabled)
        }
        .background(
            ZStack {
                cardBackground
                
                RoundedRectangle(cornerRadius: 12)
                    .stroke(accentBorder, lineWidth: isHovered ? 1.5 : 1)
                    .opacity(isHovered ? 1 : 0.6)
            }
            .shadow(
                color: shadowColor,
                radius: isHovered ? 8 : 4,
                x: 0,
                y: isHovered ? 4 : 2
            )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovered)
    }
    
    // MARK: - Timestamp
    private var timestampView: some View {
        Text(formattedTimestamp)
            .font(.caption2)
            .foregroundColor(.secondary)
            .opacity(isHovered ? 1 : 0.7)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
    }
    
    // MARK: - Computed Properties
    private var roleIcon: String {
        switch message.role {
        case .user:
            return "person.circle"
        case .assistant:
            return "brain.head.profile"
        case .system:
            return "gear.circle"
        case .function:
            return "function"
        }
    }
    
    private var roleColor: Color {
        switch message.role {
        case .user:
            return themeManager.accentColor.color
        case .assistant:
            return Color.green
        case .system:
            return Color.orange
        case .function:
            return Color.purple
        }
    }
    
    @ViewBuilder
    private var cardBackground: some View {
        if message.role == .user {
            // User message: more solid background
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            themeManager.accentColor.color.opacity(0.15),
                            themeManager.accentColor.color.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Material.ultraThickMaterial)
                )
        } else {
            // Assistant message: glassy background
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.8))
        }
    }
    
    private var accentBorder: Color {
        switch message.role {
        case .user:
            return themeManager.accentColor.color.opacity(0.6)
        case .assistant:
            return Color.green.opacity(0.4)
        case .system:
            return Color.orange.opacity(0.4)
        case .function:
            return Color.purple.opacity(0.4)
        }
    }
    
    private var shadowColor: Color {
        switch message.role {
        case .user:
            return themeManager.accentColor.color.opacity(0.3)
        case .assistant:
            return Color.green.opacity(0.2)
        case .system:
            return Color.orange.opacity(0.2)
        case .function:
            return Color.purple.opacity(0.2)
        }
    }
    
    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }
}

// MARK: - Streaming Message Card
struct StreamingMessageCard: View {
    let content: String
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) var colorScheme
    @State private var cursorVisible = true
    @StateObject private var formatter = ResponseFormatter.shared
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                // Role header
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    Text("Assistant")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                    
                    // Streaming indicator
                    HStack(spacing: 2) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(Color.green.opacity(0.7))
                                .frame(width: 3, height: 3)
                                .scaleEffect(cursorVisible ? 1.0 : 0.5)
                                .animation(
                                    .easeInOut(duration: 0.6)
                                    .repeatForever()
                                    .delay(Double(index) * 0.2),
                                    value: cursorVisible
                                )
                        }
                    }
                    .padding(.leading, 4)
                    
                    Spacer()
                }
                .padding(.horizontal, 4)
                
                // Message content with cursor
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        FormattedStreamingText(content: content, colorScheme: colorScheme)
                            .textSelection(.enabled)
                        
                        // Typing cursor
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: 2, height: 20)
                            .opacity(cursorVisible ? 1 : 0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(), value: cursorVisible)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Material.ultraThickMaterial)
                        .shadow(color: Color.green.opacity(0.2), radius: 6, x: 0, y: 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.green.opacity(0.4), lineWidth: 1)
                        )
                )
            }
            .frame(maxWidth: .infinity * 0.8, alignment: .leading)
            
            Spacer()
        }
        .onAppear {
            cursorVisible = true
        }
    }
}

// MARK: - Formatted Text Views
struct FormattedText: View {
    let content: String
    let colorScheme: ColorScheme
    
    var body: some View {
        Text(ResponseFormatter.shared.formatResponse(content, colorScheme: colorScheme))
            .font(.system(.body, design: .rounded))
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
    }
}

struct FormattedStreamingText: View {
    let content: String
    let colorScheme: ColorScheme
    
    var body: some View {
        Text(ResponseFormatter.shared.formatStreamingResponse(content, colorScheme: colorScheme))
            .font(.system(.body, design: .rounded))
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
    }
}

// MARK: - Enhanced Message Actions
struct MessageActionsView: View {
    let message: ChatMessage
    @Binding var showCopyOptions: Bool
    @State private var showingCopyConfirmation = false
    @State private var codeBlocks: [CodeBlock] = []
    
    var body: some View {
        HStack(spacing: 8) {
            // Copy entire message button
            Button(action: { copyEntireMessage() }) {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(ActionButtonStyle())
            
            // Copy code blocks button (if any exist)
            if !codeBlocks.isEmpty {
                Menu {
                    ForEach(codeBlocks) { codeBlock in
                        Button("Copy \(codeBlock.displayName) Code") {
                            copyCodeBlock(codeBlock)
                        }
                    }
                } label: {
                    Image(systemName: "curlybraces")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(ActionButtonStyle())
            }
            
            // Share button
            Button(action: shareMessage) {
                Image(systemName: "square.and.arrow.up")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(ActionButtonStyle())
        }
        .opacity(0.8)
        .overlay(
            Text("Copied!")
                .font(.caption2)
                .foregroundColor(.green)
                .opacity(showingCopyConfirmation ? 1 : 0)
                .scaleEffect(showingCopyConfirmation ? 1 : 0.8)
                .animation(.spring(response: 0.3), value: showingCopyConfirmation)
                .offset(y: -25)
        )
        .onAppear {
            codeBlocks = ResponseFormatter.shared.extractCodeBlocks(message.content)
        }
    }
    
    private func copyEntireMessage() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = message.content
        #endif
        
        showCopyConfirmation()
    }
    
    private func copyCodeBlock(_ codeBlock: CodeBlock) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(codeBlock.code, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = codeBlock.code
        #endif
        
        showCopyConfirmation()
    }
    
    private func showCopyConfirmation() {
        withAnimation {
            showingCopyConfirmation = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showingCopyConfirmation = false
            }
        }
    }
    
    private func shareMessage() {
        // Implementation for sharing functionality
        // This would typically present a share sheet
    }
}

// MARK: - Message Actions Overlay
struct MessageActionsOverlay: View {
    let message: ChatMessage
    @State private var showingCopyConfirmation = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Copy button
            Button(action: copyMessage) {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(ActionButtonStyle())
            
            // Share button (if needed)
            Button(action: shareMessage) {
                Image(systemName: "square.and.arrow.up")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(ActionButtonStyle())
        }
        .opacity(0.8)
        .overlay(
            Text("Copied!")
                .font(.caption2)
                .foregroundColor(.green)
                .opacity(showingCopyConfirmation ? 1 : 0)
                .scaleEffect(showingCopyConfirmation ? 1 : 0.8)
                .animation(.spring(response: 0.3), value: showingCopyConfirmation)
                .offset(y: -25)
        )
    }
    
    private func copyMessage() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = message.content
        #endif
        
        // Show confirmation
        withAnimation {
            showingCopyConfirmation = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showingCopyConfirmation = false
            }
        }
    }
    
    private func shareMessage() {
        // Implementation for sharing functionality
        // This would typically present a share sheet
    }
}

// MARK: - Action Button Style
struct ActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(6)
            .background(
                Circle()
                    .fill(Material.thinMaterial)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Preview
#Preview("User Message") {
    MessageCard(
        message: ChatMessage(
            role: .user,
            content: "This is a sample user message to demonstrate the card design with longer content that might wrap to multiple lines."
        )
    )
    .environmentObject(ThemeManager())
    .padding()
    .background(Color.black.opacity(0.8))
}

#Preview("Assistant Message with Formatting") {
    MessageCard(
        message: ChatMessage(
            role: .assistant,
            content: "# Sample Response\n\nThis is a **formatted** assistant response that demonstrates:\n\n- *Italic text*\n- **Bold text**\n- `inline code`\n\n```swift\nfunc example() {\n    print(\"Hello, World!\")\n}\n```\n\n> This is a blockquote example\n\nAnd here's a [link](https://example.com) for demonstration."
        )
    )
    .environmentObject(ThemeManager())
    .padding()
    .background(Color.black.opacity(0.8))
}

#Preview("Streaming Message") {
    StreamingMessageCard(content: "This is streaming content being typed in real time...")
        .environmentObject(ThemeManager())
        .padding()
        .background(Color.black.opacity(0.8))
}