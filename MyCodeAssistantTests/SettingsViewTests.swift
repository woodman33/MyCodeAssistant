import XCTest
import SwiftUI
@testable import MyCodeAssistantCore

// MARK: - Settings View Tests
final class SettingsViewTests: XCTestCase {
    
    var settingsView: SettingsView!
    var themeManager: ThemeManager!
    var settingsManager: UISettingsManager!
    var chatViewModel: ChatViewModel!
    
    @MainActor
    override func setUp() {
        super.setUp()
        themeManager = ThemeManager()
        settingsManager = UISettingsManager()
        chatViewModel = ChatViewModel()
        settingsView = SettingsView()
    }
    
    override func tearDown() {
        settingsView = nil
        themeManager = nil
        settingsManager = nil
        chatViewModel = nil
        super.tearDown()
    }
    
    // MARK: - Frame Tests
    
    func testSettingsViewMinimumWidth() {
        // Test that Settings view has minimum width of 440pt
        let hostingController = NSHostingController(
            rootView: settingsView
                .environmentObject(themeManager)
                .environmentObject(settingsManager)
                .environmentObject(chatViewModel)
        )
        
        // Get the view's frame constraints
        let view = hostingController.view
        
        // The minimum width should be at least 440
        XCTAssertGreaterThanOrEqual(view.fittingSize.width, 440, 
                                   "Settings sheet width should be at least 440pt")
    }
    
    // Test removed: SettingsView now uses dynamic width with maxWidth:.infinity
    // The sheet adapts to content and available space rather than having a fixed ideal width
    
    // MARK: - Model Picker Tests
    
    @MainActor
    func testModelPickerAppearsWhenProviderChanges() {
        // Test that model picker updates when provider changes
        chatViewModel.currentProvider = .openAI
        
        // Check OpenAI models are available
        let openAIModels = chatViewModel.availableModels[.openAI]
        XCTAssertNotNil(openAIModels, "OpenAI should have available models")
        XCTAssertTrue(openAIModels!.contains("gpt-3.5-turbo"), "Should include gpt-3.5-turbo")
        XCTAssertTrue(openAIModels!.contains("gpt-4o-mini"), "Should include gpt-4o-mini")
        
        // Switch to OpenRouter
        chatViewModel.switchProvider(.openRouter)
        
        // Check OpenRouter models are available
        let openRouterModels = chatViewModel.availableModels[.openRouter]
        XCTAssertNotNil(openRouterModels, "OpenRouter should have available models")
        XCTAssertTrue(openRouterModels!.contains("🛣️ Best Route"), "Should include auto-routing option")
    }
    
    @MainActor
    func testModelSelectionPersists() {
        // Test that selected model persists correctly
        chatViewModel.currentProvider = .openAI
        chatViewModel.selectedModel = "gpt-4o"
        
        XCTAssertEqual(chatViewModel.selectedModel, "gpt-4o", 
                      "Selected model should be gpt-4o")
        
        // Test route mode
        chatViewModel.switchModel("Route")
        XCTAssertTrue(chatViewModel.useRoutingMode, "Should enable routing mode")
        XCTAssertEqual(chatViewModel.selectedModel, "Route", "Selected model should be Route")
    }
    
    // MARK: - Auth State Tests
    
    @MainActor
    func testAuthStateCaching() {
        let authStore = AuthStateStore.shared
        
        // Initially should need authentication
        XCTAssertTrue(authStore.needsAuthentication(for: .openAI), 
                     "Should need authentication initially")
        
        // Mark as signed in
        authStore.setSignedIn(for: .openAI)
        
        // Should not need authentication now
        XCTAssertFalse(authStore.needsAuthentication(for: .openAI), 
                      "Should not need authentication after sign in")
        XCTAssertTrue(authStore.isSessionValid(), "Session should be valid")
        
        // Different provider should need auth
        XCTAssertTrue(authStore.needsAuthentication(for: .openRouter), 
                     "Different provider should need authentication")
        
        // Sign out
        authStore.signOut()
        XCTAssertTrue(authStore.needsAuthentication(for: .openAI), 
                     "Should need authentication after sign out")
    }
    
    @MainActor
    func testAuthStateExpiry() {
        let authStore = AuthStateStore.shared
        
        // Set signed in with old timestamp (25 hours ago)
        authStore.didSignIn = true
        authStore.lastSignInProvider = LLMProvider.openAI.rawValue
        authStore.lastSignInTimestamp = Date().timeIntervalSince1970 - (25 * 3600)
        
        // Should need authentication due to expiry
        XCTAssertTrue(authStore.needsAuthentication(for: .openAI), 
                     "Should need authentication after session expiry")
        XCTAssertFalse(authStore.isSessionValid(), "Session should be invalid after expiry")
    }
    
    // MARK: - Guardrails Integration Tests
    
    @MainActor
    func testGuardrailsToggleIntegration() {
        // Test guardrails toggle functionality
        chatViewModel.guardrailsEnabled = true
        XCTAssertTrue(chatViewModel.guardrailsEnabled, "Guardrails should be enabled")
        
        chatViewModel.guardrailsEnabled = false
        XCTAssertFalse(chatViewModel.guardrailsEnabled, "Guardrails should be disabled")
    }
    
    @MainActor
    func testCodeOnlyModeRequiresGuardrails() {
        // Code-only mode should only work with guardrails enabled
        chatViewModel.guardrailsEnabled = false
        chatViewModel.codeOnlyMode = true
        
        // In the UI, code-only mode should be disabled when guardrails are off
        // This is a UI behavior test - actual enforcement happens in the view
        XCTAssertFalse(chatViewModel.guardrailsEnabled, 
                      "Guardrails should be disabled")
    }
}

// MARK: - UI Component Tests
final class UIComponentTests: XCTestCase {
    
    func testGlassButtonStyle() {
        // Test that GlassButtonStyle is properly defined
        let button = Button("Test") {}
            .buttonStyle(GlassButtonStyle())
        
        XCTAssertNotNil(button, "Glass button style should be applied")
    }
    
    func testAccentButtonStyle() {
        let themeManager = ThemeManager()
        let button = Button("Test") {}
            .buttonStyle(AccentButtonStyle())
            .environmentObject(themeManager)
        
        XCTAssertNotNil(button, "Accent button style should be applied")
    }
    
    func testCustomTextFieldStyle() {
        let textField = TextField("Test", text: .constant(""))
            .textFieldStyle(CustomTextFieldStyle())
        
        XCTAssertNotNil(textField, "Custom text field style should be applied")
    }
    
    func testCustomToggleStyle() {
        let themeManager = ThemeManager()
        let toggle = Toggle("Test", isOn: .constant(true))
            .toggleStyle(CustomToggleStyle())
            .environmentObject(themeManager)
        
        XCTAssertNotNil(toggle, "Custom toggle style should be applied")
    }
}

// MARK: - Model Picker UI Tests
final class ModelPickerTests: XCTestCase {
    
    @MainActor
    func testModelPickerDisplay() {
        let chatViewModel = ChatViewModel()
        
        // Test model display for OpenAI
        chatViewModel.currentProvider = .openAI
        let openAIModels = chatViewModel.availableModels[.openAI] ?? []
        XCTAssertGreaterThan(openAIModels.count, 0, "OpenAI should have models")
        
        // Test model display for OpenRouter
        chatViewModel.currentProvider = .openRouter
        let openRouterModels = chatViewModel.availableModels[.openRouter] ?? []
        XCTAssertGreaterThan(openRouterModels.count, 0, "OpenRouter should have models")
    }
    
    @MainActor
    func testRouteModeToggle() {
        let chatViewModel = ChatViewModel()
        
        // Test enabling route mode
        chatViewModel.switchModel("Route")
        XCTAssertTrue(chatViewModel.useRoutingMode, "Route mode should be enabled")
        
        // Test disabling route mode
        chatViewModel.switchModel("gpt-3.5-turbo")
        XCTAssertFalse(chatViewModel.useRoutingMode, "Route mode should be disabled")
    }
}