//
//  PassActivityWidget.swift
//  AnyGym
//
//  Widget Extension for Live Activities
//  Note: This file should be in a Widget Extension target
//

import WidgetKit
import SwiftUI
import ActivityKit

@available(iOS 16.1, *)
struct PassActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PassActivityAttributes.self) { context in
            // Lock Screen UI
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            // Minimal Dynamic Island implementation (disabled but required by API)
            DynamicIsland {
                // Minimal expanded region (required by API)
                DynamicIslandExpandedRegion(.leading) {
                    EmptyView()
                }
            } compactLeading: {
                EmptyView()
            } compactTrailing: {
                EmptyView()
            } minimal: {
                EmptyView()
            }
        }
    }
}

// MARK: - Lock Screen Live Activity View
@available(iOS 16.1, *)
struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<PassActivityAttributes>
    
    var body: some View {
        HStack(spacing: 12) {
            // Main Content
            VStack(alignment: .leading, spacing: 8) {
                // Logo above gym name
                Image("anygym-white")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 24)
                    .foregroundColor(.white)
                
                // Gym Name - Prominently displayed
                Text(context.state.gymName)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                if let address = context.state.gymAddress {
                    Text(address)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.9))
                    Text(context.state.timeRemaining)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            Spacer()
            
            // QR Code - Display pass code prominently
            if let passCode = context.state.passCode {
                VStack(spacing: 6) {
                    Image(systemName: "qrcode")
                        .font(.title)
                        .foregroundColor(.white)
                    Text(passCode)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: 80, height: 80)
                .background(Color.white.opacity(0.2))
                .cornerRadius(8)
            } else {
                // Default icon if no pass code
                Image(systemName: "figure.run")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 80, height: 80)
            }
        }
        .padding()
        .background(Color(red: 1.0, green: 0.42, blue: 0.42)) // #FF6B6B
    }
}
