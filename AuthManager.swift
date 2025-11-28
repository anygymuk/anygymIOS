//
//  AuthManager.swift
//  AnyGym
//
//  Created on iOS App
//

import Foundation
import Auth0
import Combine

class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var user: UserInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var credentialsManager: CredentialsManager
    private var authentication: Authentication
    private var webAuth: WebAuth
    private var domain: String
    private var clientId: String
    private var cancellables = Set<AnyCancellable>()
    private var hasCheckedAuth = false
    
    init() {
        // Get Auth0 credentials from Info.plist
        self.domain = Bundle.main.object(forInfoDictionaryKey: "Auth0Domain") as? String ?? ""
        self.clientId = Bundle.main.object(forInfoDictionaryKey: "Auth0ClientId") as? String ?? ""
        
        // Initialize Authentication and WebAuth using the domain and clientId
        self.authentication = Auth0.authentication(clientId: clientId, domain: domain)
        self.webAuth = Auth0.webAuth(clientId: clientId, domain: domain)
        
        // Initialize CredentialsManager
        self.credentialsManager = CredentialsManager(authentication: authentication)
        
        // Check if we have stored credentials
        checkAuthStatus()
    }
    
    func checkAuthStatus() {
        guard !hasCheckedAuth else { return }
        hasCheckedAuth = true
        isLoading = true
        
        credentialsManager
            .credentials()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self = self else { return }
                    if case .failure = completion {
                        self.isAuthenticated = false
                        // Don't auto-trigger login here - let LoginView handle it after delay
                        self.isLoading = false
                    }
                },
                receiveValue: { [weak self] credentials in
                    guard let self = self else { return }
                    if !credentials.accessToken.isEmpty {
                        self.isAuthenticated = true
                        self.isLoading = false
                        self.getUserInfo(accessToken: credentials.accessToken)
                    } else {
                        self.isAuthenticated = false
                        // Don't auto-trigger login here - let LoginView handle it after delay
                        self.isLoading = false
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func login() {
        isLoading = true
        errorMessage = nil
        
        webAuth
            .scope("openid profile email")
            .start { [weak self] (result: Result<Credentials, WebAuthError>) in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isLoading = false
                    switch result {
                    case .success(let credentials):
                        _ = self.credentialsManager.store(credentials: credentials)
                        self.isAuthenticated = true
                        self.getUserInfo(accessToken: credentials.accessToken)
                    case .failure(let error):
                        // Only show error if it's not a user cancellation or window scene error
                        let errorDescription = error.localizedDescription
                        let lowercased = errorDescription.lowercased()
                        if !lowercased.contains("cancelled") && 
                           !lowercased.contains("windowscene") && 
                           !lowercased.contains("not in the foreground") {
                            self.errorMessage = errorDescription
                        } else {
                            // Clear error message for cancellations and window scene errors
                            self.errorMessage = nil
                        }
                        self.isAuthenticated = false
                    }
                }
            }
    }
    
    func logout() {
        webAuth
            .clearSession { [weak self] (result: Result<Void, WebAuthError>) in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    switch result {
                    case .success:
                        _ = self.credentialsManager.revoke()
                        self.isAuthenticated = false
                        self.user = nil
                    case .failure(let error):
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
    }
    
    private func getUserInfo(accessToken: String) {
        authentication
            .userInfo(withAccessToken: accessToken)
            .start { [weak self] (result: Result<UserInfo, AuthenticationError>) in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    switch result {
                    case .success(let user):
                        self.user = user
                    case .failure(let error):
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
    }
    
    // Get Auth0 signup URL
    func getSignupURL() -> URL? {
        // Get bundle identifier for redirect URI (must match Auth0 configuration)
        let bundleId = Bundle.main.bundleIdentifier ?? "com.anygym.app"
        // Auth0 expects this exact format for native apps
        let redirectURI = "\(bundleId)://\(domain)/ios/\(bundleId)/callback"
        
        // URL encode the redirect URI
        guard let encodedRedirectURI = redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        
        // Build signup URL - using /authorize endpoint with screen_hint=signup
        // This is more reliable than /u/signup for native apps
        let signupURLString = "https://\(domain)/authorize?client_id=\(clientId)&redirect_uri=\(encodedRedirectURI)&response_type=code&scope=openid%20profile%20email&screen_hint=signup"
        
        return URL(string: signupURLString)
    }
}
