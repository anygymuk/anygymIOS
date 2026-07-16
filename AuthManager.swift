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
    let passNotificationConsent: Bool?
    let marketingConsent: Bool?
    
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
        case passNotificationConsent = "pass_notification_consent"
        case marketingConsent = "marketing_consent"
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
    @Published var isCheckingAuth = true
    
    /// Auth0 user id from live session or persisted offline session.
    var auth0Id: String? {
        user?.sub ?? cachedAuth0Id
    }
    
    var userEmail: String? {
        user?.email ?? userProfile?.email
    }
    
    private var credentialsManager: CredentialsManager
    private var authentication: Authentication
    private var webAuth: WebAuth
    private var domain: String
    private var clientId: String
    private let baseURL = "https://api.any-gym.com"
    private var cancellables = Set<AnyCancellable>()
    private var cachedAuth0Id: String?
    
    private enum SessionStorageKey {
        static let hasPersistedSession = "hasPersistedSession"
        static let auth0Id = "cachedAuth0Id"
        static let userProfile = "cachedUserProfile"
        static let onboardingCompleted = "cachedOnboardingCompleted"
    }
    
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
            isCheckingAuth = false
        }
    }
    
    func checkAuthStatus() {
        guard !isLoading else { return }
        isCheckingAuth = true
        isLoading = true
        errorMessage = nil
        
        credentialsManager
            .credentials(minTTL: 60)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self = self else { return }
                    if case .failure(let error) = completion {
                        print("Auth check: credentials unavailable (\(error.localizedDescription))")
                        if self.restorePersistedSession() {
                            print("Auth check: restored persisted session for offline access")
                            self.isAuthenticated = true
                            self.isLoadingUserData = false
                        } else {
                            self.isAuthenticated = false
                        }
                        self.finishAuthCheck()
                    }
                },
                receiveValue: { [weak self] credentials in
                    guard let self = self else { return }
                    guard !credentials.accessToken.isEmpty else {
                        if self.restorePersistedSession() {
                            self.isAuthenticated = true
                            self.isLoadingUserData = false
                        } else {
                            self.isAuthenticated = false
                        }
                        self.finishAuthCheck()
                        return
                    }
                    
                    self.isAuthenticated = true
                    self.isLoadingUserData = true
                    self.getUserInfo(accessToken: credentials.accessToken)
                }
            )
            .store(in: &cancellables)
    }
    
    private func finishAuthCheck() {
        isLoading = false
        isCheckingAuth = false
    }
    
    private func persistSession() {
        guard let auth0Id = auth0Id else { return }
        
        UserDefaults.standard.set(true, forKey: SessionStorageKey.hasPersistedSession)
        UserDefaults.standard.set(auth0Id, forKey: SessionStorageKey.auth0Id)
        UserDefaults.standard.set(onboardingCompleted, forKey: SessionStorageKey.onboardingCompleted)
        
        if let userProfile = userProfile,
           let profileData = try? JSONEncoder().encode(userProfile) {
            UserDefaults.standard.set(profileData, forKey: SessionStorageKey.userProfile)
        }
        
        print("Session persisted for auth0Id: \(auth0Id)")
    }
    
    @discardableResult
    private func restorePersistedSession() -> Bool {
        guard UserDefaults.standard.bool(forKey: SessionStorageKey.hasPersistedSession),
              let auth0Id = UserDefaults.standard.string(forKey: SessionStorageKey.auth0Id),
              !auth0Id.isEmpty else {
            return false
        }
        
        cachedAuth0Id = auth0Id
        onboardingCompleted = UserDefaults.standard.bool(forKey: SessionStorageKey.onboardingCompleted)
        
        if let profileData = UserDefaults.standard.data(forKey: SessionStorageKey.userProfile),
           let cachedProfile = try? JSONDecoder().decode(User.self, from: profileData) {
            userProfile = cachedProfile
            onboardingCompleted = cachedProfile.onboardingCompleted
        }
        
        print("Restored persisted session for auth0Id: \(auth0Id)")
        return true
    }
    
    private func clearPersistedSession() {
        cachedAuth0Id = nil
        UserDefaults.standard.removeObject(forKey: SessionStorageKey.hasPersistedSession)
        UserDefaults.standard.removeObject(forKey: SessionStorageKey.auth0Id)
        UserDefaults.standard.removeObject(forKey: SessionStorageKey.userProfile)
        UserDefaults.standard.removeObject(forKey: SessionStorageKey.onboardingCompleted)
    }
    
    func login() {
        isLoading = true
        errorMessage = nil
        
        // Clear any existing Auth0 session to force fresh login
        webAuth.clearSession { [weak self] _ in
            // After clearing session, start login flow
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                self.webAuth
                    .scope("openid profile email offline_access")
                    .parameters([
                        "screen_hint": "login"
                    ])
                    .start { [weak self] (result: Result<Credentials, WebAuthError>) in
                        DispatchQueue.main.async {
                            guard let self = self else { return }
                            self.isLoading = false
                            switch result {
                            case .success(let credentials):
                                let stored = self.credentialsManager.store(credentials: credentials)
                                if !stored {
                                    print("WARNING: Failed to store credentials in keychain")
                                }
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
                        self.clearPersistedSession()
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
                        self.cachedAuth0Id = user.sub
                        self.persistSession()
                        print("getUserInfo: Calling fetchUserData with auth0Id: \(user.sub)")
                        self.fetchUserData(auth0Id: user.sub)
                    case .failure(let error):
                        print("getUserInfo: Error - \(error.localizedDescription)")
                        if self.restorePersistedSession() {
                            print("getUserInfo: Using persisted session after network failure")
                            self.isLoadingUserData = false
                            self.finishAuthCheck()
                        } else {
                            self.errorMessage = error.localizedDescription
                            self.isLoadingUserData = false
                            self.finishAuthCheck()
                        }
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
                    self.finishAuthCheck()
                    if case .failure(let error) = completion {
                        print("ERROR: Failed to fetch user data: \(error)")
                        if self.restorePersistedSession() {
                            print("Using persisted profile after user data fetch failure")
                        }
                    }
                },
                receiveValue: { [weak self] user in
                    guard let self = self else { return }
                    let previousStatus = self.onboardingCompleted
                    self.userProfile = user
                    self.onboardingCompleted = user.onboardingCompleted
                    self.isLoadingUserData = false
                    self.persistSession()
                    self.finishAuthCheck()
                    print("User profile loaded: \(user.fullName ?? "Unknown")")
                    print("User onboarding status updated: \(previousStatus) -> \(user.onboardingCompleted)")
                    print("onboardingCompleted is now: \(self.onboardingCompleted)")
                }
            )
            .store(in: &cancellables)
    }
    
    // Get auth0_id from user or refresh from credentials if needed
    func getAuth0Id(completion: @escaping (String?) -> Void) {
        if let auth0Id = auth0Id {
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
    
    // Update user profile
    func updateUserProfile(
        auth0Id: String,
        fullName: String?,
        addressLine1: String?,
        addressLine2: String?,
        addressCity: String?,
        addressPostcode: String?,
        dateOfBirth: String?,
        emergencyContactName: String?,
        emergencyContactNumber: String?,
        passNotificationConsent: Bool?,
        marketingConsent: Bool?,
        completion: @escaping (Result<User, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/user/update") else {
            completion(.failure(NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(auth0Id, forHTTPHeaderField: "auth0_id")
        
        // Build request body with snake_case field names
        var body: [String: Any] = [:]
        
        if let fullName = fullName {
            body["full_name"] = fullName
        }
        if let addressLine1 = addressLine1 {
            body["address_line1"] = addressLine1
        }
        if let addressLine2 = addressLine2 {
            body["address_line2"] = addressLine2
        }
        if let addressCity = addressCity {
            body["address_city"] = addressCity
        }
        if let addressPostcode = addressPostcode {
            body["address_postcode"] = addressPostcode
        }
        if let dateOfBirth = dateOfBirth {
            body["date_of_birth"] = dateOfBirth
        }
        if let emergencyContactName = emergencyContactName {
            body["emergency_contact_name"] = emergencyContactName
        }
        if let emergencyContactNumber = emergencyContactNumber {
            body["emergency_contact_number"] = emergencyContactNumber
        }
        if let passNotificationConsent = passNotificationConsent {
            body["pass_notification_consent"] = passNotificationConsent
        }
        if let marketingConsent = marketingConsent {
            body["marketing_consent"] = marketingConsent
        }
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode request data"])))
            return
        }
        
        request.httpBody = bodyData
        
        // Log request for debugging
        if let bodyString = String(data: bodyData, encoding: .utf8) {
            print("═══════════════════════════════════════════════")
            print("UPDATE PROFILE REQUEST:")
            print("URL: \(url.absoluteString)")
            print("Method: PUT")
            print("Body: \(bodyString)")
            print("═══════════════════════════════════════════════")
        }
        
        URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { output -> Data in
                guard let httpResponse = output.response as? HTTPURLResponse else {
                    throw NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                }
                
                print("Response status code: \(httpResponse.statusCode)")
                
                // Check for error status codes
                guard (200...299).contains(httpResponse.statusCode) else {
                    // Try to parse error message from response
                    if let errorData = try? JSONSerialization.jsonObject(with: output.data) as? [String: Any],
                       let message = errorData["message"] as? String {
                        throw NSError(domain: "AuthManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
                    } else if let errorString = String(data: output.data, encoding: .utf8) {
                        throw NSError(domain: "AuthManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error: \(errorString)"])
                    } else {
                        throw NSError(domain: "AuthManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error with status code: \(httpResponse.statusCode)"])
                    }
                }
                
                return output.data
            }
            .tryMap { data -> User in
                // Log response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    print("Response body: \(responseString)")
                }
                
                // Check if response is empty - some APIs return empty body on success
                if data.isEmpty {
                    print("Empty response - will fetch updated user data")
                    // Return current user profile if available, otherwise we'll fetch it
                    if let currentUser = self.userProfile {
                        return currentUser
                    }
                    // If no current user, we need to fetch it
                    throw NSError(domain: "AuthManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "EmptyResponse"])
                }
                
                let decoder = JSONDecoder()
                do {
                    return try decoder.decode(User.self, from: data)
                } catch {
                    print("Failed to decode User: \(error)")
                    // Check if this is a success message response (e.g., {"message": "User updated successfully"})
                    if let responseDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let message = responseDict["message"] as? String {
                        // If we have a success message, treat it as success and fetch updated data
                        print("Received success message: \(message)")
                        // Return current user profile if available, otherwise signal to fetch it
                        if let currentUser = self.userProfile {
                            return currentUser
                        }
                        // Signal to fetch updated user data
                        throw NSError(domain: "AuthManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "SuccessMessage"])
                    }
                    // If it's not a message response, treat as actual error
                    throw error
                }
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { result in
                    if case .failure(let error) = result {
                        let nsError = error as NSError
                        // Check if this is the empty response or success message case (which means success)
                        if nsError.code == 0 && nsError.domain == "AuthManager" {
                            // Empty response or success message means success - fetch updated user data
                            print("Update successful, fetching updated user data...")
                            self.fetchUserData(auth0Id: auth0Id)
                            // Wait a moment for fetch to complete, then return success
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                if let user = self.userProfile {
                                    completion(.success(user))
                                } else {
                                    completion(.failure(NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Profile updated but failed to fetch updated data"])))
                                }
                            }
                        } else {
                            print("Update profile error: \(error.localizedDescription)")
                            completion(.failure(error))
                        }
                    }
                },
                receiveValue: { user in
                    print("Profile updated successfully")
                    self.userProfile = user
                    completion(.success(user))
                }
            )
            .store(in: &cancellables)
    }
}
