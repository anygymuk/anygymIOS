//
//  AnyGymApp.swift
//  AnyGym
//
//  Created on iOS App
//

import SwiftUI
import UserNotifications
import UIKit

@main
struct AnyGymApp: App {
    @StateObject private var authManager = AuthManager()
    
    init() {
        print("═══════════════════════════════════════════════")
        print("🚀 AnyGymApp: App initializing...")
        print("═══════════════════════════════════════════════")
        // Request notification permissions on app launch
        requestNotificationPermissions()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .onOpenURL { url in
                    handleURL(url)
                }
        }
    }
    
    private func requestNotificationPermissions() {
        // Check current authorization status first
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            print("📱 Current notification authorization status: \(settings.authorizationStatus.rawValue)")
            print("   - Alert: \(settings.alertSetting.rawValue)")
            print("   - Sound: \(settings.soundSetting.rawValue)")
            print("   - Badge: \(settings.badgeSetting.rawValue)")
            
            // Only request if not determined (first time) or if previously denied (to show settings)
            if settings.authorizationStatus == .notDetermined {
                print("🔄 Requesting notification permissions...")
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error = error {
                        print("❌ Error requesting notification permissions: \(error.localizedDescription)")
                    } else {
                        print("✅ Notification permission granted: \(granted)")
                        if granted {
                            // Register for remote notifications if needed in the future
                            DispatchQueue.main.async {
                                UIApplication.shared.registerForRemoteNotifications()
                            }
                        } else {
                            print("⚠️ Notification permission denied. User can enable in Settings → AnyGym → Notifications")
                        }
                    }
                }
            } else if settings.authorizationStatus == .denied {
                print("⚠️ Notification permissions were previously denied.")
                print("   To enable: Settings → AnyGym → Notifications")
            } else {
                print("✅ Notification permissions already authorized")
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
            } else if url.host == "activepass" || url.absoluteString.contains("activepass") {
                print("═══════════════════════════════════════════════")
                print("✓ AnyGymApp: Live Activity tapped - opening active pass")
                print("   Posting ShowActivePass notification...")
                print("═══════════════════════════════════════════════")
                // Post notification to show active pass panel
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ShowActivePass"),
                        object: nil,
                        userInfo: ["url": url]
                    )
                }
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

