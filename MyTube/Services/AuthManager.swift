import Foundation
import GoogleSignIn
import SwiftUI
import Combine

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = true // Default to true for splash screen
    @Published var currentUser: GIDGoogleUser?
    @Published var errorMessage: String?
    
    private let scopes = [
        "https://www.googleapis.com/auth/youtube.readonly"
    ]
    
    private init() {
        restorePreviousSignIn()
    }
    
    func restorePreviousSignIn() {
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            if let user = user {
                self?.currentUser = user
                self?.isAuthenticated = true
            } else if let error = error {
                // Not signed in or error restoring
                print("Error restoring sign in: \(error.localizedDescription)")
                self?.isAuthenticated = false
            }
            // Transition finished, hide splash screen
            withAnimation {
                self?.isLoading = false
            }
        }
    }
    
    func signIn() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            self.errorMessage = "Unable to find root view controller"
            return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController, hint: nil, additionalScopes: scopes) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                self.errorMessage = error.localizedDescription
                return
            }
            
            if let user = result?.user {
                self.currentUser = user
                self.isAuthenticated = true
            }
        }
    }
    
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        self.currentUser = nil
        self.isAuthenticated = false
    }
    
    func refreshTokens() async throws {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            throw NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No current user"])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            currentUser.refreshTokensIfNeeded { [weak self] user, error in
                guard let self = self else { return }
                
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                if let user = user {
                    self.currentUser = user
                    self.isAuthenticated = true
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(domain: "AuthManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to refresh token"]))
                }
            }
        }
    }
    
    var accessToken: String? {
        return currentUser?.accessToken.tokenString
    }
}
