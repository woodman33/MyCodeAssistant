import SwiftUI

// MARK: - MyCodeAssistant App
@main
struct MyCodeAssistantApp: App {
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var settingsManager = UISettingsManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeManager)
                .environmentObject(settingsManager)
                .preferredColorScheme(themeManager.colorScheme)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .windowResizability(.contentSize)
    }
}

// MARK: - Theme Manager
class ThemeManager: ObservableObject {
    @Published var currentTheme: AppTheme = .system
    @Published var accentColor: AccentColor = .blue
    
    var colorScheme: ColorScheme? {
        switch currentTheme {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return nil
        }
    }
    
    func setTheme(_ theme: AppTheme) {
        currentTheme = theme
    }
    
    func setAccentColor(_ color: AccentColor) {
        accentColor = color
    }
}

// MARK: - UI Settings Manager  
class UIUISettingsManager: ObservableObject {
    @Published var appSettings: AppSettings = .default
    @Published var isFirstLaunch = true
    
    private let settingsKey = "app_settings"
    
    init() {
        loadSettings()
    }
    
    func updateSettings(_ settings: AppSettings) {
        appSettings = settings
        saveSettings()
    }
    
    private func saveSettings() {
        if let data = try? JSONEncoder().encode(appSettings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }
    
    private func loadSettings() {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return
        }
        appSettings = settings
        isFirstLaunch = false
    }
}

// MARK: - Accent Color Options
enum AccentColor: String, CaseIterable {
    case blue = "blue"
    case green = "green"
    case orange = "orange"
    case red = "red"
    case purple = "purple"
    case pink = "pink"
    case indigo = "indigo"
    case teal = "teal"
    case cyan = "cyan"
    case mint = "mint"
    
    var color: Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .purple: return .purple
        case .pink: return .pink
        case .indigo: return .indigo
        case .teal: return .teal
        case .cyan: return .cyan
        case .mint: return .mint
        }
    }
    
    var displayName: String {
        switch self {
        case .blue: return "Blue"
        case .green: return "Green"
        case .orange: return "Orange"
        case .red: return "Red"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .indigo: return "Indigo"
        case .teal: return "Teal"
        case .cyan: return "Cyan"
        case .mint: return "Mint"
        }
    }
}