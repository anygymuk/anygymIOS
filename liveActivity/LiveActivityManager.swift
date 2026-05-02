//
//  LiveActivityManager.swift
//  AnyGym
//
//  Manages Live Activities for active passes
//

import Foundation
import ActivityKit
import SwiftUI

@available(iOS 16.1, *)
class LiveActivityManager: ObservableObject {
    private var activity: Activity<PassActivityAttributes>?
    
    init() {
        // Initialize the manager
    }
    
    // Check if Live Activities are available
    var isAvailable: Bool {
        return ActivityAuthorizationInfo().areActivitiesEnabled
    }
    
    // Start a Live Activity for an active pass
    func startLiveActivity(for pass: Pass) {
        // Check availability
        guard isAvailable else {
            print("Live Activities are not available or not enabled")
            return
        }
        
        // Parse validUntil date
        guard let validUntilString = pass.validUntil else {
            print("Pass does not have a validUntil date")
            return
        }
        
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
        
        let contentState = PassActivityAttributes.ContentState(
            gymName: gymName,
            gymAddress: gymAddress,
            validUntil: validUntil,
            timeRemaining: timeRemaining,
            passCode: pass.passCode,
            status: pass.status ?? "active",
            gymChainName: pass.gymChainName
        )
        
        do {
            let activity = try Activity<PassActivityAttributes>.request(
                attributes: attributes,
                contentState: contentState,
                pushType: nil // Set to .token if you want push updates
            )
            self.activity = activity
            print("Live Activity started successfully for pass: \(pass.id)")
            return true
        } catch {
            print("Failed to start Live Activity: \(error.localizedDescription)")
            return false
        }
    }
    
    // Update the Live Activity with new pass data
    func updateLiveActivity(for pass: Pass) {
        guard let activity = activity else {
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
            await activity.end(dismissalPolicy: .immediate)
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
}
