//
//  LiveActivityManager.swift
//  AnyGym
//
//  Manages Live Activities for active passes
//

import Foundation
import ActivityKit
import SwiftUI
import UserNotifications

@available(iOS 16.1, *)
class LiveActivityManager: ObservableObject {
    private var activity: Activity<PassActivityAttributes>?
    
    init() {
        // Initialize the manager
    }
    
    // Check if Live Activities are available
    var isAvailable: Bool {
        let authInfo = ActivityAuthorizationInfo()
        let enabled = authInfo.areActivitiesEnabled
        print("📊 Live Activity Authorization Status:")
        print("   areActivitiesEnabled: \(enabled)")
        if #available(iOS 16.2, *) {
            print("   frequentPushesEnabled: \(authInfo.frequentPushesEnabled)")
        }
        return enabled
    }
    
    // Start a Live Activity for an active pass
    func startLiveActivity(for pass: Pass) {
        print("═══════════════════════════════════════════════")
        print("🔴 LiveActivityManager: startLiveActivity called")
        print("   Pass ID: \(pass.id)")
        print("   Gym: \(pass.gymName ?? "Unknown")")
        print("   Thread: \(Thread.isMainThread ? "Main" : "Background")")
        print("═══════════════════════════════════════════════")
        
        // Ensure we're on the main thread for UI-related operations
        guard Thread.isMainThread else {
            print("⚠️ Not on main thread, dispatching to main...")
            DispatchQueue.main.async { [weak self] in
                self?.startLiveActivity(for: pass)
            }
            return
        }
        
        // Check for any existing activities (only one allowed per app)
        let existingActivities = Activity<PassActivityAttributes>.activities
        if !existingActivities.isEmpty {
            print("⚠️ Found \(existingActivities.count) existing Live Activity(ies)")
            for existing in existingActivities {
                print("   - Activity ID: \(existing.id), Pass ID: \(existing.attributes.passId)")
                if existing.attributes.passId == pass.id {
                    print("   Same pass - updating existing activity...")
                    // Store reference and update
                    self.activity = existing
                    updateLiveActivity(for: pass)
                    return
                } else {
                    print("   Different pass - ending old activity...")
                    // End any other activities
                    Task {
                        await existing.end(dismissalPolicy: .immediate)
                    }
                }
            }
        }
        
        // Check if we have a stored activity reference
        if let storedActivity = activity {
            if storedActivity.attributes.passId == pass.id {
                print("ℹ️ Updating stored activity for pass \(pass.id)...")
                updateLiveActivity(for: pass)
                return
            } else {
                print("ℹ️ Stored activity is for different pass - clearing...")
                self.activity = nil
            }
        }
        
        // Check notification permissions first (required for Live Activities)
        checkAndRequestNotificationPermissions()
        
        // Check availability
        guard isAvailable else {
            print("❌ Live Activities are not available or not enabled")
            print("   Check: Settings → Face ID & Passcode → Live Activities")
            return
        }
        print("✅ Live Activities are available")
        
        // Parse validUntil date
        guard let validUntilString = pass.validUntil else {
            print("❌ Pass does not have a validUntil date")
            return
        }
        print("✅ Pass has validUntil: \(validUntilString)")
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let validUntilDate = dateFormatter.date(from: validUntilString) else {
            // Try without fractional seconds
            dateFormatter.formatOptions = [.withInternetDateTime]
            guard let date = dateFormatter.date(from: validUntilString) else {
                print("Failed to parse validUntil date: \(validUntilString)")
                return
            }
            _ = startActivityWithDate(pass: pass, validUntil: date)
            return
        }
        
        _ = startActivityWithDate(pass: pass, validUntil: validUntilDate)
    }
    
    private func startActivityWithDate(pass: Pass, validUntil: Date) -> Bool {
        let attributes = PassActivityAttributes(
            passId: pass.id,
            gymId: pass.gymId
        )
        
        let gymName = pass.gymName ?? pass.gymChainName ?? "Gym"
        var gymAddress: String? = nil
        if let address = pass.gymAddress {
            var components: [String] = [address]
            if let city = pass.gymCity {
                components.append(city)
            }
            if let postcode = pass.gymPostcode {
                components.append(postcode)
            }
            gymAddress = components.joined(separator: ", ")
        }
        
        let timeRemaining = calculateTimeRemaining(until: validUntil)
        
        print("📋 Creating ContentState with:")
        print("   Gym Name: \(gymName)")
        print("   QR Code URL: \(pass.qrcodeUrl ?? "nil")")
        print("   Pass Code: \(pass.passCode ?? "nil")")
        print("   Valid Until: \(validUntil)")
        
        let contentState = PassActivityAttributes.ContentState(
            gymName: gymName,
            gymAddress: gymAddress,
            validUntil: validUntil,
            timeRemaining: timeRemaining,
            passCode: pass.passCode,
            qrcodeUrl: pass.qrcodeUrl,
            status: pass.status ?? "active",
            gymChainName: pass.gymChainName
        )
        
        do {
            print("📱 Requesting Live Activity...")
            print("   Attributes: passId=\(attributes.passId), gymId=\(attributes.gymId)")
            print("   ContentState: gymName=\(contentState.gymName), passCode=\(contentState.passCode ?? "nil")")
            
            // Create URL for deep linking to active pass
            let bundleId = Bundle.main.bundleIdentifier ?? "com.anygym.app"
            let deepLinkURL = URL(string: "\(bundleId)://activepass?passId=\(pass.id)")!
            print("🔗 Deep link URL: \(deepLinkURL.absoluteString)")
            
            // Wrap in autoreleasepool to prevent memory issues
            let activity = try autoreleasepool {
                try Activity<PassActivityAttributes>.request(
                    attributes: attributes,
                    contentState: contentState,
                    pushType: nil // Set to .token if you want push updates
                )
            }
            
            // Note: The URL is handled via widgetURL modifier in the widget view
            
            self.activity = activity
            print("✅ Live Activity started successfully!")
            print("   Activity ID: \(activity.id)")
            print("   Activity State: \(activity.activityState)")
            print("   Check Lock Screen or Dynamic Island")
            print("═══════════════════════════════════════════════")
            return true
        } catch {
            print("❌ Failed to start Live Activity:")
            print("   Error: \(error.localizedDescription)")
            print("   Error Type: \(type(of: error))")
            if let nsError = error as NSError? {
                print("   Error Domain: \(nsError.domain)")
                print("   Error Code: \(nsError.code)")
                print("   Error UserInfo: \(nsError.userInfo)")
            }
            print("═══════════════════════════════════════════════")
            return false
        }
    }
    
    // Update the Live Activity with new pass data
    func updateLiveActivity(for pass: Pass) {
        guard activity != nil else {
            // Try to start if not already started
            startLiveActivity(for: pass)
            return
        }
        
        guard let validUntilString = pass.validUntil else {
            return
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let validUntilDate = dateFormatter.date(from: validUntilString) else {
            dateFormatter.formatOptions = [.withInternetDateTime]
            guard let date = dateFormatter.date(from: validUntilString) else {
                return
            }
            updateActivityWithDate(pass: pass, validUntil: date)
            return
        }
        
        updateActivityWithDate(pass: pass, validUntil: validUntilDate)
    }
    
    private func updateActivityWithDate(pass: Pass, validUntil: Date) {
        guard let activity = activity else { return }
        
        let gymName = pass.gymName ?? pass.gymChainName ?? "Gym"
        var gymAddress: String? = nil
        if let address = pass.gymAddress {
            var components: [String] = [address]
            if let city = pass.gymCity {
                components.append(city)
            }
            if let postcode = pass.gymPostcode {
                components.append(postcode)
            }
            gymAddress = components.joined(separator: ", ")
        }
        
        let timeRemaining = calculateTimeRemaining(until: validUntil)
        
        let contentState = PassActivityAttributes.ContentState(
            gymName: gymName,
            gymAddress: gymAddress,
            validUntil: validUntil,
            timeRemaining: timeRemaining,
            passCode: pass.passCode,
            qrcodeUrl: pass.qrcodeUrl,
            status: pass.status ?? "active",
            gymChainName: pass.gymChainName
        )
        
        Task {
            await activity.update(using: contentState)
            print("Live Activity updated for pass: \(pass.id)")
        }
    }
    
    // End the Live Activity
    func endLiveActivity() {
        guard let activity = activity else { return }
        
        Task {
            // Use the non-deprecated API for iOS 16.2+
            if #available(iOS 16.2, *) {
                let finalContentState = PassActivityAttributes.ContentState(
                    gymName: activity.content.state.gymName,
                    gymAddress: activity.content.state.gymAddress,
                    validUntil: activity.content.state.validUntil,
                    timeRemaining: "Expired",
                    passCode: activity.content.state.passCode,
                    status: "expired",
                    gymChainName: activity.content.state.gymChainName
                )
                await activity.end(using: finalContentState, dismissalPolicy: .immediate)
            } else {
                // Fallback for iOS 16.1
                await activity.end(dismissalPolicy: .immediate)
            }
            self.activity = nil
            print("Live Activity ended")
        }
    }
    
    // Calculate time remaining until expiration
    private func calculateTimeRemaining(until date: Date) -> String {
        let now = Date()
        let timeInterval = date.timeIntervalSince(now)
        
        if timeInterval <= 0 {
            return "Expired"
        }
        
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) / 60 % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m remaining"
        } else {
            return "\(minutes)m remaining"
        }
    }
    
    // Check and request notification permissions if needed
    private func checkAndRequestNotificationPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            print("📱 Notification Settings Check:")
            print("   Authorization Status: \(settings.authorizationStatus.rawValue)")
            
            if settings.authorizationStatus == .notDetermined {
                print("🔄 Requesting notification permissions...")
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error = error {
                        print("❌ Error requesting notification permissions: \(error.localizedDescription)")
                    } else {
                        print("✅ Notification permission result: \(granted)")
                        if granted {
                            DispatchQueue.main.async {
                                UIApplication.shared.registerForRemoteNotifications()
                            }
                        } else {
                            print("⚠️ Notification permission denied. Enable in Settings → AnyGym → Notifications")
                        }
                    }
                }
            } else if settings.authorizationStatus == .denied {
                print("⚠️ Notification permissions denied. Enable in Settings → AnyGym → Notifications")
            } else {
                print("✅ Notification permissions already authorized")
            }
        }
    }
}
