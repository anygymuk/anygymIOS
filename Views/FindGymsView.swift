//
//  FindGymsView.swift
//  AnyGym
//
//  Created on iOS App
//

import SwiftUI
import MapKit

struct FindGymsView: View {
    @StateObject private var gymService = GymService()
    @State private var searchText = ""
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 54.5, longitude: -2.0), // Center of UK
        span: MKCoordinateSpan(latitudeDelta: 12.0, longitudeDelta: 10.0)
    )
    
    var body: some View {
        ZStack {
            // Map View
            GymMapView(gyms: gymService.gyms, region: $region)
                .ignoresSafeArea()
            
            VStack {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                        .padding(.leading, 12)
                    
                    TextField("Search", text: $searchText)
                        .padding(.vertical, 10)
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .padding(.trailing, 12)
                        }
                    }
                }
                .background(Color.white)
                .cornerRadius(10)
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                Spacer()
            }
        }
        .onAppear {
            gymService.fetchGyms()
        }
    }
}

#Preview {
    FindGymsView()
}

