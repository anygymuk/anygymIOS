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
                .onOpenURL { url in
                    handleURL(url)
                }
        }
    }
    
    private func handleURL(_ url: URL) {
        print("═══════════════════════════════════════════════")
        print("AnyGymApp: handleURL called")
        print("APP RECEIVED URL: \(url.absoluteString)")
        print("URL Scheme: \(url.scheme ?? "nil")")
        print("URL Host: \(url.host ?? "nil")")
        print("URL Path: \(url.path)")
        print("═══════════════════════════════════════════════")
        
        // Handle Stripe checkout redirects
        let bundleId = Bundle.main.bundleIdentifier ?? "com.anygym.app"
        if url.scheme == "com.anygym.app" || url.scheme == bundleId {
            if url.host == "stripe-checkout-success" || url.absoluteString.contains("stripe-checkout-success") {
                print("═══════════════════════════════════════════════")
                print("✓ AnyGymApp: Stripe checkout completed successfully")
                print("   Posting StripeCheckoutSuccess notification...")
                print("═══════════════════════════════════════════════")
                // Post notification to dismiss Safari view and complete onboarding
                NotificationCenter.default.post(
                    name: NSNotification.Name("StripeCheckoutSuccess"),
                    object: nil,
                    userInfo: ["url": url]
                )
                print("✓ AnyGymApp: Notification posted successfully")
            } else if url.host == "stripe-checkout-cancel" || url.absoluteString.contains("stripe-checkout-cancel") {
                print("═══════════════════════════════════════════════")
                print("⚠ AnyGymApp: Stripe checkout was cancelled")
                print("   Posting StripeCheckoutCancel notification...")
                print("═══════════════════════════════════════════════")
                NotificationCenter.default.post(
                    name: NSNotification.Name("StripeCheckoutCancel"),
                    object: nil,
                    userInfo: ["url": url]
                )
                print("✓ AnyGymApp: Notification posted successfully")
            } else {
                print("⚠ AnyGymApp: URL scheme matches but host doesn't match expected patterns")
                print("   Host: \(url.host ?? "nil")")
                print("   Full URL: \(url.absoluteString)")
            }
        } else {
            print("⚠ AnyGymApp: URL scheme '\(url.scheme ?? "nil")' does not match expected scheme '\(bundleId)'")
        }
    }
}

