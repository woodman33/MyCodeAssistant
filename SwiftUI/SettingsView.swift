import SwiftUI

// MARK: - Settings View
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var settingsManager: SettingsManager
    @StateObject private var apiKeyManager = APIKeyManager()
    
    @State private var selectedProvider: LLMProvider = .openAI
    @State private var apiKeyInput = ""
    @State private var showingApiKeyField = false
    @State private var saveStatus: SaveStatus = .none
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                backgroundView
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerView
                        
                        // Theme Settings
                        themeSection
                        
                        // API Keys Section
                        apiKeysSection
                        
                        // Advanced Settings
                        advancedSection
                        
                        Spacer(minLength: 50)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            loadCurrentApiKey()
        }
    }
    
    // MARK: - Background
    private var backgroundView: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.95),
                Color.black.opacity(0.85),
                Color.black.opacity(0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(GlassButtonStyle())
            
            Spacer()
            
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Spacer()
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(AccentButtonStyle())
        }
    }
    
    // MARK: - Theme Section
    private var themeSection: some View {
        SettingsSection(title: "Appearance") {
            VStack(spacing: 16) {
                // Theme selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Theme")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            ThemeOption(
                                theme: theme,
                                isSelected: themeManager.currentTheme == theme
                            ) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    themeManager.setTheme(theme)
                                }
                            }
                        }
                    }
                }
                
                // Accent color selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accent Color")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(AccentColor.allCases, id: \.self) { color in
                            AccentColorOption(
                                accentColor: color,
                                isSelected: themeManager.accentColor == color
                            ) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    themeManager.setAccentColor(color)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - API Keys Section
    private var apiKeysSection: some View {
        SettingsSection(title: "API Keys") {
            VStack(spacing: 16) {
                // Provider selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Provider")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Picker("Provider", selection: $selectedProvider) {
                        ForEach(LLMProvider.allCases) { provider in
                            HStack {
                                Text(provider.displayName)
                                Spacer()
                                if apiKeyManager.hasAPIKey(for: provider) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .tag(provider)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Material.thickMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                            )
                    )
                    .onChange(of: selectedProvider) { _ in
                        loadCurrentApiKey()
                    }
                }
                
                // API Key input
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("API Key")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button(showingApiKeyField ? "Hide" : "Show") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingApiKeyField.toggle()
                            }
                        }
                        .font(.caption)
                        .buttonStyle(GlassButtonStyle())
                    }
                    
                    if showingApiKeyField {
                        VStack(spacing: 12) {
                            SecureField("Enter API key...", text: $apiKeyInput)
                                .textFieldStyle(CustomTextFieldStyle())
                                .transition(.scale.combined(with: .opacity))
                            
                            HStack(spacing: 12) {
                                Button("Save") {
                                    saveApiKey()
                                }
                                .buttonStyle(AccentButtonStyle())
                                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                
                                if apiKeyManager.hasAPIKey(for: selectedProvider) {
                                    Button("Delete") {
                                        deleteApiKey()
                                    }
                                    .buttonStyle(DestructiveButtonStyle())
                                }
                            }
                        }
                    }
                    
                    // Status indicator
                    statusIndicatorView
                }
            }
        }
    }
    
    // MARK: - Advanced Section
    private var advancedSection: some View {
        SettingsSection(title: "Advanced") {
            VStack(spacing: 16) {
                // Temperature setting
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Temperature")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(String(format: "%.1f", settingsManager.appSettings.temperature))
                            .font(.caption)
                            .foregroundColor(themeManager.accentColor.color)
                            .fontWeight(.semibold)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { settingsManager.appSettings.temperature },
                            set: { newValue in
                                let newSettings = AppSettings(
                                    defaultProvider: settingsManager.appSettings.defaultProvider,
                                    defaultModel: settingsManager.appSettings.defaultModel,
                                    temperature: newValue,
                                    maxTokens: settingsManager.appSettings.maxTokens,
                                    systemPrompt: settingsManager.appSettings.systemPrompt,
                                    autoSave: settingsManager.appSettings.autoSave,
                                    theme: settingsManager.appSettings.theme,
                                    apiTimeoutSeconds: settingsManager.appSettings.apiTimeoutSeconds,
                                    retryAttempts: settingsManager.appSettings.retryAttempts,
                                    enableLogging: settingsManager.appSettings.enableLogging
                                )
                                settingsManager.updateSettings(newSettings)
                            }
                        ),
                        in: 0.0...2.0,
                        step: 0.1
                    )
                    .accentColor(themeManager.accentColor.color)
                }
                
                // Auto-save toggle
                Toggle("Auto-save conversations", isOn: Binding(
                    get: { settingsManager.appSettings.autoSave },
                    set: { newValue in
                        let newSettings = AppSettings(
                            defaultProvider: settingsManager.appSettings.defaultProvider,
                            defaultModel: settingsManager.appSettings.defaultModel,
                            temperature: settingsManager.appSettings.temperature,
                            maxTokens: settingsManager.appSettings.maxTokens,
                            systemPrompt: settingsManager.appSettings.systemPrompt,
                            autoSave: newValue,
                            theme: settingsManager.appSettings.theme,
                            apiTimeoutSeconds: settingsManager.appSettings.apiTimeoutSeconds,
                            retryAttempts: settingsManager.appSettings.retryAttempts,
                            enableLogging: settingsManager.appSettings.enableLogging
                        )
                        settingsManager.updateSettings(newSettings)
                    }
                ))
                .toggleStyle(CustomToggleStyle())
            }
        }
    }
    
    // MARK: - Status Indicator
    private var statusIndicatorView: some View {
        Group {
            switch saveStatus {
            case .none:
                HStack(spacing: 6) {
                    Circle()
                        .fill(apiKeyManager.hasAPIKey(for: selectedProvider) ? .green : .gray)
                        .frame(width: 6, height: 6)
                    
                    Text(apiKeyManager.hasAPIKey(for: selectedProvider) ? "API key configured" : "No API key")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
            case .saving:
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    
                    Text("Saving...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
            case .saved:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    
                    Text("API key saved")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                
            case .error:
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    
                    Text(errorMessage.isEmpty ? "Failed to save" : errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .transition(.scale.combined(with: .opacity))
    }
    
    // MARK: - Methods
    private func loadCurrentApiKey() {
        do {
            apiKeyInput = try apiKeyManager.getAPIKey(for: selectedProvider) ?? ""
        } catch {
            apiKeyInput = ""
            errorMessage = error.localizedDescription
        }
    }
    
    private func saveApiKey() {
        let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            saveStatus = .saving
        }
        
        do {
            try apiKeyManager.storeAPIKey(trimmedKey, for: selectedProvider)
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                saveStatus = .saved
            }
            
            // Reset status after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    saveStatus = .none
                }
            }
            
        } catch {
            errorMessage = error.localizedDescription
            withAnimation(.easeInOut(duration: 0.2)) {
                saveStatus = .error
            }
        }
    }
    
    private func deleteApiKey() {
        do {
            try apiKeyManager.deleteAPIKey(for: selectedProvider)
            apiKeyInput = ""
            
            withAnimation(.easeInOut(duration: 0.2)) {
                saveStatus = .none
            }
            
        } catch {
            errorMessage = error.localizedDescription
            withAnimation(.easeInOut(duration: 0.2)) {
                saveStatus = .error
            }
        }
    }
}

// MARK: - Settings Section
struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            VStack(spacing: 16) {
                content
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Material.ultraThickMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            )
        }
    }
}

// MARK: - Theme Option
struct ThemeOption: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: themeIcon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .secondary)
                
                Text(theme.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue : Material.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.primary.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var themeIcon: String {
        switch theme {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .system: return "gearshape.fill"
        }
    }
}

// MARK: - Accent Color Option
struct AccentColorOption: View {
    let accentColor: AccentColor
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Circle()
                .fill(accentColor.color)
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: isSelected ? 3 : 0)
                        .scaleEffect(isSelected ? 1.2 : 1.0)
                )
                .shadow(color: accentColor.color.opacity(0.4), radius: isSelected ? 4 : 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Custom Styles
struct AccentButtonStyle: ButtonStyle {
    @EnvironmentObject private var themeManager: ThemeManager
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(themeManager.accentColor.color)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Material.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )
            )
    }
}

struct CustomToggleStyle: ToggleStyle {
    @EnvironmentObject private var themeManager: ThemeManager
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
                .font(.subheadline)
                .fontWeight(.medium)
            
            Spacer()
            
            RoundedRectangle(cornerRadius: 16)
                .fill(configuration.isOn ? themeManager.accentColor.color : Color.gray.opacity(0.3))
                .frame(width: 50, height: 30)
                .overlay(
                    Circle()
                        .fill(Color.white)
                        .shadow(radius: 2)
                        .padding(2)
                        .offset(x: configuration.isOn ? 10 : -10)
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isOn)
                .onTapGesture {
                    configuration.isOn.toggle()
                }
        }
    }
}

// MARK: - Save Status
enum SaveStatus {
    case none
    case saving
    case saved
    case error
}

// MARK: - Preview
#Preview {
    SettingsView()
        .environmentObject(ThemeManager())
        .environmentObject(SettingsManager())
        .preferredColorScheme(.dark)
}