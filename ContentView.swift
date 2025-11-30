//
//  ContentView.swift
//  AnyGym
//
//  Created on iOS App
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        Group {
            if !authManager.isAuthenticated {
                LoginView()
            } else if authManager.isLoadingUserData {
                // Show loading while fetching user data
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 1.0, green: 0.42, blue: 0.42)))
                        .scaleEffect(1.5)
                    Text("Loading...")
                        .poppins(.regular, size: 14)
                        .foregroundColor(.secondary)
                }
            } else if authManager.onboardingCompleted {
                MainView()
            } else {
                OnboardingView()
            }
        }
        .onAppear {
            // Check auth status on appear, which will auto-trigger login if not authenticated
            if !authManager.isAuthenticated {
                authManager.checkAuthStatus()
            } else if !authManager.isLoadingUserData && authManager.user?.sub != nil {
                // If authenticated but user data might be stale, refresh it
                print("ContentView: Refreshing user data on appear")
                authManager.fetchUserData(auth0Id: authManager.user!.sub)
            }
        }
        .onChange(of: authManager.onboardingCompleted) { newValue in
            print("ContentView: onboardingCompleted changed to \(newValue)")
        }
        .onChange(of: authManager.isLoadingUserData) { newValue in
            print("ContentView: isLoadingUserData changed to \(newValue)")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
}

