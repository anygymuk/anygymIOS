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
            if authManager.isAuthenticated {
                MainView()
            } else {
                LoginView()
            }
        }
        .onAppear {
            // Check auth status on appear, which will auto-trigger login if not authenticated
            authManager.checkAuthStatus()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
}

