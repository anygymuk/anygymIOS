//
//  LoginView.swift
//  AnyGym
//
//  Created on iOS App
//

import SwiftUI
import SafariServices

// MARK: - Poppins Font Extension (if PoppinsFont.swift is not in target)
extension Font {
    static func poppins(_ weight: PoppinsWeight = .regular, size: CGFloat) -> Font {
        let fontName: String
        switch weight {
        case .regular:
            fontName = "Poppins-Regular"
        case .medium:
            fontName = "Poppins-Medium"
        case .semibold:
            fontName = "Poppins-SemiBold"
        case .bold:
            fontName = "Poppins-Bold"
        }
        
        // Check if font is available, fallback to system font if not
        if UIFont(name: fontName, size: size) != nil {
            return Font.custom(fontName, size: size)
        } else {
            // Fallback to system font with equivalent weight
            let systemWeight: Font.Weight
            switch weight {
            case .regular:
                systemWeight = .regular
            case .medium:
                systemWeight = .medium
            case .semibold:
                systemWeight = .semibold
            case .bold:
                systemWeight = .bold
            }
            return Font.system(size: size, weight: systemWeight)
        }
    }
    
    enum PoppinsWeight {
        case regular
        case medium
        case semibold
        case bold
    }
}

extension View {
    func poppins(_ weight: Font.PoppinsWeight = .regular, size: CGFloat = 16) -> some View {
        self.font(.poppins(weight, size: size))
    }
}

// MARK: - Safari View Controller Wrapper for Login
struct LoginSafariView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let safariVC = SFSafariViewController(url: url, configuration: config)
        safariVC.preferredControlTintColor = UIColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 1.0) // #FF6B6B
        return safariVC
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // No updates needed
    }
}

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var hasTriggeredLogin = false
    @State private var showSignupView = false
    @State private var signupURL: URL?
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // App Logo/Title
            VStack(spacing: 16) {
                
                Text("anygym")
                    .poppins(.bold, size: 34)
                
                Text("anybody, anywhere, anygym")
                    .poppins(.regular, size: 14)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Loading or Login Button
            if authManager.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 1.0, green: 0.42, blue: 0.42))) // #FF6B6B
                        .scaleEffect(1.5)
                    Text("Opening login...")
                        .poppins(.regular, size: 14)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 32)
            } else {
                VStack(spacing: 12) {
                    // Manual login button (fallback if auto-login didn't work or was cancelled)
                    Button(action: {
                        authManager.login()
                    }) {
                        Text("Log In")
                            .poppins(.semibold, size: 16)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(red: 1.0, green: 0.42, blue: 0.42)) // #FF6B6B
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    
                    // Create Account button
                    Button(action: {
                        if let url = authManager.getSignupURL() {
                            signupURL = url
                            showSignupView = true
                        }
                    }) {
                        Text("Create an Account")
                            .poppins(.semibold, size: 16)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.42)) // #FF6B6B
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(red: 1.0, green: 0.42, blue: 0.42), lineWidth: 2) // #FF6B6B
                            )
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 32)
            }
            
            // Error Message (only show if not a cancellation)
            if let errorMessage = authManager.errorMessage,
               !errorMessage.contains("cancelled") {
                Text(errorMessage)
                    .poppins(.regular, size: 12)
                    .foregroundColor(.red)
                    .padding(.horizontal, 32)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .padding()
        .sheet(isPresented: Binding(
            get: { showSignupView && signupURL != nil },
            set: { newValue in
                showSignupView = newValue
                if !newValue {
                    signupURL = nil
                }
            }
        )) {
            if let url = signupURL {
                LoginSafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .task {
            // Wait a moment for the window scene to be active, then trigger login
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            if !hasTriggeredLogin && !authManager.isLoading && !authManager.isAuthenticated {
                hasTriggeredLogin = true
                await MainActor.run {
                    authManager.login()
                }
            }
        }
        .onChange(of: authManager.errorMessage) { errorMessage in
            // If user cancelled or window scene error, clear the error and allow retry
            if let error = errorMessage {
                let lowercased = error.lowercased()
                if lowercased.contains("cancelled") || lowercased.contains("windowscene") || lowercased.contains("not in the foreground") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        authManager.errorMessage = nil
                        hasTriggeredLogin = false
                    }
                }
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}

