//
//  Gym.swift
//  AnyGym
//
//  Created on iOS App
//

import Foundation
import CoreLocation

struct Gym: Codable, Identifiable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let address: String?
    let city: String?
    let country: String?
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct GymResponse: Codable {
    let gyms: [Gym]
}

