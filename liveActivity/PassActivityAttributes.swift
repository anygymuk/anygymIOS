//
//  PassActivityAttributes.swift
//  AnyGym
//
//  Live Activity Attributes for Active Pass
//

import ActivityKit
import Foundation

struct PassActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic state that can change
        var gymName: String
        var gymAddress: String?
        var validUntil: Date
        var timeRemaining: String
        var passCode: String?
        var qrcodeUrl: String?
        var status: String
        var gymChainName: String?
    }
    
    // Static attributes that don't change
    var passId: Int
    var gymId: Int
}
