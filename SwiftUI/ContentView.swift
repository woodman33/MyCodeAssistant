import SwiftUI

// MARK: - Content View
struct ContentView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var settingsManager: SettingsManager
    @StateObject private var viewModel = ChatViewModel()
    @State private var showingSettings = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                backgroundGradient
                
                VStack(spacing: 0) {
                    // Header
                    headerView
                    
                    // Messages area
                    messagesScrollView
                    
                    // Input bar
                    inputBar
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(themeManager)
                .environmentObject(settingsManager)
        }
        .onAppear {
            viewModel.initialize(with: settingsManager.appSettings)
        }
    }
    
    // MARK: - Background
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.9),
                Color.black.opacity(0.7),
                Color.black.opacity(0.9)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            Text("MyCodeAssistant")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Provider indicator
            if let currentProvider = viewModel.currentProvider {
                HStack(spacing: 4) {
                    Circle()
                        .fill(themeManager.accentColor.color)
                        .frame(width: 6, height: 6)
                    
                    Text(currentProvider.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Material.ultraThinMaterial)
                )
            }
            
            // Settings button
            Button(action: { showingSettings = true }) {
                Image(systemName: "gear")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(GlassButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(Material.ultraThickMaterial)
                .ignoresSafeArea()
        )
    }
    
    // MARK: - Messages Scroll View
    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        MessageCard(message: message)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                removal: .scale(scale: 0.8).combined(with: .opacity)
                            ))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.messages.count) { _ in
                if let lastMessage = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Input Bar
    private var inputBar: some View {
        InputBar(
            currentProvider: $viewModel.currentProvider,
            isLoading: viewModel.isLoading,
            onSendMessage: { message in
                Task {
                    await viewModel.sendMessage(message)
                }
            }
        )
        .environmentObject(themeManager)
    }
}

// MARK: - Glass Button Style
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
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
    ContentView()
        .environmentObject(ThemeManager())
        .environmentObject(SettingsManager())
        .preferredColorScheme(.dark)
}