//
//  OnboardingView.swift
//  AnyGym
//
//  Created on iOS App
//

import SwiftUI
import SafariServices

// MARK: - Onboarding Data Model
struct OnboardingData {
    var firstName: String = ""
    var dateOfBirth: Date = Date()
    var addressLine1: String = ""
    var addressLine2: String = ""
    var city: String = ""
    var postcode: String = ""
    var emergencyContactName: String = ""
    var emergencyContactNumber: String = ""
    var selectedPlanId: String? = nil
}

// MARK: - Stripe Product Model (matching Stripe API response)
struct StripeProduct: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let active: Bool?
    let defaultPrice: String? // Price ID
    var price: StripePrice? // Will be populated from prices array
    let metadata: [String: String]? // Product metadata from Stripe
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case active
        case defaultPrice = "default_price"
        case metadata
    }
    
    // Extract tier from metadata or name
    var membershipTier: String? {
        // Try to get tier from metadata first (check various possible keys)
        if let tier = metadata?["tier"] {
            return tier.lowercased()
        }
        if let tier = metadata?["Tier"] {
            return tier.lowercased()
        }
        if let tier = metadata?["membership_tier"] {
            return tier.lowercased()
        }
        if let tier = metadata?["Membership Tier"] {
            return tier.lowercased()
        }
        
        // Try to infer from product name (e.g., "Premium", "Standard", "Elite")
        let nameLower = name.lowercased()
        if nameLower.contains("premium") {
            return "premium"
        } else if nameLower.contains("elite") {
            return "elite"
        } else if nameLower.contains("standard") {
            return "standard"
        }
        
        // Try to infer from description
        if let desc = description?.lowercased() {
            if desc.contains("premium") {
                return "premium"
            } else if desc.contains("elite") {
                return "elite"
            } else if desc.contains("standard") {
                return "standard"
            }
        }
        
        return nil
    }
}

struct StripePrice: Codable {
    let id: String
    let unitAmount: Int? // Amount in cents
    let amount: Int? // Alternative field name
    let currency: String
    let recurring: StripeRecurring?
    
    enum CodingKeys: String, CodingKey {
        case id
        case unitAmount = "unit_amount"
        case amount
        case currency
        case recurring
    }
    
    // Computed property to get amount regardless of field name
    var amountValue: Int {
        return unitAmount ?? amount ?? 0
    }
}

struct StripeRecurring: Codable {
    let interval: String // "month", "year", etc.
    let intervalCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case interval
        case intervalCount = "interval_count"
    }
}

// Stripe API returns products and prices separately, so we need to combine them
struct StripeAPIResponse: Codable {
    let data: [StripeProduct]
    let hasMore: Bool?
    
    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
    }
}

struct StripePricesAPIResponse: Codable {
    let data: [StripePrice]
    let hasMore: Bool?
    
    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
    }
}

struct OnboardingView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var currentStep = 1
    @State private var onboardingData = OnboardingData()
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var stripeProducts: [StripeProduct] = []
    @State private var isLoadingProducts = false
    @State private var showStripeCheckout = false
    @State private var stripeCheckoutURL: URL?
    @State private var selectedProduct: StripeProduct? = nil // Store selected product to get tier info
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            ProgressView(value: Double(currentStep), total: 4)
                .progressViewStyle(LinearProgressViewStyle(tint: Color(red: 1.0, green: 0.42, blue: 0.42)))
                .padding(.horizontal, 20)
                .padding(.top, 20)
            
            // Step content
            ScrollView {
                VStack(spacing: 24) {
                    switch currentStep {
                    case 1:
                        StepOneView(data: $onboardingData)
                    case 2:
                        StepTwoView(data: $onboardingData)
                    case 3:
                        StepThreeView(data: $onboardingData)
                    case 4:
                        StepFourView(
                            data: $onboardingData,
                            products: $stripeProducts,
                            isLoadingProducts: $isLoadingProducts
                        )
                    default:
                        EmptyView()
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 40)
            }
            
            // Navigation buttons
            VStack(spacing: 12) {
                if currentStep == 4 && onboardingData.selectedPlanId != nil {
                    // Show "Complete Checkout" button when plan is selected
                    Button(action: {
                        if let planId = onboardingData.selectedPlanId {
                            print("User clicked Complete Checkout with planId: \(planId)")
                            completeOnboarding(selectedPlanId: planId, proceedToCheckout: true)
                        } else {
                            errorMessage = "Please select a plan before proceeding to checkout"
                            print("ERROR: No plan selected when clicking Complete Checkout")
                        }
                    }) {
                        Text("Complete Checkout")
                            .poppins(.semibold, size: 16)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(red: 1.0, green: 0.42, blue: 0.42))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(isLoading)
                }
                
                HStack(spacing: 16) {
                    if currentStep > 1 {
                        Button(action: {
                            withAnimation {
                                currentStep -= 1
                            }
                        }) {
                            Text("Back")
                                .poppins(.semibold, size: 16)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .foregroundColor(.gray)
                                .cornerRadius(12)
                        }
                    }
                    
                    Button(action: {
                        if currentStep == 4 {
                            // Skip - complete onboarding without checkout
                            print("═══════════════════════════════════════════════")
                            print("SKIP BUTTON CLICKED")
                            print("═══════════════════════════════════════════════")
                            print("Selected Plan ID: \(onboardingData.selectedPlanId ?? "nil")")
                            print("Proceed to Checkout: false")
                            print("Calling completeOnboarding...")
                            print("═══════════════════════════════════════════════")
                            completeOnboarding(selectedPlanId: onboardingData.selectedPlanId, proceedToCheckout: false)
                        } else {
                            handleNext()
                        }
                    }) {
                        Text(currentStep == 4 ? "Skip" : "Next")
                            .poppins(.semibold, size: 16)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(currentStep == 4 ? Color.gray.opacity(0.1) : Color(red: 1.0, green: 0.42, blue: 0.42))
                            .foregroundColor(currentStep == 4 ? .gray : .white)
                            .cornerRadius(12)
                    }
                    .disabled(isLoading) // Removed !isStepValid() check for Skip button - allow skipping even if step 4 validation fails
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .overlay {
            if isLoading {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .sheet(isPresented: $showStripeCheckout) {
            if let url = stripeCheckoutURL {
                StripeCheckoutSafariView(url: url)
                    .ignoresSafeArea()
                    .onDisappear {
                        // When checkout sheet is dismissed, complete onboarding if it hasn't been completed yet
                        if !authManager.onboardingCompleted {
                            authManager.onboardingCompleted = true
                            if let auth0Id = authManager.user?.sub {
                                authManager.fetchUserData(auth0Id: auth0Id)
                            }
                        }
                        // Clear the URL when dismissed
                        stripeCheckoutURL = nil
                    }
            } else {
                // Fallback - shouldn't happen but prevents crash
                Text("Loading checkout...")
                    .onAppear {
                        showStripeCheckout = false
                    }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StripeCheckoutSuccess"))) { _ in
            // Handle successful checkout redirect
            print("✓ Received Stripe checkout success notification")
            // Dismiss the checkout sheet
            showStripeCheckout = false
            // Complete onboarding
            if !authManager.onboardingCompleted {
                authManager.onboardingCompleted = true
                if let auth0Id = authManager.user?.sub {
                    authManager.fetchUserData(auth0Id: auth0Id)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StripeCheckoutCancel"))) { _ in
            // Handle cancelled checkout
            print("⚠ Received Stripe checkout cancel notification")
            showStripeCheckout = false
        }
        .onAppear {
            if currentStep == 4 {
                fetchStripeProducts()
            }
        }
        .onChange(of: currentStep) { newStep in
            if newStep == 4 {
                fetchStripeProducts()
            }
        }
    }
    
    private func isStepValid() -> Bool {
        switch currentStep {
        case 1:
            return !onboardingData.firstName.isEmpty
        case 2:
            return !onboardingData.addressLine1.isEmpty &&
                   !onboardingData.city.isEmpty &&
                   !onboardingData.postcode.isEmpty
        case 3:
            return !onboardingData.emergencyContactName.isEmpty &&
                   !onboardingData.emergencyContactNumber.isEmpty
        case 4:
            return true // Step 4 is always valid (can skip)
        default:
            return false
        }
    }
    
    private func handleNext() {
        if currentStep == 4 {
            // Skip - complete onboarding without plan
            completeOnboarding(selectedPlanId: nil)
        } else {
            withAnimation {
                currentStep += 1
            }
        }
    }
    
    private func fetchStripeProducts() {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        
        // Get Stripe key from Info.plist
        // NOTE: Stripe's products API requires a SECRET key (sk_test_...), not a publishable key
        // NOTE: In production, this should be done server-side for security
        let stripeKey = Bundle.main.object(forInfoDictionaryKey: "StripePublishableKey") as? String ?? ""
        
        guard !stripeKey.isEmpty else {
            print("Stripe key not found in Info.plist. Please add 'StripePublishableKey' to Info.plist")
            isLoadingProducts = false
            return
        }
        
        // Check if it's a secret key (required for products API)
        guard stripeKey.hasPrefix("sk_") else {
            print("ERROR: Stripe products API requires a SECRET key (sk_test_...), not a publishable key (pk_test_...).")
            print("The key in Info.plist starts with 'pk_' which is a publishable key.")
            print("Please add your Stripe SECRET key (starts with 'sk_test_') to Info.plist as 'StripePublishableKey'")
            print("OR use your backend endpoint at https://api.any-gym.com/stripe/products instead.")
            isLoadingProducts = false
            return
        }
        
        // Fetch products from Stripe API
        guard let productsURL = URL(string: "https://api.stripe.com/v1/products?active=true&limit=100") else {
            isLoadingProducts = false
            return
        }
        
        var productsRequest = URLRequest(url: productsURL)
        productsRequest.httpMethod = "GET"
        productsRequest.setValue("Bearer \(stripeKey)", forHTTPHeaderField: "Authorization")
        productsRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        print("Fetching Stripe products from: \(productsURL.absoluteString)")
        
        URLSession.shared.dataTask(with: productsRequest) { productsData, productsResponse, productsError in
            if let error = productsError {
                DispatchQueue.main.async {
                    self.isLoadingProducts = false
                    print("Error fetching Stripe products: \(error.localizedDescription)")
                }
                return
            }
            
            guard let httpResponse = productsResponse as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    self.isLoadingProducts = false
                }
                return
            }
            
            print("Stripe products API response status: \(httpResponse.statusCode)")
            
            guard let productsData = productsData else {
                DispatchQueue.main.async {
                    self.isLoadingProducts = false
                }
                return
            }
            
            // Log raw response for debugging
            if let jsonString = String(data: productsData, encoding: .utf8) {
                print("Stripe products API response (first 500 chars): \(String(jsonString.prefix(500)))")
            }
            
            do {
                let decoder = JSONDecoder()
                let productsResponse = try decoder.decode(StripeAPIResponse.self, from: productsData)
                let products = productsResponse.data.filter { $0.active != false }
                
                // Now fetch prices for each product
                self.fetchStripePrices(for: products, stripeKey: stripeKey)
            } catch {
                DispatchQueue.main.async {
                    self.isLoadingProducts = false
                    print("Error decoding Stripe products: \(error)")
                    if let decodingError = error as? DecodingError {
                        switch decodingError {
                        case .keyNotFound(let key, let context):
                            print("Missing key '\(key.stringValue)' in \(context.debugDescription)")
                        case .typeMismatch(let type, let context):
                            print("Type mismatch for type \(type) in \(context.debugDescription)")
                        case .valueNotFound(let type, let context):
                            print("Value not found for type \(type) in \(context.debugDescription)")
                        case .dataCorrupted(let context):
                            print("Data corrupted: \(context.debugDescription)")
                        @unknown default:
                            print("Unknown decoding error")
                        }
                    }
                }
            }
        }.resume()
    }
    
    private func fetchStripePrices(for products: [StripeProduct], stripeKey: String) {
        // Fetch prices from Stripe API
        guard let pricesURL = URL(string: "https://api.stripe.com/v1/prices?active=true&limit=100") else {
            DispatchQueue.main.async {
                self.isLoadingProducts = false
            }
            return
        }
        
        var pricesRequest = URLRequest(url: pricesURL)
        pricesRequest.httpMethod = "GET"
        pricesRequest.setValue("Bearer \(stripeKey)", forHTTPHeaderField: "Authorization")
        pricesRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        print("Fetching Stripe prices from: \(pricesURL.absoluteString)")
        
        URLSession.shared.dataTask(with: pricesRequest) { pricesData, pricesResponse, pricesError in
            DispatchQueue.main.async {
                self.isLoadingProducts = false
                
                if let error = pricesError {
                    print("Error fetching Stripe prices: \(error.localizedDescription)")
                    return
                }
                
                guard let httpResponse = pricesResponse as? HTTPURLResponse else {
                    return
                }
                
                print("Stripe prices API response status: \(httpResponse.statusCode)")
                
                guard let pricesData = pricesData else {
                    return
                }
                
                do {
                    let decoder = JSONDecoder()
                    let pricesResponse = try decoder.decode(StripePricesAPIResponse.self, from: pricesData)
                    let prices = pricesResponse.data
                    
                    // Create a dictionary of prices by ID for quick lookup
                    var pricesDict: [String: StripePrice] = [:]
                    for price in prices {
                        pricesDict[price.id] = price
                    }
                    
                    // Combine products with their prices
                    var productsWithPrices: [StripeProduct] = []
                    for var product in products {
                        // Try to find price using default_price or first available price
                        if let defaultPriceId = product.defaultPrice,
                           let price = pricesDict[defaultPriceId] {
                            product.price = price
                            productsWithPrices.append(product)
                        } else {
                            // If no default price, try to find any price for this product
                            // (Note: Stripe API doesn't directly link prices to products in the response,
                            // so we'll use the default_price field)
                            if let defaultPriceId = product.defaultPrice,
                               let price = pricesDict[defaultPriceId] {
                                product.price = price
                                productsWithPrices.append(product)
                            }
                        }
                    }
                    
                    self.stripeProducts = productsWithPrices
                    print("Successfully loaded \(productsWithPrices.count) products with prices")
                } catch {
                    print("Error decoding Stripe prices: \(error)")
                }
            }
        }.resume()
    }
    
    private func completeOnboarding(selectedPlanId: String?, proceedToCheckout: Bool = false) {
        print("═══════════════════════════════════════════════")
        print("completeOnboarding CALLED")
        print("═══════════════════════════════════════════════")
        print("Selected Plan ID: \(selectedPlanId ?? "nil")")
        print("Proceed to Checkout: \(proceedToCheckout)")
        print("═══════════════════════════════════════════════")
        
        isLoading = true
        errorMessage = nil
        
        // Get auth0_id - will fetch from credentials if user object is nil
        authManager.getAuth0Id { auth0Id in
            guard let auth0Id = auth0Id else {
                print("ERROR: Could not get auth0_id")
                self.errorMessage = "User not authenticated. Please try logging in again."
                self.isLoading = false
                return
            }
            
            print("✓ Got auth0_id: \(auth0Id)")
            print("Calling proceedWithOnboarding...")
            self.proceedWithOnboarding(auth0Id: auth0Id, selectedPlanId: selectedPlanId, proceedToCheckout: proceedToCheckout)
        }
    }
    
    private func proceedWithOnboarding(auth0Id: String, selectedPlanId: String?, proceedToCheckout: Bool) {
        
        guard let url = URL(string: "https://api.any-gym.com/user/update") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(auth0Id, forHTTPHeaderField: "auth0_id")
        
        // Validate required fields before sending
        guard !onboardingData.firstName.isEmpty else {
            errorMessage = "First name is required"
            isLoading = false
            print("ERROR: First name is empty")
            return
        }
        
        guard !onboardingData.addressLine1.isEmpty else {
            errorMessage = "Address line 1 is required"
            isLoading = false
            print("ERROR: Address line 1 is empty")
            return
        }
        
        guard !onboardingData.city.isEmpty else {
            errorMessage = "City is required"
            isLoading = false
            print("ERROR: City is empty")
            return
        }
        
        guard !onboardingData.postcode.isEmpty else {
            errorMessage = "Postcode is required"
            isLoading = false
            print("ERROR: Postcode is empty")
            return
        }
        
        guard !onboardingData.emergencyContactName.isEmpty else {
            errorMessage = "Emergency contact name is required"
            isLoading = false
            print("ERROR: Emergency contact name is empty")
            return
        }
        
        guard !onboardingData.emergencyContactNumber.isEmpty else {
            errorMessage = "Emergency contact number is required"
            isLoading = false
            print("ERROR: Emergency contact number is empty")
            return
        }
        
        // Log the onboarding data being sent
        print("═══════════════════════════════════════════════")
        print("ONBOARDING DATA BEING SENT:")
        print("═══════════════════════════════════════════════")
        print("Full Name: '\(onboardingData.firstName)' (length: \(onboardingData.firstName.count))")
        print("Date of Birth: \(onboardingData.dateOfBirth)")
        print("Address Line 1: '\(onboardingData.addressLine1)' (length: \(onboardingData.addressLine1.count))")
        print("Address Line 2: '\(onboardingData.addressLine2)' (length: \(onboardingData.addressLine2.count))")
        print("City: '\(onboardingData.city)' (length: \(onboardingData.city.count))")
        print("Postcode: '\(onboardingData.postcode)' (length: \(onboardingData.postcode.count))")
        print("Emergency Contact Name: '\(onboardingData.emergencyContactName)' (length: \(onboardingData.emergencyContactName.count))")
        print("Emergency Contact Number: '\(onboardingData.emergencyContactNumber)' (length: \(onboardingData.emergencyContactNumber.count))")
        print("Selected Plan ID: \(selectedPlanId ?? "nil")")
        print("Proceed to Checkout: \(proceedToCheckout)")
        print("═══════════════════════════════════════════════")
        
        // Format date of birth - ensure it's in YYYY-MM-DD format
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0) // Use UTC to avoid timezone issues
        let dobString = dateFormatter.string(from: onboardingData.dateOfBirth)
        print("Date of Birth formatted: '\(dobString)' (from: \(onboardingData.dateOfBirth))")
        
        // Build request body - API expects snake_case field names
        var body: [String: Any] = [
            "full_name": onboardingData.firstName,
            "date_of_birth": dobString,
            "address_line1": onboardingData.addressLine1,
            "address_city": onboardingData.city,
            "address_postcode": onboardingData.postcode,
            "emergency_contact_name": onboardingData.emergencyContactName,
            "emergency_contact_number": onboardingData.emergencyContactNumber,
            "onboarding_completed": true
        ]
        
        // Add optional fields
        if !onboardingData.addressLine2.isEmpty {
            body["address_line2"] = onboardingData.addressLine2
        }
        
        if let planId = selectedPlanId {
            body["subscription_plan_id"] = planId
        }
        
        // Create and log the request body
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            errorMessage = "Failed to encode request data"
            isLoading = false
            print("ERROR: Failed to serialize request body")
            return
        }
        
        if let bodyString = String(data: bodyData, encoding: .utf8) {
            print("═══════════════════════════════════════════════")
            print("REQUEST BODY JSON:")
            print("═══════════════════════════════════════════════")
            print(bodyString)
            print("═══════════════════════════════════════════════")
            
            // Pretty print the JSON for easier debugging
            if let jsonObject = try? JSONSerialization.jsonObject(with: bodyData),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                print("REQUEST BODY (PRETTY):")
                print(prettyString)
            }
        }
        
        request.httpBody = bodyData
        
        // Log the exact bytes being sent
        print("Request body bytes: \(bodyData.count) bytes")
        print("Request body hex (first 100 bytes): \(bodyData.prefix(100).map { String(format: "%02x", $0) }.joined(separator: " "))")
        
        // Log the full request details
        print("═══════════════════════════════════════════════")
        print("API REQUEST DETAILS:")
        print("═══════════════════════════════════════════════")
        print("URL: \(url.absoluteString)")
        print("Method: PUT")
        print("Headers:")
        print("  Content-Type: application/json")
        print("  auth0_id: \(auth0Id)")
        print("Body size: \(bodyData.count) bytes")
        print("═══════════════════════════════════════════════")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    let errorMsg = "Error updating profile: \(error.localizedDescription)"
                    print("═══════════════════════════════════════════════")
                    print("ERROR UPDATING USER PROFILE:")
                    print("═══════════════════════════════════════════════")
                    print(errorMsg)
                    print("Error details: \(error)")
                    print("═══════════════════════════════════════════════")
                    self.errorMessage = errorMsg
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("═══════════════════════════════════════════════")
                    print("USER UPDATE API RESPONSE:")
                    print("═══════════════════════════════════════════════")
                    print("Status Code: \(httpResponse.statusCode)")
                    print("Response Headers: \(httpResponse.allHeaderFields)")
                    
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        print("Response Body: \(responseString)")
                    }
                    print("═══════════════════════════════════════════════")
                    
                    if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                        print("✓ User profile updated successfully!")
                        
                        // Parse response to verify what was actually updated
                        if let responseData = data,
                           let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                            print("═══════════════════════════════════════════════")
                            print("API RESPONSE DATA:")
                            print("═══════════════════════════════════════════════")
                            print(json)
                            print("═══════════════════════════════════════════════")
                            
                            // Check if response contains updated user data
                            if let updatedUser = json["user"] as? [String: Any] {
                                print("✓ Response contains updated user data:")
                                print(updatedUser)
                                
                                // Compare sent vs received data
                                print("═══════════════════════════════════════════════")
                                print("DATA COMPARISON (Sent vs Received):")
                                print("═══════════════════════════════════════════════")
                                print("Full Name - Sent: '\(onboardingData.firstName)' | Received: '\(updatedUser["full_name"] as? String ?? "N/A")'")
                                print("Address Line 1 - Sent: '\(onboardingData.addressLine1)' | Received: '\(updatedUser["address_line1"] as? String ?? "N/A")'")
                                print("City - Sent: '\(onboardingData.city)' | Received: '\(updatedUser["address_city"] as? String ?? "N/A")'")
                                print("Postcode - Sent: '\(onboardingData.postcode)' | Received: '\(updatedUser["address_postcode"] as? String ?? "N/A")'")
                                print("Emergency Contact Name - Sent: '\(onboardingData.emergencyContactName)' | Received: '\(updatedUser["emergency_contact_name"] as? String ?? "N/A")'")
                                print("Emergency Contact Number - Sent: '\(onboardingData.emergencyContactNumber)' | Received: '\(updatedUser["emergency_contact_number"] as? String ?? "N/A")'")
                                print("═══════════════════════════════════════════════")
                            } else {
                                print("⚠ Response does not contain updated user data")
                                print("⚠ This might indicate the API accepted the request but didn't process the fields")
                                print("⚠ The API might not be recognizing the camelCase field names")
                            }
                        }
                        
                        // Wait a moment before fetching user data to ensure backend has processed the update
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            // If plan was selected and user wants to checkout, proceed to Stripe checkout FIRST
                            // Don't complete onboarding yet - wait until after checkout
                            if let planId = selectedPlanId, proceedToCheckout {
                                print("✓ Onboarding update successful. Starting Stripe checkout with planId: \(planId)")
                                // Start checkout flow without completing onboarding
                                self.initiateStripeCheckout(planId: planId)
                            } else {
                                // No checkout - complete onboarding now
                                print("✓ Completing onboarding (no checkout)")
                                self.authManager.onboardingCompleted = true
                                self.authManager.fetchUserData(auth0Id: auth0Id)
                            }
                        }
                    } else {
                        let errorMsg = "Failed to update profile (Status: \(httpResponse.statusCode)). Please try again."
                        print("⚠ \(errorMsg)")
                        if let data = data, let responseString = String(data: data, encoding: .utf8) {
                            print("Error response: \(responseString)")
                        }
                        self.errorMessage = errorMsg
                    }
                } else {
                    let errorMsg = "Invalid response from server. Please try again."
                    print("⚠ \(errorMsg)")
                    self.errorMessage = errorMsg
                }
            }
        }.resume()
    }
    
    private func initiateStripeCheckout(planId: String) {
        // Get auth0_id and user email - will fetch from credentials if user object is nil
        authManager.getAuth0Id { auth0Id in
            guard let auth0Id = auth0Id else {
                errorMessage = "User not authenticated. Please try logging in again."
                return
            }
            
            // Get user email from Auth0 user info if available
            let userEmail = authManager.user?.email
            
            // Find the product that matches this price ID to get tier information
            var membershipTier: String? = nil
            for product in stripeProducts {
                if product.price?.id == planId {
                    membershipTier = product.membershipTier
                    print("═══════════════════════════════════════════════")
                    print("PRODUCT TIER EXTRACTION:")
                    print("═══════════════════════════════════════════════")
                    print("Product Name: \(product.name)")
                    print("Product Description: \(product.description ?? "none")")
                    print("Product Metadata: \(product.metadata ?? [:])")
                    print("Extracted Tier: \(membershipTier ?? "NOT FOUND")")
                    print("═══════════════════════════════════════════════")
                    break
                }
            }
            
            if membershipTier == nil {
                print("⚠ WARNING: Could not determine membership tier for price ID: \(planId)")
                print("⚠ Available products:")
                for product in stripeProducts {
                    print("  - \(product.name) (price: \(product.price?.id ?? "none"))")
                }
            }
            
            proceedWithStripeCheckout(planId: planId, auth0Id: auth0Id, userEmail: userEmail, membershipTier: membershipTier)
        }
    }
    
    private func proceedWithStripeCheckout(planId: String, auth0Id: String, userEmail: String? = nil, membershipTier: String? = nil) {
        print("proceedWithStripeCheckout: Starting checkout for planId: '\(planId)', auth0Id: \(auth0Id), email: \(userEmail ?? "none"), tier: \(membershipTier ?? "none")")
        
        // Validate planId is not empty
        guard !planId.isEmpty else {
            errorMessage = "No plan selected. Please select a plan and try again."
            print("ERROR: planId is empty!")
            return
        }
        
        print("✓ Plan ID validated: \(planId)")
        
        // Get Stripe secret key from Info.plist
        let stripeKey = Bundle.main.object(forInfoDictionaryKey: "StripePublishableKey") as? String ?? ""
        
        guard !stripeKey.isEmpty && stripeKey.hasPrefix("sk_") else {
            errorMessage = "Stripe secret key not configured. Please check your configuration."
            print("ERROR: Stripe secret key is missing or invalid")
            return
        }
        
        // Get bundle identifier for redirect URI
        let bundleId = Bundle.main.bundleIdentifier ?? "com.anygym.app"
        let successURL = "\(bundleId)://stripe-checkout-success"
        let cancelURL = "\(bundleId)://stripe-checkout-cancel"
        
        // Create Stripe Checkout Session using Stripe API
        guard let url = URL(string: "https://api.stripe.com/v1/checkout/sessions") else {
            errorMessage = "Invalid Stripe API URL"
            print("ERROR: Invalid Stripe API URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(stripeKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        print("Creating Stripe checkout session for price ID: '\(planId)'")
        print("Price ID validation: isEmpty=\(planId.isEmpty), count=\(planId.count)")
        print("Price ID format check - starts with 'price_': \(planId.hasPrefix("price_"))")
        
        // Build form-encoded body for Stripe API
        // Use proper URL encoding for form data values
        func urlEncode(_ value: String) -> String {
            return value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
        }
        
        // Build form data - Stripe requires line_items[0][price] to be the price ID
        var formDataComponents: [String] = []
        
        formDataComponents.append("mode=subscription")
        formDataComponents.append("line_items[0][price]=\(urlEncode(planId))")
        formDataComponents.append("line_items[0][quantity]=1")
        formDataComponents.append("success_url=\(urlEncode(successURL))")
        formDataComponents.append("cancel_url=\(urlEncode(cancelURL))")
        
        // Add client_reference_id - this is critical for webhooks to link checkout to user
        formDataComponents.append("client_reference_id=\(urlEncode(auth0Id))")
        
        // Add metadata for webhook processing - MUST include membership_tier for webhook
        formDataComponents.append("metadata[auth0_id]=\(urlEncode(auth0Id))")
        
        // Add membership tier to metadata - REQUIRED for webhook
        if let tier = membershipTier, !tier.isEmpty {
            formDataComponents.append("metadata[membership_tier]=\(urlEncode(tier))")
            print("✓ Adding membership tier to metadata: \(tier)")
        } else {
            print("⚠ WARNING: No membership tier found - webhook will fail!")
            print("⚠ Attempting to infer tier from product name...")
            // Try to find tier from product name as fallback
            for product in stripeProducts {
                if product.price?.id == planId {
                    let nameLower = product.name.lowercased()
                    var inferredTier: String? = nil
                    if nameLower.contains("premium") {
                        inferredTier = "premium"
                    } else if nameLower.contains("elite") {
                        inferredTier = "elite"
                    } else if nameLower.contains("standard") {
                        inferredTier = "standard"
                    }
                    if let tier = inferredTier {
                        formDataComponents.append("metadata[membership_tier]=\(urlEncode(tier))")
                        print("✓ Inferred tier from product name: \(tier)")
                    }
                    break
                }
            }
        }
        
        // CRITICAL: Create customer with metadata FIRST, then use customer ID in checkout
        // The webhook expects auth0_id in customer metadata, not session metadata
        if let email = userEmail, !email.isEmpty {
            // Create customer with metadata first
            createStripeCustomer(email: email, auth0Id: auth0Id, membershipTier: membershipTier, stripeKey: stripeKey) { customerId in
                DispatchQueue.main.async {
                    var finalFormData = formDataComponents
                    
                    func urlEncode(_ value: String) -> String {
                        return value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                    }
                    
                    if let customerId = customerId {
                        // Use the customer ID we just created (has metadata)
                        finalFormData.append("customer=\(urlEncode(customerId))")
                        print("✓ Using customer with ID: \(customerId) (has metadata)")
                    } else {
                        // Fallback: use customer_email (will create customer but without metadata)
                        finalFormData.append("customer_email=\(urlEncode(email))")
                        print("⚠ Could not create customer with metadata, using customer_email: \(email)")
                        print("⚠ WARNING: Webhook may not find auth0_id in customer metadata!")
                    }
                    
                    // Create checkout session
                    self.createCheckoutSessionWithFormData(formDataComponents: finalFormData, planId: planId, auth0Id: auth0Id, userEmail: userEmail, membershipTier: membershipTier, stripeKey: stripeKey, successURL: successURL, cancelURL: cancelURL)
                }
            }
            return // Exit early - checkout session will be created in callback
        } else {
            print("⚠ No customer email available - webhook may have difficulty linking to user")
            // Continue without customer
            createCheckoutSessionWithFormData(formDataComponents: formDataComponents, planId: planId, auth0Id: auth0Id, userEmail: userEmail, membershipTier: membershipTier, stripeKey: stripeKey, successURL: successURL, cancelURL: cancelURL)
        }
    }
    
    // Helper function to create Stripe customer with metadata
    private func createStripeCustomer(email: String, auth0Id: String, membershipTier: String?, stripeKey: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://api.stripe.com/v1/customers") else {
            print("ERROR: Invalid Stripe customers API URL")
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(stripeKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        func urlEncode(_ value: String) -> String {
            return value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
        }
        
        var formDataComponents: [String] = []
        formDataComponents.append("email=\(urlEncode(email))")
        formDataComponents.append("metadata[auth0_id]=\(urlEncode(auth0Id))")
        
        if let tier = membershipTier, !tier.isEmpty {
            formDataComponents.append("metadata[membership_tier]=\(urlEncode(tier))")
        }
        
        let formData = formDataComponents.joined(separator: "&")
        request.httpBody = formData.data(using: .utf8)
        
        print("Creating Stripe customer with email: \(email), auth0_id: \(auth0Id)")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("ERROR: Failed to create Stripe customer: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 || httpResponse.statusCode == 201,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let customerId = json["id"] as? String else {
                print("ERROR: Failed to parse customer creation response")
                if let data = data, let jsonString = String(data: data, encoding: .utf8) {
                    print("Response: \(jsonString)")
                }
                completion(nil)
                return
            }
            
            print("✓ Successfully created Stripe customer: \(customerId)")
            completion(customerId)
        }.resume()
    }
    
    // Helper function to create checkout session with form data
    private func createCheckoutSessionWithFormData(formDataComponents: [String], planId: String, auth0Id: String, userEmail: String?, membershipTier: String?, stripeKey: String, successURL: String, cancelURL: String) {
        guard let url = URL(string: "https://api.stripe.com/v1/checkout/sessions") else {
            errorMessage = "Invalid Stripe API URL"
            print("ERROR: Invalid Stripe API URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(stripeKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        func urlEncode(_ value: String) -> String {
            return value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
        }
        
        let formData = formDataComponents.joined(separator: "&")
        request.httpBody = formData.data(using: .utf8)
        
        // Comprehensive logging
        if let bodyString = String(data: request.httpBody!, encoding: .utf8) {
            print("═══════════════════════════════════════════════")
            print("STRIPE CHECKOUT SESSION REQUEST:")
            print("═══════════════════════════════════════════════")
            print("Full request body:")
            print(bodyString)
            print("═══════════════════════════════════════════════")
        }
        
        isLoading = true
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Error creating checkout session: \(error.localizedDescription)"
                    print("ERROR: Network error: \(error.localizedDescription)")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("Stripe checkout session API response status: \(httpResponse.statusCode)")
                    
                    if httpResponse.statusCode != 200 && httpResponse.statusCode != 201 {
                        self.errorMessage = "Failed to create checkout session (Status: \(httpResponse.statusCode))"
                        print("ERROR: Non-success status code: \(httpResponse.statusCode)")
                        if let data = data, let jsonString = String(data: data, encoding: .utf8) {
                            print("Error response: \(jsonString)")
                        }
                    }
                }
                
                guard let data = data else {
                    self.errorMessage = "No data received from Stripe"
                    print("ERROR: No data in response")
                    return
                }
                
                // Log response for debugging
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("Stripe checkout session response: \(jsonString)")
                }
                
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.errorMessage = "Invalid response format. Please try again."
                    print("ERROR: Failed to parse JSON response")
                    return
                }
                
                // Check for Stripe errors
                if let error = json["error"] as? [String: Any] {
                    let errorMessage = error["message"] as? String ?? "Unknown Stripe error"
                    self.errorMessage = "Stripe error: \(errorMessage)"
                    print("ERROR: Stripe API error: \(error)")
                    return
                }
                
                guard let checkoutUrlString = json["url"] as? String else {
                    self.errorMessage = "No checkout URL in response. Please try again."
                    print("ERROR: 'url' key not found in response. Available keys: \(json.keys)")
                    return
                }
                
                guard let checkoutUrl = URL(string: checkoutUrlString) else {
                    self.errorMessage = "Invalid checkout URL format. Please try again."
                    print("ERROR: Invalid URL string: \(checkoutUrlString)")
                    return
                }
                
                // Extract checkout session ID for webhook tracking
                if let sessionId = json["id"] as? String {
                    print("═══════════════════════════════════════════════")
                    print("STRIPE CHECKOUT SESSION CREATED:")
                    print("═══════════════════════════════════════════════")
                    print("Session ID: \(sessionId)")
                    print("Client Reference ID: \(auth0Id)")
                    print("Customer Email: \(userEmail ?? "not provided")")
                    print("Checkout URL: \(checkoutUrlString)")
                    print("═══════════════════════════════════════════════")
                }
                
                print("Opening Stripe checkout in in-app Safari...")
                
                // Set the URL first
                self.stripeCheckoutURL = checkoutUrl
                print("✓ Set stripeCheckoutURL: \(checkoutUrl.absoluteString)")
                
                // Present the sheet
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.showStripeCheckout = true
                    print("✓ Set showStripeCheckout = true")
                }
            }
        }.resume()
    }
}

// MARK: - Step One: First Name and Date of Birth
struct StepOneView: View {
    @Binding var data: OnboardingData
    @State private var showDatePicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Personal Information")
                .poppins(.bold, size: 28)
            
            Text("Let's start with some basic information")
                .poppins(.regular, size: 16)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 16) {
                // First Name
                VStack(alignment: .leading, spacing: 8) {
                    Text("First Name *")
                        .poppins(.semibold, size: 14)
                    TextField("Enter your first name", text: $data.firstName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .poppins(.regular, size: 16)
                }
                
                // Date of Birth
                VStack(alignment: .leading, spacing: 8) {
                    Text("Date of Birth *")
                        .poppins(.semibold, size: 14)
                    
                    Button(action: {
                        showDatePicker.toggle()
                    }) {
                        HStack {
                            Text(formatDate(data.dateOfBirth))
                                .poppins(.regular, size: 16)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "calendar")
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    if showDatePicker {
                        DatePicker(
                            "Date of Birth",
                            selection: $data.dateOfBirth,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                    }
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
}

// MARK: - Step Two: Address
struct StepTwoView: View {
    @Binding var data: OnboardingData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Address")
                .poppins(.bold, size: 28)
            
            Text("Where are you located?")
                .poppins(.regular, size: 16)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 16) {
                // Address Line 1
                VStack(alignment: .leading, spacing: 8) {
                    Text("Address Line 1 *")
                        .poppins(.semibold, size: 14)
                    TextField("Enter address line 1", text: $data.addressLine1)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .poppins(.regular, size: 16)
                }
                
                // Address Line 2
                VStack(alignment: .leading, spacing: 8) {
                    Text("Address Line 2")
                        .poppins(.semibold, size: 14)
                    TextField("Enter address line 2 (optional)", text: $data.addressLine2)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .poppins(.regular, size: 16)
                }
                
                // City
                VStack(alignment: .leading, spacing: 8) {
                    Text("City *")
                        .poppins(.semibold, size: 14)
                    TextField("Enter city", text: $data.city)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .poppins(.regular, size: 16)
                }
                
                // Postcode
                VStack(alignment: .leading, spacing: 8) {
                    Text("Postcode *")
                        .poppins(.semibold, size: 14)
                    TextField("Enter postcode", text: $data.postcode)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .poppins(.regular, size: 16)
                        .autocapitalization(.allCharacters)
                }
            }
        }
    }
}

// MARK: - Step Three: Emergency Contact
struct StepThreeView: View {
    @Binding var data: OnboardingData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Emergency Contact")
                .poppins(.bold, size: 28)
            
            Text("Who should we contact in case of an emergency?")
                .poppins(.regular, size: 16)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 16) {
                // Emergency Contact Name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Contact Name *")
                        .poppins(.semibold, size: 14)
                    TextField("Enter contact name", text: $data.emergencyContactName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .poppins(.regular, size: 16)
                }
                
                // Emergency Contact Number
                VStack(alignment: .leading, spacing: 8) {
                    Text("Contact Number *")
                        .poppins(.semibold, size: 14)
                    TextField("Enter contact number", text: $data.emergencyContactNumber)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .poppins(.regular, size: 16)
                        .keyboardType(.phonePad)
                }
            }
        }
    }
}

// MARK: - Step Four: Subscription Plan
struct StepFourView: View {
    @Binding var data: OnboardingData
    @Binding var products: [StripeProduct]
    @Binding var isLoadingProducts: Bool
    @State private var showCheckout = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Choose a Plan")
                .poppins(.bold, size: 28)
            
            Text("Select a subscription plan to get started")
                .poppins(.regular, size: 16)
                .foregroundColor(.secondary)
            
            if isLoadingProducts {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if products.isEmpty {
                Text("No plans available at the moment. You can skip and choose a plan later.")
                    .poppins(.regular, size: 14)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(products) { product in
                            if let price = product.price {
                                PlanCard(
                                    product: product,
                                    price: price,
                                    isSelected: data.selectedPlanId == price.id,
                                    onSelect: {
                                        data.selectedPlanId = price.id
                                        print("✓ User selected plan with price ID: \(price.id)")
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Plan Card
struct PlanCard: View {
    let product: StripeProduct
    let price: StripePrice
    let isSelected: Bool
    var isDisabled: Bool = false
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: {
            if !isDisabled {
                onSelect()
            }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(product.name)
                            .poppins(.bold, size: 18)
                            .foregroundColor(isDisabled ? .gray : .primary)
                        
                        if isDisabled {
                            Text("(Current Plan)")
                                .poppins(.regular, size: 12)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    if let description = product.description {
                        Text(description)
                            .poppins(.regular, size: 14)
                            .foregroundColor(isDisabled ? .gray.opacity(0.7) : .secondary)
                    }
                    
                    if let recurring = price.recurring {
                        Text(formatPrice(price.amountValue, currency: price.currency, interval: recurring.interval))
                            .poppins(.semibold, size: 16)
                            .foregroundColor(isDisabled ? .gray : Color(red: 1.0, green: 0.42, blue: 0.42))
                            .padding(.top, 4)
                    }
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundColor(isDisabled ? .gray.opacity(0.5) : (isSelected ? Color(red: 1.0, green: 0.42, blue: 0.42) : .gray))
            }
            .padding()
            .background(isDisabled ? Color.gray.opacity(0.1) : (isSelected ? Color(red: 1.0, green: 0.42, blue: 0.42).opacity(0.1) : Color.gray.opacity(0.05)))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isDisabled ? Color.gray.opacity(0.3) : (isSelected ? Color(red: 1.0, green: 0.42, blue: 0.42) : Color.clear), lineWidth: 2)
            )
            .cornerRadius(12)
            .opacity(isDisabled ? 0.6 : 1.0)
        }
        .disabled(isDisabled)
    }
    
    private func formatPrice(_ amount: Int, currency: String, interval: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.uppercased()
        let price = Double(amount) / 100.0
        let priceString = formatter.string(from: NSNumber(value: price)) ?? "\(price)"
        return "\(priceString) / \(interval)"
    }
}

// MARK: - Stripe Checkout Safari View
// Using WKWebView instead of SFSafariViewController to intercept custom URL scheme redirects
import WebKit

struct StripeCheckoutSafariView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.translatesAutoresizingMaskIntoConstraints = false
        
        viewController.view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: viewController.view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor)
        ])
        
        // Add close button
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("✕", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 24, weight: .bold)
        closeButton.setTitleColor(.label, for: .normal)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(context.coordinator, action: #selector(Coordinator.closeTapped), for: .touchUpInside)
        viewController.view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        webView.load(URLRequest(url: url))
        context.coordinator.webView = webView
        
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var webView: WKWebView?
        
        @objc func closeTapped() {
            NotificationCenter.default.post(name: NSNotification.Name("StripeCheckoutCancel"), object: nil)
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            
            // Check if this is our custom URL scheme
            let bundleId = Bundle.main.bundleIdentifier ?? "com.anygym.app"
            if url.scheme == "com.anygym.app" || url.scheme == bundleId {
                print("✓ Intercepted custom URL scheme redirect: \(url.absoluteString)")
                decisionHandler(.cancel) // Cancel the navigation in webview
                
                // Open the URL in the app (this will trigger onOpenURL)
                DispatchQueue.main.async {
                    UIApplication.shared.open(url) { success in
                        if success {
                            print("✓ Successfully opened URL in app")
                        } else {
                            print("⚠ Failed to open URL in app")
                        }
                    }
                }
                return
            }
            
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // Check if the error is due to custom URL scheme
            let errorDescription = error.localizedDescription.lowercased()
            if errorDescription.contains("cannot be found") || errorDescription.contains("server") {
                // This might be our custom URL scheme being blocked
                if let url = webView.url, (url.scheme == "com.anygym.app" || url.scheme == Bundle.main.bundleIdentifier) {
                    print("✓ Detected custom URL scheme in error, opening in app")
                    DispatchQueue.main.async {
                        UIApplication.shared.open(url) { success in
                            if success {
                                print("✓ Successfully opened URL in app")
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AuthManager())
}
