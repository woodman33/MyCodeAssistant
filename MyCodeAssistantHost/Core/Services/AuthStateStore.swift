import Foundation
import SwiftUI

// MARK: - Auth State Store
/// Singleton service for caching authentication state
/// Uses AppStorage to persist sign-in status across app sessions
@MainActor
final class AuthStateStore: ObservableObject {
    
    // MARK: - Singleton
    static let shared = AuthStateStore()
    
    // MARK: - Published Properties
    @AppStorage("didSignIn") var didSignIn: Bool = false
    @AppStorage("lastSignInProvider") var lastSignInProvider: String = ""
    @AppStorage("lastSignInDate") var lastSignInTimestamp: Double = 0
    
    // Session expiry (24 hours in seconds)
    private let sessionExpiryDuration: TimeInterval = 86400
    
    // MARK: - Private Init
    private init() {
        checkSessionValidity()
    }
    
    // MARK: - Public Methods
    
    /// Mark user as signed in for a specific provider
    func setSignedIn(for provider: LLMProvider) {
        didSignIn = true
        lastSignInProvider = provider.rawValue
        lastSignInTimestamp = Date().timeIntervalSince1970
    }
    
    /// Clear authentication state
    func signOut() {
        didSignIn = false
        lastSignInProvider = ""
        lastSignInTimestamp = 0
    }
    
    /// Check if user needs to sign in
    func needsAuthentication(for provider: LLMProvider) -> Bool {
        // If never signed in
        guard didSignIn else { return true }
        
        // If different provider
        if lastSignInProvider != provider.rawValue {
            return true
        }
        
        // Check session expiry
        if isSessionExpired() {
            signOut()
            return true
        }
        
        return false
    }
    
    /// Check if the current session is still valid
    func isSessionValid() -> Bool {
        return didSignIn && !isSessionExpired()
    }
    
    // MARK: - Private Methods
    
    private func checkSessionValidity() {
        if isSessionExpired() {
            signOut()
        }
    }
    
    private func isSessionExpired() -> Bool {
        let currentTime = Date().timeIntervalSince1970
        let timeSinceSignIn = currentTime - lastSignInTimestamp
        return timeSinceSignIn > sessionExpiryDuration
    }
}

// MARK: - Extension for Provider Integration
extension AuthStateStore {
    
    /// Handle successful authentication
    func handleSuccessfulAuth(for provider: LLMProvider) {
        setSignedIn(for: provider)
    }
    
    /// Check if re-authentication is needed before API call
    func shouldPromptForAuth(provider: LLMProvider) -> Bool {
        return needsAuthentication(for: provider)
    }
    
    /// Get cached provider if available
    var cachedProvider: LLMProvider? {
        guard !lastSignInProvider.isEmpty else { return nil }
        return LLMProvider(rawValue: lastSignInProvider)
    }
}