import XCTest
import SwiftUI
@testable import MyCodeAssistantCore

// MARK: - Auth State Store Tests
@MainActor
final class AuthStateStoreTests: XCTestCase {
    
    var authStore: AuthStateStore!
    
    override func setUp() {
        super.setUp()
        // Create a fresh instance for testing
        authStore = AuthStateStore.shared
        // Clear any existing state
        authStore.signOut()
    }
    
    override func tearDown() {
        authStore.signOut()
        authStore = nil
        super.tearDown()
    }
    
    // MARK: - Basic Authentication Tests
    
    func testInitialStateNeedsAuthentication() {
        // Initially should need authentication for all providers
        XCTAssertTrue(authStore.needsAuthentication(for: .openAI),
                     "Should need authentication initially for OpenAI")
        XCTAssertTrue(authStore.needsAuthentication(for: .openRouter),
                     "Should need authentication initially for OpenRouter")
        // Edge provider doesn't require authentication
        XCTAssertFalse(authStore.needsAuthentication(for: .edge),
                      "Edge provider should not need authentication")
        XCTAssertFalse(authStore.isSessionValid(),
                      "Session should be invalid initially")
    }
    
    func testSignInPersistsState() {
        // Sign in for OpenAI
        authStore.setSignedIn(for: .openAI)
        
        // Should not need authentication for OpenAI
        XCTAssertFalse(authStore.needsAuthentication(for: .openAI), 
                      "Should not need authentication after sign in")
        XCTAssertTrue(authStore.isSessionValid(), 
                     "Session should be valid after sign in")
        
        // Should still need authentication for different provider
        XCTAssertTrue(authStore.needsAuthentication(for: .openRouter), 
                     "Different provider should still need authentication")
        
        // Verify persistence properties
        XCTAssertTrue(authStore.didSignIn, "didSignIn should be true")
        XCTAssertEqual(authStore.lastSignInProvider, LLMProvider.openAI.rawValue, 
                      "Last provider should be OpenAI")
        XCTAssertGreaterThan(authStore.lastSignInTimestamp, 0, 
                           "Timestamp should be set")
    }
    
    func testSignOutClearsState() {
        // Sign in first
        authStore.setSignedIn(for: .openAI)
        XCTAssertFalse(authStore.needsAuthentication(for: .openAI), 
                      "Should be signed in")
        
        // Sign out
        authStore.signOut()
        
        // Should need authentication again
        XCTAssertTrue(authStore.needsAuthentication(for: .openAI), 
                     "Should need authentication after sign out")
        XCTAssertFalse(authStore.isSessionValid(), 
                      "Session should be invalid after sign out")
        
        // Verify state is cleared
        XCTAssertFalse(authStore.didSignIn, "didSignIn should be false")
        XCTAssertEqual(authStore.lastSignInProvider, "", 
                      "Provider should be cleared")
        XCTAssertEqual(authStore.lastSignInTimestamp, 0, 
                      "Timestamp should be cleared")
    }
    
    // MARK: - 24-Hour Expiry Tests
    
    func testSessionExpiryAfter24Hours() {
        // Set signed in with timestamp 25 hours ago
        authStore.didSignIn = true
        authStore.lastSignInProvider = LLMProvider.openAI.rawValue
        authStore.lastSignInTimestamp = Date().timeIntervalSince1970 - (25 * 3600)
        
        // Should need authentication due to expiry
        XCTAssertTrue(authStore.needsAuthentication(for: .openAI), 
                     "Should need authentication after 24 hours")
        XCTAssertFalse(authStore.isSessionValid(), 
                      "Session should be invalid after 24 hours")
    }
    
    func testSessionValidWithin24Hours() {
        // Set signed in with timestamp 23 hours ago
        authStore.didSignIn = true
        authStore.lastSignInProvider = LLMProvider.openAI.rawValue
        authStore.lastSignInTimestamp = Date().timeIntervalSince1970 - (23 * 3600)
        
        // Should not need authentication within 24 hours
        XCTAssertFalse(authStore.needsAuthentication(for: .openAI), 
                      "Should not need authentication within 24 hours")
        XCTAssertTrue(authStore.isSessionValid(), 
                     "Session should be valid within 24 hours")
    }
    
    func testSessionExpiryAtExactly24Hours() {
        // Test boundary condition: the implementation uses > not >= for expiry check
        authStore.didSignIn = true
        authStore.lastSignInProvider = LLMProvider.openAI.rawValue
        
        // Test at 24 hours minus 1 second (should NOT be expired)
        authStore.lastSignInTimestamp = Date().timeIntervalSince1970 - (24 * 3600 - 1)
        XCTAssertFalse(authStore.needsAuthentication(for: .openAI),
                      "Should NOT need authentication at 23:59:59")
        
        // Test at 24 hours plus 1 second (should be expired)
        authStore.lastSignInTimestamp = Date().timeIntervalSince1970 - (24 * 3600 + 1)
        XCTAssertTrue(authStore.needsAuthentication(for: .openAI),
                      "Should need authentication at 24:00:01")
    }
    
    // MARK: - Provider Switching Tests
    
    func testSwitchingProviderRequiresNewAuth() {
        // Sign in for OpenAI
        authStore.setSignedIn(for: .openAI)
        
        // Should not need auth for OpenAI
        XCTAssertFalse(authStore.needsAuthentication(for: .openAI), 
                      "Should not need auth for signed-in provider")
        
        // Should need auth for different provider
        XCTAssertTrue(authStore.needsAuthentication(for: .openRouter), 
                     "Should need auth for different provider")
        
        // Sign in for OpenRouter
        authStore.setSignedIn(for: .openRouter)
        
        // Now should not need auth for OpenRouter
        XCTAssertFalse(authStore.needsAuthentication(for: .openRouter), 
                      "Should not need auth after signing in to new provider")
        
        // But now should need auth for OpenAI (provider changed)
        XCTAssertTrue(authStore.needsAuthentication(for: .openAI), 
                     "Should need auth for previous provider after switching")
    }
    
    // MARK: - Helper Method Tests
    
    func testHandleSuccessfulAuth() {
        // Use helper method to handle successful auth
        authStore.handleSuccessfulAuth(for: .openAI)
        
        // Should be signed in
        XCTAssertFalse(authStore.needsAuthentication(for: .openAI), 
                      "Should not need auth after successful auth")
        XCTAssertTrue(authStore.isSessionValid(), 
                     "Session should be valid")
        XCTAssertEqual(authStore.lastSignInProvider, LLMProvider.openAI.rawValue, 
                      "Provider should be set")
    }
    
    func testShouldPromptForAuth() {
        // Initially should prompt
        XCTAssertTrue(authStore.shouldPromptForAuth(provider: .openAI), 
                     "Should prompt for auth initially")
        
        // After signing in, should not prompt
        authStore.handleSuccessfulAuth(for: .openAI)
        XCTAssertFalse(authStore.shouldPromptForAuth(provider: .openAI), 
                      "Should not prompt after auth")
    }
    
    func testCachedProvider() {
        // Initially no cached provider
        XCTAssertNil(authStore.cachedProvider, 
                    "Should have no cached provider initially")
        
        // After signing in, should have cached provider
        authStore.setSignedIn(for: .openRouter)
        XCTAssertEqual(authStore.cachedProvider, .openRouter, 
                      "Should cache the signed-in provider")
        
        // After signing out, should have no cached provider
        authStore.signOut()
        XCTAssertNil(authStore.cachedProvider, 
                    "Should clear cached provider after sign out")
    }
}

// MARK: - Performance Tests
extension AuthStateStoreTests {
    
    func testAuthCheckPerformance() {
        // Measure performance of authentication check
        authStore.setSignedIn(for: .openAI)
        
        measure {
            for _ in 0..<1000 {
                _ = authStore.needsAuthentication(for: .openAI)
            }
        }
    }
    
    func testSessionValidityCheckPerformance() {
        // Measure performance of session validity check
        authStore.setSignedIn(for: .openAI)
        
        measure {
            for _ in 0..<1000 {
                _ = authStore.isSessionValid()
            }
        }
    }
}