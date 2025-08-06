import SwiftUI

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