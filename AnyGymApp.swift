//
//  AnyGymApp.swift
//  AnyGym
//
//  Created on iOS App
//

import SwiftUI

@main
struct AnyGymApp: App {
    @StateObject private var authManager = AuthManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
        }
    }
}

