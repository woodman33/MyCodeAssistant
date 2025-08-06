import SwiftUI

// MARK: - Input Bar
struct InputBar: View {
    @Binding var currentProvider: LLMProvider?
    let isLoading: Bool
    let onSendMessage: (String) -> Void
    
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var messageText = ""
    @State private var showingProviderPicker = false
    @State private var isTextFieldFocused = false
    @FocusState private var textFieldIsFocused: Bool
    
    private let maxMessageLength = 4000
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator for loading
            if isLoading {
                ProgressView()
                    .progressViewStyle(LinearProgressViewStyle(tint: themeManager.accentColor.color))
                    .padding(.horizontal, 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
            
            // Main input bar
            HStack(spacing: 12) {
                // Provider selector
                providerSelector
                
                // Text input field
                textInputField
                
                // Send button
                sendButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(inputBarBackground)
        }
        .animation(.easeInOut(duration: 0.2), value: isLoading)
        .onAppear {
            textFieldIsFocused = true
        }
    }
    
    // MARK: - Provider Selector
    private var providerSelector: some View {
        Menu {
            ForEach(LLMProvider.allCases) { provider in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentProvider = provider
                    }
                }) {
                    HStack {
                        Text(provider.displayName)
                        Spacer()
                        if currentProvider == provider {
                            Image(systemName: "checkmark")
                                .foregroundColor(themeManager.accentColor.color)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                // Provider icon
                Circle()
                    .fill(providerStatusColor)
                    .frame(width: 8, height: 8)
                
                // Provider name
                Text(currentProvider?.displayName ?? "Select Provider")
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // Dropdown arrow
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Material.thickMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(metalBorder, lineWidth: 1)
                    )
            )
        }
        .menuStyle(BorderlessButtonMenuStyle())
    }
    
    // MARK: - Text Input Field
    private var textInputField: some View {
        ZStack(alignment: .leading) {
            // Background
            RoundedRectangle(cornerRadius: 20)
                .fill(Material.thickMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            textFieldIsFocused ? themeManager.accentColor.color.opacity(0.6) : metalBorder,
                            lineWidth: textFieldIsFocused ? 1.5 : 1
                        )
                )
                .shadow(
                    color: textFieldIsFocused ? themeManager.accentColor.color.opacity(0.3) : .clear,
                    radius: textFieldIsFocused ? 4 : 0
                )
                .animation(.easeInOut(duration: 0.2), value: textFieldIsFocused)
            
            // Text field
            HStack {
                TextField("Type your message...", text: $messageText, axis: .vertical)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(.body, design: .rounded))
                    .focused($textFieldIsFocused)
                    .lineLimit(1...6)
                    .onSubmit {
                        sendMessage()
                    }
                    .onChange(of: messageText) { newValue in
                        // Limit message length
                        if newValue.count > maxMessageLength {
                            messageText = String(newValue.prefix(maxMessageLength))
                        }
                    }
                
                // Character count (when approaching limit)
                if messageText.count > maxMessageLength * 3 / 4 {
                    Text("\(messageText.count)/\(maxMessageLength)")
                        .font(.caption2)
                        .foregroundColor(messageText.count >= maxMessageLength ? .red : .secondary)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
    
    // MARK: - Send Button
    private var sendButton: some View {
        Button(action: sendMessage) {
            Group {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                }
            }
            .foregroundColor(.white)
            .frame(width: 40, height: 40)
            .background(
                Circle()
                    .fill(
                        canSendMessage ? 
                        LinearGradient(
                            colors: [
                                themeManager.accentColor.color,
                                themeManager.accentColor.color.opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) : 
                        LinearGradient(
                            colors: [Color.gray, Color.gray],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(
                        color: canSendMessage ? themeManager.accentColor.color.opacity(0.4) : .clear,
                        radius: canSendMessage ? 4 : 0,
                        y: canSendMessage ? 2 : 0
                    )
            )
        }
        .disabled(!canSendMessage)
        .buttonStyle(MetallicButtonStyle())
        .scaleEffect(canSendMessage ? 1.0 : 0.9)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canSendMessage)
    }
    
    // MARK: - Background
    private var inputBarBackground: some View {
        Rectangle()
            .fill(Material.ultraThickMaterial)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(metalBorder)
                    .opacity(0.3),
                alignment: .top
            )
            .ignoresSafeArea()
    }
    
    // MARK: - Computed Properties
    private var canSendMessage: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && 
        !isLoading && 
        currentProvider != nil
    }
    
    private var providerStatusColor: Color {
        guard let provider = currentProvider else { return .gray }
        
        // This would integrate with the ProviderFactory to check if provider is available
        // For now, showing as available if provider is selected
        return themeManager.accentColor.color
    }
    
    private var metalBorder: Color {
        Color.primary.opacity(0.2)
    }
    
    // MARK: - Actions
    private func sendMessage() {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        
        onSendMessage(trimmedMessage)
        
        // Clear input with animation
        withAnimation(.easeOut(duration: 0.2)) {
            messageText = ""
        }
        
        // Refocus text field
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            textFieldIsFocused = true
        }
    }
}

// MARK: - Metallic Button Style
struct MetallicButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .brightness(configuration.isPressed ? -0.1 : 0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Provider Status Indicator
struct ProviderStatusIndicator: View {
    let provider: LLMProvider
    let isAvailable: Bool
    @EnvironmentObject private var themeManager: ThemeManager
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                )
            
            Text(provider.displayName)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(isAvailable ? .primary : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Material.thinMaterial)
                .opacity(isAvailable ? 1.0 : 0.6)
        )
    }
    
    private var statusColor: Color {
        if isAvailable {
            return themeManager.accentColor.color
        } else {
            return .gray
        }
    }
}

// MARK: - Advanced Input Features
struct AdvancedInputBar: View {
    @Binding var currentProvider: LLMProvider?
    let isLoading: Bool
    let onSendMessage: (String) -> Void
    let onAttachFile: (() -> Void)?
    let onVoiceInput: (() -> Void)?
    
    @State private var messageText = ""
    @State private var showingAdvancedOptions = false
    @FocusState private var textFieldIsFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Advanced options panel
            if showingAdvancedOptions {
                advancedOptionsPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Main input bar
            HStack(spacing: 12) {
                // More options button
                Button(action: { 
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showingAdvancedOptions.toggle()
                    }
                }) {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(showingAdvancedOptions ? 90 : 0))
                }
                .buttonStyle(GlassButtonStyle())
                
                // Text input (same as basic version)
                textInputArea
                
                // Send button (same as basic version)
                sendButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Material.ultraThickMaterial)
        .animation(.easeInOut(duration: 0.3), value: showingAdvancedOptions)
    }
    
    private var advancedOptionsPanel: some View {
        HStack(spacing: 16) {
            // File attachment
            if let onAttachFile = onAttachFile {
                Button(action: onAttachFile) {
                    VStack(spacing: 4) {
                        Image(systemName: "paperclip")
                        Text("Attach")
                            .font(.caption2)
                    }
                }
                .buttonStyle(AdvancedOptionButtonStyle())
            }
            
            // Voice input
            if let onVoiceInput = onVoiceInput {
                Button(action: onVoiceInput) {
                    VStack(spacing: 4) {
                        Image(systemName: "mic")
                        Text("Voice")
                            .font(.caption2)
                    }
                }
                .buttonStyle(AdvancedOptionButtonStyle())
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Material.thinMaterial)
    }
    
    private var textInputArea: some View {
        // Implementation similar to basic InputBar textInputField
        TextField("Type your message...", text: $messageText)
            .textFieldStyle(RoundedBorderTextFieldStyle())
    }
    
    private var sendButton: some View {
        // Implementation similar to basic InputBar sendButton
        Button(action: {}) {
            Image(systemName: "paperplane.fill")
        }
    }
}

// MARK: - Advanced Option Button Style
struct AdvancedOptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Material.ultraThinMaterial)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Preview
#Preview {
    VStack {
        Spacer()
        
        InputBar(
            currentProvider: .constant(.openAI),
            isLoading: false,
            onSendMessage: { message in
                print("Sending: \(message)")
            }
        )
        .environmentObject(ThemeManager())
    }
    .background(Color.black.opacity(0.8))
}

#Preview("Loading State") {
    VStack {
        Spacer()
        
        InputBar(
            currentProvider: .constant(.openAI),
            isLoading: true,
            onSendMessage: { _ in }
        )
        .environmentObject(ThemeManager())
    }
    .background(Color.black.opacity(0.8))
}