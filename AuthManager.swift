//
//  AuthManager.swift
//  AnyGym
//
//  Created on iOS App
//

import Foundation
import Auth0
import Combine

// MARK: - User Model
struct User: Codable {
    let auth0Id: String?
    let email: String?
    let fullName: String?
    let onboardingCompleted: Bool
    let addressLine1: String?
    let addressLine2: String?
    let addressCity: String?
    let addressPostcode: String?
    let dateOfBirth: String?
    let emergencyContactName: String?
    let emergencyContactNumber: String?
    let stripeCustomerId: String?
    
    enum CodingKeys: String, CodingKey {
        case auth0Id = "auth0_id"
        case email
        case fullName = "full_name"
        case onboardingCompleted = "onboarding_completed"
        case addressLine1 = "address_line1"
        case addressLine2 = "address_line2"
        case addressCity = "address_city"
        case addressPostcode = "address_postcode"
        case dateOfBirth = "date_of_birth"
        case emergencyContactName = "emergency_contact_name"
        case emergencyContactNumber = "emergency_contact_number"
        case stripeCustomerId = "stripe_customer_id"
    }
    
    // Computed property for display name (first name from full name)
    var firstName: String {
        guard let fullName = fullName, !fullName.isEmpty else {
            return "User"
        }
        return fullName.components(separatedBy: " ").first ?? fullName
    }
    
    // Computed property for location string
    var locationString: String {
        var components: [String] = []
        if let city = addressCity, !city.isEmpty {
            components.append(city)
        }
        if let postcode = addressPostcode, !postcode.isEmpty {
            components.append(postcode)
        }
        if components.isEmpty {
            return "Location not set"
        }
        // Add country if we have location data
        // For now, default to "United Kingdom" if we have UK postcode format
        if let postcode = addressPostcode, !postcode.isEmpty {
            // UK postcodes typically have specific format, but for now just add UK
            return "\(components.joined(separator: ", ")), United Kingdom"
        }
        return components.joined(separator: ", ")
    }
}

class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var user: UserInfo? // Auth0 user info
    @Published var userProfile: User? // Full user profile from API
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var onboardingCompleted: Bool = false
    @Published var isLoadingUserData: Bool = false
    
    private var credentialsManager: CredentialsManager
    private var authentication: Authentication
    private var webAuth: WebAuth
    private var domain: String
    private var clientId: String
    private let baseURL = "https://api.any-gym.com"
    private var cancellables = Set<AnyCancellable>()
    private var hasCheckedAuth = false
    
    init() {
        // Get Auth0 credentials from Info.plist
        self.domain = Bundle.main.object(forInfoDictionaryKey: "Auth0Domain") as? String ?? ""
        self.clientId = Bundle.main.object(forInfoDictionaryKey: "Auth0ClientId") as? String ?? ""
        
        // Validate Auth0 configuration
        if domain.isEmpty || clientId.isEmpty {
            print("ERROR: Auth0Domain or Auth0ClientId is missing from Info.plist")
            print("Please add your Auth0 credentials to Info.plist:")
            print("  - Auth0Domain: your-tenant.auth0.com")
            print("  - Auth0ClientId: your-client-id")
        }
        
        // Initialize Authentication and WebAuth using the domain and clientId
        self.authentication = Auth0.authentication(clientId: clientId, domain: domain)
        self.webAuth = Auth0.webAuth(clientId: clientId, domain: domain)
        
        // Initialize CredentialsManager
        self.credentialsManager = CredentialsManager(authentication: authentication)
        
        // Only check auth status if Auth0 is properly configured
        if !domain.isEmpty && !clientId.isEmpty {
            // Check if we have stored credentials
            checkAuthStatus()
        } else {
            print("Skipping auth status check - Auth0 not configured")
        }
    }
    
    func checkAuthStatus() {
        // Reset hasCheckedAuth to allow re-checking if needed
        // hasCheckedAuth = false // Commented out - only check once per session
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
                        // Set isLoadingUserData to true BEFORE calling getUserInfo
                        // This ensures ContentView shows loading while we fetch user data
                        self.isLoadingUserData = true
                        self.getUserInfo(accessToken: credentials.accessToken)
                        // Note: fetchUserData will be called from getUserInfo after user.sub is available
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
        
        // Clear any existing Auth0 session to force fresh login
        webAuth.clearSession { _ in
            // After clearing session, start login flow
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                self.webAuth
                    .scope("openid profile email")
                    .parameters([
                        "screen_hint": "login",  // Show login screen (not signup)
                        "prompt": "login"        // Force login even if user is already authenticated
                    ])
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
                        self.userProfile = nil
                        self.onboardingCompleted = false
                    case .failure(let error):
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
    }
    
    private func getUserInfo(accessToken: String) {
        print("getUserInfo: Fetching user info from Auth0")
        authentication
            .userInfo(withAccessToken: accessToken)
            .start { [weak self] (result: Result<UserInfo, AuthenticationError>) in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    switch result {
                    case .success(let user):
                        print("getUserInfo: Success, user.sub = \(user.sub)")
                        self.user = user
                        // Fetch user data from API to check onboarding status
                        print("getUserInfo: Calling fetchUserData with auth0Id: \(user.sub)")
                        self.fetchUserData(auth0Id: user.sub)
                    case .failure(let error):
                        print("getUserInfo: Error - \(error.localizedDescription)")
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
    }
    
    func fetchUserData(auth0Id: String) {
        isLoadingUserData = true
        
        guard let url = URL(string: "\(baseURL)/user") else {
            isLoadingUserData = false
            print("ERROR: Invalid URL for fetchUserData")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(auth0Id, forHTTPHeaderField: "auth0_id")
        
        print("Fetching user data for auth0_id: \(auth0Id)")
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .tryMap { data -> User in
                // Log raw response for debugging
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("User data API response: \(jsonString)")
                }
                let decoder = JSONDecoder()
                return try decoder.decode(User.self, from: data)
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self = self else { return }
                    self.isLoadingUserData = false
                    if case .failure(let error) = completion {
                        print("ERROR: Failed to fetch user data: \(error)")
                        // Don't default to false - keep current state if fetch fails
                        // This prevents overwriting a true value with false on network errors
                    }
                },
                receiveValue: { [weak self] user in
                    guard let self = self else { return }
                    let previousStatus = self.onboardingCompleted
                    self.userProfile = user
                    self.onboardingCompleted = user.onboardingCompleted
                    self.isLoadingUserData = false
                    print("User profile loaded: \(user.fullName ?? "Unknown")")
                    print("User onboarding status updated: \(previousStatus) -> \(user.onboardingCompleted)")
                    print("onboardingCompleted is now: \(self.onboardingCompleted)")
                }
            )
            .store(in: &cancellables)
    }
    
    // Get auth0_id from user or refresh from credentials if needed
    func getAuth0Id(completion: @escaping (String?) -> Void) {
        // If user is already loaded, return the sub
        if let auth0Id = user?.sub {
            completion(auth0Id)
            return
        }
        
        // Otherwise, try to get it from stored credentials
        credentialsManager
            .credentials()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { result in
                    if case .failure = result {
                        completion(nil)
                    }
                },
                receiveValue: { [weak self] credentials in
                    guard let self = self else {
                        completion(nil)
                        return
                    }
                    if !credentials.accessToken.isEmpty {
                        // Fetch user info to get auth0_id
                        self.authentication
                            .userInfo(withAccessToken: credentials.accessToken)
                            .start { result in
                                switch result {
                                case .success(let userInfo):
                                    DispatchQueue.main.async {
                                        self.user = userInfo
                                        completion(userInfo.sub)
                                    }
                                case .failure:
                                    completion(nil)
                                }
                            }
                    } else {
                        completion(nil)
                    }
                }
            )
            .store(in: &cancellables)
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
