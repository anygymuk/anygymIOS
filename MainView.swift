//
//  MainView.swift
//  AnyGym
//
//  Created on iOS App
//

import SwiftUI
import MapKit
import CoreLocation
import Foundation
import Combine
import Auth0
import PassKit
import SafariServices

// MARK: - Gym Model
struct Gym: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let latitude: Double?
    let longitude: Double?
    let address: String?
    let city: String?
    let country: String?
    let postcode: String?
    let gymChainId: Int?
    let gymChainName: String?
    let gymChainLogo: String?
    let requiredTier: String?
    let amenities: [String]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case latitude
        case longitude
        case address
        case city
        case country
        case postcode
        case gymChainId = "gym_chain_id"
        case gymChainName = "gym_chain_name"
        case gymChainLogo = "gym_chain_logo"
        case requiredTier = "required_tier"
        case amenities
    }
    
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else {
            return nil
        }
        // Validate coordinates are in reasonable ranges
        guard lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180 else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    var hasValidLocation: Bool {
        coordinate != nil
    }
    
    static func == (lhs: Gym, rhs: Gym) -> Bool {
        lhs.id == rhs.id
    }
}

struct GymResponse: Codable {
    let gyms: [Gym]
}


// MARK: - Gym Chain Model (for nested gym_chain in GymDetail)
struct GymDetailChain: Codable {
    let id: Int?
    let name: String?
    let logoUrl: String?
    let description: String?
    let terms: String?
    let termsUrl: String?
    let healthStatement: String?
    let healthStatementUrl: String?
    let useTermsUrl: Bool?
    let useHealthStatementUrl: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case logoUrl = "logo_url"
        case description
        case terms
        case termsUrl = "terms_url"
        case healthStatement = "health_statement"
        case healthStatementUrl = "health_statement_url"
        case useTermsUrl = "use_terms_url"
        case useHealthStatementUrl = "use_health_statement_url"
    }
    
    var hasTerms: Bool {
        (termsUrl != nil && !termsUrl!.isEmpty) || (terms != nil && !terms!.isEmpty)
    }
    
    var hasHealthStatement: Bool {
        (healthStatementUrl != nil && !healthStatementUrl!.isEmpty) || (healthStatement != nil && !healthStatement!.isEmpty)
    }
}

// MARK: - Gym Detail Model
struct GymDetail: Codable {
    let id: Int
    let name: String
    let latitude: Double?
    let longitude: Double?
    let address: String?
    let city: String?
    let country: String?
    let postcode: String?
    let gymChainId: Int?
    let gymChainName: String?
    let gymChainLogo: String?
    let gymChain: GymDetailChain? // Nested gym_chain object
    let requiredTier: String?
    let amenities: [String]?
    let description: String?
    let openingHours: [String]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case latitude
        case longitude
        case address
        case city
        case country
        case postcode
        case gymChainId = "gym_chain_id"
        case gymChainName = "gym_chain_name"
        case gymChainLogo = "gym_chain_logo"
        case gymChain = "gym_chain"
        case requiredTier = "required_tier"
        case amenities
        case description
        case openingHours = "opening_hours"
    }
    
    // Computed property to get logo URL from either flat or nested structure
    var logoUrl: String? {
        // First try nested gym_chain.logo_url
        if let nestedLogo = gymChain?.logoUrl, !nestedLogo.isEmpty {
            return nestedLogo
        }
        // Fall back to flat gym_chain_logo
        if let flatLogo = gymChainLogo, !flatLogo.isEmpty {
            return flatLogo
        }
        return nil
    }
    
    // Computed property to get chain name from either flat or nested structure
    var chainName: String? {
        if let nestedName = gymChain?.name, !nestedName.isEmpty {
            return nestedName
        }
        if let flatName = gymChainName, !flatName.isEmpty {
            return flatName
        }
        return nil
    }
}

// MARK: - Gym Service
class GymService: ObservableObject {
    @Published var gyms: [Gym] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let baseURL = "https://api.any-gym.com"
    private var cancellables = Set<AnyCancellable>()
    
    func fetchGyms() {
        isLoading = true
        errorMessage = nil
        
        guard let url = URL(string: "\(baseURL)/gyms") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        
        URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .tryMap { data -> [Gym] in
                // Decode with snake_case conversion since API uses snake_case
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                
                do {
                    // Try to decode as array directly (which is what the API returns)
                    let gyms = try decoder.decode([Gym].self, from: data)
                    print("Successfully decoded \(gyms.count) gyms from API")
                    return gyms
                } catch let decodingError as DecodingError {
                    print("Decoding error: \(decodingError)")
                    
                    // Try to decode individual gyms to find the problematic one
                    if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                        var validGyms: [Gym] = []
                        for (index, gymDict) in jsonArray.enumerated() {
                            if let gymData = try? JSONSerialization.data(withJSONObject: gymDict),
                               let gym = try? decoder.decode(Gym.self, from: gymData) {
                                validGyms.append(gym)
                            } else {
                                print("Failed to decode gym at index \(index). Keys: \(gymDict.keys.joined(separator: ", "))")
                                if let jsonString = try? JSONSerialization.data(withJSONObject: gymDict),
                                   let string = String(data: jsonString, encoding: .utf8) {
                                    print("Problematic gym JSON: \(string)")
                                }
                            }
                        }
                        if !validGyms.isEmpty {
                            print("Decoded \(validGyms.count) out of \(jsonArray.count) gyms")
                            return validGyms
                        }
                    }
                    
                    throw decodingError
                } catch {
                    print("Unexpected error: \(error)")
                    throw error
                }
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                        print("Error fetching gyms: \(error)")
                    }
                },
                receiveValue: { [weak self] gyms in
                    print("Successfully fetched \(gyms.count) gyms")
                    self?.gyms = gyms
                    self?.isLoading = false
                }
            )
            .store(in: &cancellables)
    }
}

// MARK: - Gym Chain Model
struct GymChain: Codable, Identifiable {
    let id: Int
    let name: String
    let logoUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case logoUrl = "logo_url"
    }
}

// MARK: - Gym Search Service
class GymSearchService: ObservableObject {
    @Published var gyms: [Gym] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var chains: [GymChain] = []
    
    private let baseURL = "https://api.any-gym.com"
    private var cancellables = Set<AnyCancellable>()
    private var searchWorkItem: DispatchWorkItem?
    
    // Debounced search function
    func searchGyms(searchQuery: String, tier: String?, chainId: String?) {
        // Cancel previous search if any
        searchWorkItem?.cancel()
        
        // Create new work item
        let workItem = DispatchWorkItem { [weak self] in
            self?.performSearch(searchQuery: searchQuery, tier: tier, chainId: chainId)
        }
        
        searchWorkItem = workItem
        
        // Debounce: wait 300ms after user stops typing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
    
    // Immediate search (for filter changes)
    func searchGymsImmediate(searchQuery: String, tier: String?, chainId: String?) {
        searchWorkItem?.cancel()
        performSearch(searchQuery: searchQuery, tier: tier, chainId: chainId)
    }
    
    private func performSearch(searchQuery: String, tier: String?, chainId: String?) {
        isLoading = true
        errorMessage = nil
        
        // Build query parameters
        var components = URLComponents(string: "\(baseURL)/api/gyms/search")
        var queryItems: [URLQueryItem] = []
        
        if !searchQuery.isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: searchQuery))
        }
        
        if let tier = tier, tier != "All Tiers" {
            queryItems.append(URLQueryItem(name: "tier", value: tier))
        }
        
        if let chainId = chainId, chainId != "All Chains" {
            queryItems.append(URLQueryItem(name: "chain", value: chainId))
        }
        
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        
        guard let url = components?.url else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        
        let request = URLRequest(url: url)
        // Add authentication header if needed (get from AuthManager)
        // For now, assuming the session handles auth
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .tryMap { data -> [Gym] in
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                
                // Try to decode as wrapped response first
                if let response = try? decoder.decode(GymResponse.self, from: data) {
                    return response.gyms
                }
                
                // Try to decode as array directly
                return try decoder.decode([Gym].self, from: data)
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                        print("Error searching gyms: \(error)")
                        // Keep previous gym list on error
                    }
                },
                receiveValue: { [weak self] gyms in
                    self?.gyms = gyms.filter { $0.hasValidLocation }
                    self?.isLoading = false
                    print("Search returned \(gyms.count) gyms")
                }
            )
            .store(in: &cancellables)
    }
    
    // Fetch chains for filter dropdown
    func fetchChains() {
        guard let url = URL(string: "\(baseURL)/api/chains") else {
            return
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .decode(type: [GymChain].self, decoder: decoder)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("Error fetching chains: \(error)")
                    }
                },
                receiveValue: { [weak self] chains in
                    self?.chains = chains
                    print("Fetched \(chains.count) chains")
                }
            )
            .store(in: &cancellables)
    }
}

// MARK: - Gym Detail Response
struct GymDetailResponse: Codable {
    let gym: GymDetail?
    let gymChain: GymDetailChain?
    
    enum CodingKeys: String, CodingKey {
        case gym
        case gymChain = "gym_chain"
    }
}

// MARK: - Generate Pass Response
struct GeneratePassResponse: Codable {
    let success: Bool
    let message: String
}

// MARK: - Error Response
struct ErrorResponse: Codable {
    let error: String?
    let message: String?
    
    var errorMessage: String {
        return error ?? message ?? "An unknown error occurred"
    }
}

// MARK: - Pass Generation Error
enum PassGenerationError: LocalizedError {
    case forbidden(String)
    case badRequest(String)
    case notFound(String)
    case serverError(String)
    case networkError(Error)
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .forbidden(let message):
            return message
        case .badRequest(let message):
            return message
        case .notFound(let message):
            return message
        case .serverError(let message):
            return message
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unknown(let message):
            return message
        }
    }
}

// MARK: - Gym Detail Service
class GymDetailService: ObservableObject {
    @Published var gymDetail: GymDetail?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let baseURL = "https://api.any-gym.com"
    private var cancellables = Set<AnyCancellable>()
    
    func fetchGymDetail(gymId: Int) {
        isLoading = true
        errorMessage = nil
        gymDetail = nil
        
        guard let url = URL(string: "\(baseURL)/gyms/\(gymId)") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        
        URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .handleEvents(receiveOutput: { data in
                // Log raw JSON response for debugging
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("Raw API Response (first 1000 chars): \(String(jsonString.prefix(1000)))")
                }
            })
            .tryMap { data -> GymDetail in
                let decoder = JSONDecoder()
                // Try to decode as wrapped response first
                if let response = try? decoder.decode(GymDetailResponse.self, from: data),
                   let gym = response.gym {
                    // Chain data should already be in the gym object
                    return gym
                }
                // Fallback to direct decode
                do {
                    let detail = try decoder.decode(GymDetail.self, from: data)
                    print("Decoding successful")
                    print("  - gymChain object: \(detail.gymChain != nil ? "exists" : "nil")")
                    if let chain = detail.gymChain {
                        print("  - gymChain.id: \(chain.id?.description ?? "nil")")
                        print("  - gymChain.name: \(chain.name ?? "nil")")
                        print("  - gymChain.logoUrl: \(chain.logoUrl ?? "nil")")
                    }
                    return detail
                } catch {
                    print("Decoding error: \(error)")
                    if let decodingError = error as? DecodingError {
                        switch decodingError {
                        case .keyNotFound(let key, let context):
                            print("Key not found: \(key.stringValue), path: \(context.codingPath)")
                        case .typeMismatch(let type, let context):
                            print("Type mismatch: \(type), path: \(context.codingPath)")
                        case .valueNotFound(let type, let context):
                            print("Value not found: \(type), path: \(context.codingPath)")
                        case .dataCorrupted(let context):
                            print("Data corrupted: \(context)")
                        @unknown default:
                            print("Unknown decoding error")
                        }
                    }
                    throw error
                }
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                        print("Error fetching gym detail: \(error)")
                    }
                },
                receiveValue: { [weak self] detail in
                    self?.gymDetail = detail
                    self?.isLoading = false
                    print("Gym detail loaded:")
                    print("  - Flat gym_chain_logo: \(detail.gymChainLogo ?? "nil")")
                    print("  - Nested gym_chain?.logo_url: \(detail.gymChain?.logoUrl ?? "nil")")
                    print("  - Computed logoUrl: \(detail.logoUrl ?? "nil")")
                }
            )
            .store(in: &cancellables)
    }
}

// MARK: - Tab Enum
enum Tab: String, CaseIterable {
    case findGyms = "Find Gyms"
    case myPasses = "My Passes"
    case profile = "Profile"
    
    var icon: String {
        switch self {
        case .findGyms:
            return "mappin.circle.fill"
        case .myPasses:
            return "rectangle.stack.fill"
        case .profile:
            return "person.fill"
        }
    }
}

// MARK: - Gym Map View
struct GymMapView: UIViewRepresentable {
    let gyms: [Gym]
    @Binding var region: MKCoordinateRegion
    var selectedGymId: Int? // Selected gym to exclude from clustering
    var onGymSelected: ((Int) -> Void)?
    var onClusterTapped: (() -> Void)? // Handler for cluster taps
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        let coordinator = context.coordinator
        coordinator.parent = self
        mapView.delegate = coordinator
        mapView.setRegion(region, animated: false)
        mapView.showsUserLocation = false
        mapView.mapType = .mutedStandard // Lighter, more minimal appearance
        // Make the map appear lighter/more minimal
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.showsCompass = false
        mapView.showsScale = false
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update region if it changed significantly
        let currentCenter = mapView.region.center
        let newCenter = region.center
        let currentSpan = mapView.region.span
        let newSpan = region.span
        
        let centerChanged = abs(currentCenter.latitude - newCenter.latitude) > 0.001 || 
                           abs(currentCenter.longitude - newCenter.longitude) > 0.001
        let spanChanged = abs(currentSpan.latitudeDelta - newSpan.latitudeDelta) > 0.01 ||
                         abs(currentSpan.longitudeDelta - newSpan.longitudeDelta) > 0.01
        
        if centerChanged || spanChanged {
            mapView.setRegion(region, animated: true)
        }
        
        // Check if gyms have changed
        let gymsChanged = gyms.count != context.coordinator.previousGymsCount ||
                         gyms.map { $0.id } != context.coordinator.previousGymIds
        
        if gymsChanged {
            context.coordinator.previousGymsCount = gyms.count
            context.coordinator.previousGymIds = gyms.map { $0.id }
            print("Gyms changed: \(gyms.count) gyms")
        }
        
        // Update annotations when region or gyms change
        // Use a slight delay to ensure map view has updated after region change
        DispatchQueue.main.async {
            self.updateAnnotations(for: mapView, region: mapView.region)
        }
        
        // Store reference to parent for delegate callbacks
        context.coordinator.parent = self
    }
    
    private func updateAnnotations(for mapView: MKMapView, region: MKCoordinateRegion) {
        // Remove existing gym annotations
        let existingAnnotations = mapView.annotations.filter { $0 is GymClusterAnnotation }
        mapView.removeAnnotations(existingAnnotations)
        
        guard !gyms.isEmpty else {
            return
        }
        
        // Filter gyms with valid locations and prioritize visible ones
        let validGyms = gyms.filter { $0.hasValidLocation }
        
        // Get visible gyms in current viewport for chunked loading
        let visibleGyms = getVisibleGyms(gyms: validGyms, region: region)
        
        // Separate selected gym from others (selected gym is excluded from clustering)
        let selectedGym = visibleGyms.first { $0.id == selectedGymId }
        let otherGyms = visibleGyms.filter { $0.id != selectedGymId }
        
        // Calculate pixel distance threshold based on zoom level
        let span = max(region.span.latitudeDelta, region.span.longitudeDelta)
        let pixelThreshold: CGFloat
        
        if span > 5.0 {
            pixelThreshold = 100 // Very zoomed out - large clusters
        } else if span > 2.0 {
            pixelThreshold = 80
        } else if span > 0.5 {
            pixelThreshold = 60
        } else {
            pixelThreshold = 40 // Zoomed in - smaller clusters
        }
        
        // Cluster gyms using pixel-based algorithm (chunked for performance)
        var clusteredAnnotations = clusterGymsByPixelDistance(
            gyms: otherGyms,
            mapView: mapView,
            region: region,
            pixelThreshold: pixelThreshold
        )
        
        // Add selected gym separately if it exists (always rendered individually, never clustered)
        if let selected = selectedGym, let coord = selected.coordinate {
            let selectedAnnotation = GymClusterAnnotation(
                coordinate: coord,
                gymCount: 1,
                gymId: selected.id,
                isSelected: true,
                gym: selected
            )
            clusteredAnnotations.append(selectedAnnotation)
        }
        
        // Add annotations in chunks for better performance with large datasets
        addAnnotationsChunked(annotations: clusteredAnnotations, to: mapView, chunkSize: 100)
    }
    
    // Get visible gyms in current viewport
    private func getVisibleGyms(gyms: [Gym], region: MKCoordinateRegion) -> [Gym] {
        let center = region.center
        let span = region.span
        
        return gyms.filter { gym in
            guard let lat = gym.latitude, let lon = gym.longitude else {
                return false
            }
            
            // Add buffer to include gyms slightly outside viewport
            let buffer = 0.1
            return lat >= center.latitude - span.latitudeDelta / 2 - buffer &&
                   lat <= center.latitude + span.latitudeDelta / 2 + buffer &&
                   lon >= center.longitude - span.longitudeDelta / 2 - buffer &&
                   lon <= center.longitude + span.longitudeDelta / 2 + buffer
        }
    }
    
    // Add annotations in chunks to prevent UI blocking
    private func addAnnotationsChunked(annotations: [GymClusterAnnotation], to mapView: MKMapView, chunkSize: Int) {
        // For small numbers, add all at once
        guard annotations.count > chunkSize else {
            mapView.addAnnotations(annotations)
            return
        }
        
        // Add in chunks with slight delay to keep UI responsive
        for i in stride(from: 0, to: annotations.count, by: chunkSize) {
            let chunk = Array(annotations[i..<min(i + chunkSize, annotations.count)])
            DispatchQueue.main.async {
                mapView.addAnnotations(chunk)
            }
        }
    }
    
    // Calculate meters per pixel for coordinate-to-pixel conversion
    private func calculateMetersPerPixel(mapView: MKMapView, region: MKCoordinateRegion) -> Double {
        let mapRect = mapView.visibleMapRect
        let mapRectWidth = mapRect.size.width
        let worldCoordinateWidth = region.span.longitudeDelta * 111000.0 * cos(region.center.latitude * .pi / 180.0)
        return worldCoordinateWidth / Double(mapRectWidth)
    }
    
    // Cluster gyms based on pixel distance threshold
    private func clusterGymsByPixelDistance(
        gyms: [Gym],
        mapView: MKMapView,
        region: MKCoordinateRegion,
        pixelThreshold: CGFloat
    ) -> [GymClusterAnnotation] {
        var clusters: [GymClusterAnnotation] = []
        var processedGyms = Set<Int>()
        
        for gym in gyms {
            guard !processedGyms.contains(gym.id),
                  let coord = gym.coordinate else { continue }
            
            // Find all gyms within pixel threshold
            var clusterGyms: [Gym] = [gym]
            processedGyms.insert(gym.id)
            
            for otherGym in gyms {
                guard !processedGyms.contains(otherGym.id),
                      let otherCoord = otherGym.coordinate else { continue }
                
                let pixelDistance = calculatePixelDistance(
                    coord1: coord,
                    coord2: otherCoord,
                    mapView: mapView,
                    region: region
                )
                
                if pixelDistance <= pixelThreshold {
                    clusterGyms.append(otherGym)
                    processedGyms.insert(otherGym.id)
                }
            }
            
            // Create cluster annotation
            let clusterCoord: CLLocationCoordinate2D
            if clusterGyms.count > 1 {
                let avgLat = clusterGyms.compactMap { $0.latitude }.reduce(0, +) / Double(clusterGyms.count)
                let avgLon = clusterGyms.compactMap { $0.longitude }.reduce(0, +) / Double(clusterGyms.count)
                clusterCoord = CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
            } else {
                clusterCoord = coord
            }
            
            let annotation = GymClusterAnnotation(
                coordinate: clusterCoord,
                gymCount: clusterGyms.count,
                gymId: clusterGyms.count == 1 ? clusterGyms.first?.id : nil,
                isSelected: false,
                gym: clusterGyms.count == 1 ? clusterGyms.first : nil
            )
            clusters.append(annotation)
        }
        
        return clusters
    }
    
    // Calculate pixel distance between two coordinates
    private func calculatePixelDistance(
        coord1: CLLocationCoordinate2D,
        coord2: CLLocationCoordinate2D,
        mapView: MKMapView,
        region: MKCoordinateRegion
    ) -> CGFloat {
        let point1 = mapView.convert(coord1, toPointTo: mapView)
        let point2 = mapView.convert(coord2, toPointTo: mapView)
        let dx = point1.x - point2.x
        let dy = point1.y - point2.y
        return sqrt(dx * dx + dy * dy)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: GymMapView?
        var previousGymsCount: Int = 0
        var previousGymIds: [Int] = []
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Update annotations when user zooms/pans
            parent?.updateAnnotations(for: mapView, region: mapView.region)
        }
        
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let gymAnnotation = view.annotation as? GymClusterAnnotation else {
                return
            }
            
            if gymAnnotation.gymCount > 1 {
                // Cluster tapped - recenter on cluster and zoom in one level
                let currentSpan = mapView.region.span
                let newSpan = MKCoordinateSpan(
                    latitudeDelta: currentSpan.latitudeDelta * 0.5,
                    longitudeDelta: currentSpan.longitudeDelta * 0.5
                )
                // Use the cluster's coordinate as the center, not the current map center
                let newRegion = MKCoordinateRegion(center: gymAnnotation.coordinate, span: newSpan)
                mapView.setRegion(newRegion, animated: true)
                parent?.onClusterTapped?()
            } else if let gymId = gymAnnotation.gymId {
                // Individual gym tapped
                parent?.onGymSelected?(gymId)
            }
        }
        
        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
            guard let gymAnnotation = view.annotation as? GymClusterAnnotation,
                  let gymId = gymAnnotation.gymId else {
                return
            }
            parent?.onGymSelected?(gymId)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let gymAnnotation = annotation as? GymClusterAnnotation else {
                return nil
            }
            
            // Use different identifiers for selected, individual, and cluster markers
            let identifier = gymAnnotation.isSelected ? "SelectedGym" :
                             (gymAnnotation.gymCount == 1 ? "GymIndividual" : "GymCluster")
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            
            if annotationView == nil {
                annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.isEnabled = true
            }
            
            annotationView?.annotation = annotation
            annotationView?.subviews.forEach { $0.removeFromSuperview() }
            
            // Orange color: #F97316 (RGB: 249, 115, 22)
            let orangeColor = UIColor(red: 0.976, green: 0.451, blue: 0.086, alpha: 1.0)
            
            if gymAnnotation.isSelected {
                // Selected gym marker - custom orange circle with pin emoji
                let size: CGFloat = 32
                let circleView = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
                circleView.backgroundColor = orangeColor
                circleView.layer.cornerRadius = size / 2
                circleView.layer.borderWidth = 4
                circleView.layer.borderColor = UIColor.white.cgColor
                circleView.layer.shadowColor = UIColor.black.cgColor
                circleView.layer.shadowOffset = CGSize(width: 0, height: 4)
                circleView.layer.shadowRadius = 8
                circleView.layer.shadowOpacity = 0.4
                
                let emojiLabel = UILabel(frame: CGRect(x: 0, y: 0, width: size, height: size))
                emojiLabel.text = "📍"
                emojiLabel.font = UIFont.systemFont(ofSize: 18)
                emojiLabel.textAlignment = .center
                
                circleView.addSubview(emojiLabel)
                annotationView?.addSubview(circleView)
                annotationView?.frame = CGRect(x: 0, y: 0, width: size, height: size)
                annotationView?.centerOffset = CGPoint(x: 0, y: -size/2)
                annotationView?.zPriority = .max // Ensure it's on top
                annotationView?.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
                annotationView?.canShowCallout = false
                
            } else if gymAnnotation.gymCount == 1 {
                // Individual gym marker - use standard blue pin with callout
                let pinView = MKPinAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                pinView.pinTintColor = .systemBlue
                pinView.canShowCallout = true
                pinView.animatesDrop = false
                
                // Setup callout with gym details
                if let gym = gymAnnotation.gym {
                    let titleLabel = UILabel()
                    titleLabel.text = gym.name
                    titleLabel.font = UIFont.boldSystemFont(ofSize: 16)
                    titleLabel.numberOfLines = 0
                    
                    var addressParts: [String] = []
                    if let address = gym.address {
                        addressParts.append(address)
                    }
                    if let city = gym.city {
                        addressParts.append(city)
                    }
                    if let postcode = gym.postcode {
                        addressParts.append(postcode)
                    }
                    let addressText = addressParts.joined(separator: ", ")
                    
                    let subtitleLabel = UILabel()
                    subtitleLabel.text = addressText
                    subtitleLabel.font = UIFont.systemFont(ofSize: 12)
                    subtitleLabel.textColor = .gray
                    subtitleLabel.numberOfLines = 0
                    
                    let stackView = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
                    stackView.axis = .vertical
                    stackView.spacing = 4
                    stackView.frame = CGRect(x: 0, y: 0, width: 200, height: 60)
                    
                    pinView.detailCalloutAccessoryView = stackView
                    
                    // Add "View Details" button
                    let detailButton = UIButton(type: .custom)
                    detailButton.backgroundColor = UIColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 1.0) // #FF6B6B
                    detailButton.setTitle("View Details", for: .normal)
                    detailButton.setTitleColor(.white, for: .normal)
                    detailButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
                    detailButton.layer.cornerRadius = 8
                    // Use frame-based sizing instead of deprecated contentEdgeInsets
                    detailButton.frame = CGRect(x: 0, y: 0, width: 120, height: 36)
                    pinView.rightCalloutAccessoryView = detailButton
                }
                
                return pinView
                
            } else {
                // Cluster marker - orange circle with count (40pt diameter)
                let size: CGFloat = 40
                let circleView = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
                circleView.backgroundColor = orangeColor
                circleView.layer.cornerRadius = size / 2
                circleView.layer.borderWidth = 3
                circleView.layer.borderColor = UIColor.white.cgColor
                circleView.layer.shadowColor = UIColor.black.cgColor
                circleView.layer.shadowOffset = CGSize(width: 0, height: 2)
                circleView.layer.shadowRadius = 4
                circleView.layer.shadowOpacity = 0.3
                
                let label = UILabel(frame: CGRect(x: 0, y: 0, width: size, height: size))
                label.text = "\(gymAnnotation.gymCount)"
                label.textColor = .white
                label.font = UIFont.boldSystemFont(ofSize: 14)
                label.textAlignment = .center
                
                circleView.addSubview(label)
                annotationView?.addSubview(circleView)
                annotationView?.frame = CGRect(x: 0, y: 0, width: size, height: size)
                annotationView?.centerOffset = CGPoint(x: 0, y: -size/2)
                annotationView?.canShowCallout = false
            }
            
            return annotationView
        }
    }
}

class GymClusterAnnotation: NSObject, MKAnnotation {
    var coordinate: CLLocationCoordinate2D
    var gymCount: Int
    var gymId: Int? // Store gym ID for individual gyms
    var isSelected: Bool = false
    var gym: Gym? // Store full gym object for callout
    
    init(coordinate: CLLocationCoordinate2D, gymCount: Int, gymId: Int? = nil, isSelected: Bool = false, gym: Gym? = nil) {
        self.coordinate = coordinate
        self.gymCount = gymCount
        self.gymId = gymId
        self.isSelected = isSelected
        self.gym = gym
    }
}

// MARK: - Find Gyms View
struct FindGymsView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var gymService = GymService()
    @StateObject private var gymDetailService = GymDetailService()
    @StateObject private var searchService = GymSearchService()
    @StateObject private var passService = PassService()
    @State private var searchText = ""
    @State private var showSearchOverlay = false
    @State private var selectedGymId: Int?
    @State private var showGymDetail = false
    @State private var activePassExpanded = false
    @State private var activePassDragOffset: CGFloat = 0
    var onNavigateToPasses: (() -> Void)? = nil
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 54.5, longitude: -2.0), // UK center
        span: MKCoordinateSpan(latitudeDelta: 8.0, longitudeDelta: 8.0) // Zoom level 6 equivalent
    )
    
    // Use search service gyms if a search has been performed, otherwise use gym service gyms
    @State private var hasSearched = false
    
    // Make displayGyms a @State to ensure view updates when it changes
    @State private var displayGyms: [Gym] = []
    
    private func updateDisplayGyms() {
        let newGyms: [Gym]
        if hasSearched {
            newGyms = searchService.gyms
        } else {
            newGyms = gymService.gyms
        }
        
        // Only update if the array actually changed
        if displayGyms.map({ $0.id }) != newGyms.map({ $0.id }) {
            displayGyms = newGyms
            print("Display gyms updated: \(newGyms.count) gyms (hasSearched: \(hasSearched))")
        }
    }
    
    var body: some View {
        ZStack {
            // Map View
            GymMapView(
                gyms: displayGyms,
                region: $region,
                selectedGymId: selectedGymId,
                onGymSelected: { gymId in
                    selectedGymId = gymId
                    gymDetailService.fetchGymDetail(gymId: gymId)
                    showGymDetail = true
                    
                    // Center and zoom to selected gym (zoom level 13 - street level)
                    if let gym = displayGyms.first(where: { $0.id == gymId }),
                       let coord = gym.coordinate {
                        withAnimation {
                            region = MKCoordinateRegion(
                                center: coord,
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01) // Zoom level 13
                            )
                        }
                    }
                },
                onClusterTapped: {
                    // Cluster was tapped, zoom will be handled in the map delegate
                }
            )
            .ignoresSafeArea()
            .blur(radius: showSearchOverlay ? 5 : 0)
            
            // Loading Overlay
            if searchService.isLoading {
                ZStack {
                    Color.white.opacity(0.75)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading...")
                            .poppins(.regular, size: 16)
                            .foregroundColor(.black)
                    }
                }
            }
            
            if !showSearchOverlay && !showGymDetail {
                VStack {
                    // Search Bar (Button)
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .font(.system(size: 16))
                        
                        Text(searchText.isEmpty ? "Search" : searchText)
                            .poppins(.regular, size: 16)
                            .foregroundColor(searchText.isEmpty ? .gray : .black)
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 16))
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .cornerRadius(80)
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showSearchOverlay = true
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    
                    Spacer()
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showGymDetail)
            }
            
            // Search Overlay
            if showSearchOverlay {
                SearchOverlayView(
                    searchService: searchService,
                    isPresented: $showSearchOverlay,
                    hasSearched: $hasSearched,
                    initialGyms: gymService.gyms
                )
            }
            
            // Gym Detail Panel
            if showGymDetail {
                if let gymDetail = gymDetailService.gymDetail {
                    GymDetailView(
                        gymDetail: gymDetail,
                        isPresented: $showGymDetail,
                        isLoading: gymDetailService.isLoading,
                        onNavigateToPasses: onNavigateToPasses
                    )
                    .environmentObject(authManager)
                } else if gymDetailService.isLoading {
                    // Loading state
                    VStack {
                        Spacer()
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("Loading gym details...")
                                .poppins(.regular, size: 16)
                                .foregroundColor(.gray)
                        }
                        .padding(40)
                        .background(Color.white)
                        .cornerRadius(20, corners: [.topLeft, .topRight])
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: -5)
                        .frame(maxHeight: UIScreen.main.bounds.height * 0.3)
                    }
                    .transition(.move(edge: .bottom))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showGymDetail)
                }
            }
            
            // Active Pass Bottom Sheet
            if let activePass = passService.activePass, !showGymDetail {
                ActivePassBottomSheet(
                    pass: activePass,
                    isExpanded: $activePassExpanded,
                    dragOffset: $activePassDragOffset
                )
            }
        }
        .onAppear {
            // Initial load: fetch all gyms
            if gymService.gyms.isEmpty {
                gymService.fetchGyms()
            }
            // Fetch chains for filter dropdown
            if searchService.chains.isEmpty {
                searchService.fetchChains()
            }
            // Initialize displayGyms
            updateDisplayGyms()
            // Fetch active pass
            if let user = authManager.user {
                passService.fetchActivePass(auth0Id: user.sub)
            }
        }
        .onChange(of: authManager.user?.sub) { auth0Id in
            // Fetch active pass when user changes
            if let auth0Id = auth0Id {
                passService.fetchActivePass(auth0Id: auth0Id)
            }
        }
        .onChange(of: gymService.gyms) { newGyms in
            print("Gyms updated in FindGymsView: \(newGyms.count) gyms")
            // Update search service with initial gyms for tier extraction
            if searchService.gyms.isEmpty && !newGyms.isEmpty {
                searchService.gyms = newGyms.filter { $0.hasValidLocation }
            }
            // Update display gyms if not searching
            if !hasSearched {
                updateDisplayGyms()
            }
        }
        .onChange(of: searchService.gyms) { newGyms in
            print("Search service gyms updated: \(newGyms.count) gyms")
            // Update display gyms if searching
            if hasSearched {
                updateDisplayGyms()
            }
        }
        .onChange(of: hasSearched) { _ in
            // Update display gyms when search state changes
            updateDisplayGyms()
        }
    }
}

// MARK: - Gym Detail View
struct GymDetailView: View {
    let gymDetail: GymDetail
    @Binding var isPresented: Bool
    let isLoading: Bool
    var onNavigateToPasses: (() -> Void)? = nil
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var passService = PassService()
    @State private var selectedTab: DetailTab = .amenities
    @State private var dragOffset: CGFloat = 0
    @State private var panelHeight: CGFloat = UIScreen.main.bounds.height * 0.7
    @State private var showTermsModal = false
    @State private var isGeneratingPass = false
    @State private var errorMessage: String?
    @State private var chainData: GymDetailChain?
    
    enum DetailTab {
        case amenities
        case openingHours
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 0) {
                // Drag handle with gesture
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 40, height: 4)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                }
                .background(Color.white)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Only allow downward dragging
                            if value.translation.height > 0 {
                                dragOffset = value.translation.height
                            }
                        }
                        .onEnded { value in
                            // If dragged down more than 100 points, dismiss
                            if value.translation.height > 100 || value.predictedEndTranslation.height > 200 {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isPresented = false
                                    dragOffset = 0
                                }
                            } else {
                                // Spring back to original position
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header with tier tag and name
                        VStack(alignment: .leading, spacing: 8) {
                            // Tier tag
                            if let tier = gymDetail.requiredTier {
                                    Text(tier.uppercased())
                                        .poppins(.semibold, size: 12)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue)
                                    .cornerRadius(12)
                            }
                            
                            // Gym name
                                Text(gymDetail.name)
                                    .poppins(.bold, size: 24)
                                .foregroundColor(.black)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        
                        // Gym chain logo and name (vertical layout)
                        VStack(alignment: .leading, spacing: 8) {
                            if let logoUrl = gymDetail.logoUrl,
                               !logoUrl.isEmpty {
                                AsyncImage(url: URL(string: logoUrl)) { phase in
                                    Group {
                                        switch phase {
                                        case .empty:
                                            ProgressView()
                                                .frame(width: 50, height: 50)
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(maxWidth: 100, maxHeight: 50)
                                                .clipped()
                                        case .failure(let error):
                                            Image(systemName: "photo")
                                                .font(.system(size: 24))
                                                .foregroundColor(.gray)
                                                .frame(width: 50, height: 50)
                                                .onAppear {
                                                    print("Failed to load gym logo from \(logoUrl): \(error.localizedDescription)")
                                                }
                                        @unknown default:
                                            Image(systemName: "photo")
                                                .font(.system(size: 24))
                                                .foregroundColor(.gray)
                                                .frame(width: 50, height: 50)
                                        }
                                    }
                                }
                                .frame(width: 100, height: 50)
                            } else {
                                // Show placeholder if no logo URL
                                Image(systemName: "photo")
                                    .font(.system(size: 24))
                                    .foregroundColor(.gray)
                                    .frame(width: 50, height: 50)
                            }
                            
                            if let chainName = gymDetail.chainName {
                                Text(chainName)
                                    .poppins(.regular, size: 16)
                                    .foregroundColor(.black)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Address
                        if let address = gymDetail.address,
                           let city = gymDetail.city,
                           let postcode = gymDetail.postcode {
                            Text("\(address), \(city) \(postcode)")
                                .poppins(.regular, size: 14)
                                .foregroundColor(.gray)
                                .padding(.horizontal, 20)
                        }
                        
                        // Description
                        if let description = gymDetail.description {
                            Text(description)
                                .poppins(.regular, size: 14)
                                .foregroundColor(.black)
                                .padding(.horizontal, 20)
                        }
                        
                        // Error message
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .poppins(.regular, size: 14)
                                .foregroundColor(Color(red: 0.7, green: 0.1, blue: 0.1))
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(red: 1.0, green: 0.9, blue: 0.9))
                                .cornerRadius(8)
                                .padding(.horizontal, 20)
                        }
                        
                        // Generate Pass / Get Subscription button
                        Button(action: {
                            if hasSubscription {
                                handleGeneratePass()
                            } else {
                                // Navigate to subscription page or show message
                                showSubscriptionMessage()
                            }
                        }) {
                            Text(isGeneratingPass ? "Loading..." : (hasSubscription ? "Generate Pass" : "Get a Subscription"))
                                .poppins(.semibold, size: 18)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color(red: 1.0, green: 0.42, blue: 0.42)) // #FF6B6B
                                .cornerRadius(12)
                                .opacity(isGeneratingPass ? 0.5 : 1.0)
                        }
                        .disabled(isGeneratingPass)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        
                        // Tabs
                        HStack(spacing: 0) {
                            Button(action: {
                                selectedTab = .amenities
                            }) {
                                VStack(spacing: 8) {
                                    Text("Amenities")
                                        .poppins(selectedTab == .amenities ? .semibold : .regular, size: 16)
                                        .foregroundColor(.black)
                                    if selectedTab == .amenities {
                                        Rectangle()
                                            .fill(Color.black)
                                            .frame(height: 2)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            
                            Button(action: {
                                selectedTab = .openingHours
                            }) {
                                VStack(spacing: 8) {
                                    Text("Opening Hours")
                                        .poppins(selectedTab == .openingHours ? .semibold : .regular, size: 16)
                                        .foregroundColor(.black)
                                    if selectedTab == .openingHours {
                                        Rectangle()
                                            .fill(Color.black)
                                            .frame(height: 2)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        
                        // Tab content
                        if selectedTab == .amenities {
                            // Amenities grid
                            if let amenities = gymDetail.amenities, !amenities.isEmpty {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                    ForEach(amenities.prefix(8), id: \.self) { amenity in
                                        AmenityButton(amenity: amenity)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                            }
                        } else {
                            // Opening hours
                            if let hours = gymDetail.openingHours, !hours.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(hours, id: \.self) { hour in
                                        Text(hour)
                                            .poppins(.regular, size: 14)
                                            .foregroundColor(.black)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                            } else {
                                Text("Opening hours not available")
                                    .poppins(.regular, size: 14)
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 16)
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity)
            }
            .background(Color.white)
            .cornerRadius(20, corners: [.topLeft, .topRight])
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: -5)
            .frame(maxHeight: panelHeight)
            .offset(y: dragOffset)
        }
        .transition(.move(edge: .bottom))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isPresented)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dragOffset)
        .fullScreenCover(isPresented: $showTermsModal) {
            if let chain = chainData ?? gymDetail.gymChain {
                TermsModal(
                    chain: chain,
                    isPresented: $showTermsModal,
                    onAccept: {
                        showTermsModal = false
                        generatePassDirectly()
                    },
                    onCancel: {
                        showTermsModal = false
                    }
                )
            }
        }
        .onAppear {
            // Fetch subscription status
            if let user = authManager.user {
                passService.fetchPasses(auth0Id: user.sub)
            }
        }
    }
    
    private var hasSubscription: Bool {
        passService.subscription != nil
    }
    
    private func handleGeneratePass() {
        isGeneratingPass = true
        errorMessage = nil
        
        // Check if chain data exists
        if let chain = gymDetail.gymChain {
            chainData = chain
            checkTermsAndGenerate()
        } else {
            // Fetch chain data
            fetchChainData()
        }
    }
    
    private func fetchChainData() {
        guard let url = URL(string: "https://api.any-gym.com/gyms/\(gymDetail.id)") else {
            errorMessage = "Invalid URL"
            isGeneratingPass = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if error != nil {
                    self.errorMessage = "Failed to load gym details. Please try again."
                    self.isGeneratingPass = false
                    return
                }
                
                guard let data = data,
                      let httpResponse = response as? HTTPURLResponse else {
                    self.errorMessage = "Invalid response"
                    self.isGeneratingPass = false
                    return
                }
                
                if httpResponse.statusCode == 404 {
                    self.errorMessage = "Gym not found. Please try again."
                    self.isGeneratingPass = false
                    return
                }
                
                let decoder = JSONDecoder()
                if let response = try? decoder.decode(GymDetailResponse.self, from: data) {
                    self.chainData = response.gymChain
                } else if let gymDetail = try? decoder.decode(GymDetail.self, from: data) {
                    self.chainData = gymDetail.gymChain
                }
                
                self.checkTermsAndGenerate()
            }
        }.resume()
    }
    
    private func checkTermsAndGenerate() {
        let chain = chainData ?? gymDetail.gymChain
        
        if let chain = chain, (chain.hasTerms || chain.hasHealthStatement) {
            // Show terms modal
            showTermsModal = true
            isGeneratingPass = false
        } else {
            // Generate pass directly
            generatePassDirectly()
        }
    }
    
    private func generatePassDirectly() {
        isGeneratingPass = true
        errorMessage = nil
        
        guard let user = authManager.user else {
            errorMessage = "Please log in to generate a pass"
            isGeneratingPass = false
            return
        }
        
        Task {
            do {
                _ = try await passService.generatePass(gymId: gymDetail.id, auth0Id: user.sub)
                await MainActor.run {
                    isGeneratingPass = false
                    isPresented = false
                    // Navigate to passes page
                    onNavigateToPasses?()
                    // Refresh passes
                    passService.fetchPasses(auth0Id: user.sub)
                }
            } catch {
                await MainActor.run {
                    isGeneratingPass = false
                    
                    if let passError = error as? PassGenerationError {
                        let message = passError.errorDescription ?? "Failed to generate pass. Please try again."
                        errorMessage = message
                        print("=== Error Displayed to User ===")
                        print("Error Type: PassGenerationError")
                        print("Error Message: \(message)")
                        print("===============================")
                    } else if let nsError = error as NSError? {
                        errorMessage = nsError.localizedDescription
                        print("=== Error Displayed to User ===")
                        print("Error Type: NSError")
                        print("Error Message: \(nsError.localizedDescription)")
                        print("===============================")
                    } else {
                        errorMessage = "Failed to generate pass. Please try again."
                        print("=== Error Displayed to User ===")
                        print("Error Type: Unknown")
                        print("Error Message: Failed to generate pass. Please try again.")
                        print("===============================")
                    }
                }
            }
        }
    }
    
    private func showSubscriptionMessage() {
        // Show alert or navigate to subscription page
        errorMessage = "A subscription is required to generate passes. Please subscribe to continue."
    }
}

// MARK: - Amenity Button
struct AmenityButton: View {
    let amenity: String
    
    var icon: String {
        switch amenity.lowercased() {
        case let a where a.contains("wifi"):
            return "wifi"
        case let a where a.contains("parking"):
            return "building.2"
        case let a where a.contains("shower"):
            return "drop.fill"
        case let a where a.contains("locker"):
            return "lock.fill"
        default:
            return "checkmark.circle"
        }
    }
    
    var body: some View {
        Button(action: {}) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.black)
                                        Text(amenity)
                                            .poppins(.regular, size: 12)
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

// MARK: - Corner Radius Extension
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Search Overlay View
struct SearchOverlayView: View {
    @ObservedObject var searchService: GymSearchService
    @Binding var isPresented: Bool
    @Binding var hasSearched: Bool
    let initialGyms: [Gym] // For tier extraction
    @FocusState private var isSearchFocused: Bool
    
    @State private var searchQuery: String = ""
    @State private var selectedTier: String = "All Tiers"
    @State private var selectedChain: String = "All Chains"
    @State private var selectedFacility: String = "All Facilities"
    
    // Extract unique tiers from initial gyms
    var tierOptions: [String] {
        var tiers = Set<String>()
        // Get tiers from initial gyms
        for gym in initialGyms {
            if let tier = gym.requiredTier, !tier.isEmpty {
                tiers.insert(tier)
            }
        }
        return ["All Tiers"] + tiers.sorted()
    }
    
    var chainOptions: [String] {
        ["All Chains"] + searchService.chains.map { $0.name }
    }
    
    var chainIdForName: [String: String] {
        var mapping: [String: String] = [:]
        for chain in searchService.chains {
            mapping[chain.name] = String(chain.id)
        }
        return mapping
    }
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            VStack(spacing: 0) {
                // Close button (top right)
                HStack {
                    Spacer()
                    Button(action: {
                        isPresented = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 60)
                }
                
                // Main overlay content - positioned at top
                VStack(spacing: 20) {
                    // Search Input Field
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .font(.system(size: 16))
                        
                        TextField("Search by name, chain, or city...", text: $searchQuery)
                            .poppins(.regular, size: 16)
                            .onChange(of: searchQuery) { newValue in
                                // Check if all filters are cleared
                                let allFiltersCleared = newValue.isEmpty && selectedTier == "All Tiers" && selectedChain == "All Chains"
                                
                                if allFiltersCleared {
                                    // Reset to show all gyms
                                    hasSearched = false
                                    searchService.gyms = []
                                } else {
                                    // Debounced search - only search if query is not empty or filters are active
                                    hasSearched = true
                                    searchService.searchGyms(
                                        searchQuery: newValue,
                                        tier: selectedTier == "All Tiers" ? nil : selectedTier,
                                        chainId: selectedChain == "All Chains" ? nil : chainIdForName[selectedChain]
                                    )
                                }
                            }
                        
                        // Location icon button (placeholder)
                        Button(action: {
                            // Location button action - not implemented yet
                        }) {
                            Image(systemName: "location.fill")
                                .foregroundColor(.gray)
                                .font(.system(size: 16))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .focused($isSearchFocused)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    // Filter Dropdowns
                    VStack(spacing: 16) {
                        // Tier Filter
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tier")
                                .poppins(.semibold, size: 14)
                                .foregroundColor(.primary)
                            Picker("Tier", selection: $selectedTier) {
                                ForEach(tierOptions, id: \.self) { tier in
                                    Text(tier).tag(tier)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: selectedTier) { newValue in
                                // Check if all filters are cleared
                                let allFiltersCleared = searchQuery.isEmpty && newValue == "All Tiers" && selectedChain == "All Chains"
                                
                                if allFiltersCleared {
                                    // Reset to show all gyms
                                    hasSearched = false
                                    searchService.gyms = []
                                } else {
                                    // Immediate search on filter change
                                    hasSearched = true
                                    searchService.searchGymsImmediate(
                                        searchQuery: searchQuery,
                                        tier: newValue == "All Tiers" ? nil : newValue,
                                        chainId: selectedChain == "All Chains" ? nil : chainIdForName[selectedChain]
                                    )
                                }
                            }
                        }
                        
                        // Chain Filter
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Chain")
                                .poppins(.semibold, size: 14)
                                .foregroundColor(.primary)
                            Picker("Chain", selection: $selectedChain) {
                                ForEach(chainOptions, id: \.self) { chain in
                                    Text(chain).tag(chain)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: selectedChain) { newValue in
                                // Check if all filters are cleared
                                let allFiltersCleared = searchQuery.isEmpty && selectedTier == "All Tiers" && newValue == "All Chains"
                                
                                if allFiltersCleared {
                                    // Reset to show all gyms
                                    hasSearched = false
                                    searchService.gyms = []
                                } else {
                                    // Immediate search on filter change
                                    hasSearched = true
                                    searchService.searchGymsImmediate(
                                        searchQuery: searchQuery,
                                        tier: selectedTier == "All Tiers" ? nil : selectedTier,
                                        chainId: newValue == "All Chains" ? nil : chainIdForName[newValue]
                                    )
                                }
                            }
                        }
                        
                        // Facility Filter (placeholder - not implemented)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Facility")
                                .poppins(.semibold, size: 14)
                                .foregroundColor(.primary)
                            Picker("Facility", selection: $selectedFacility) {
                                Text("All Facilities").tag("All Facilities")
                            }
                            .pickerStyle(.menu)
                            .disabled(true)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // Search Button
                Button(action: {
                    // Perform final search and close overlay
                    hasSearched = true
                    searchService.searchGymsImmediate(
                        searchQuery: searchQuery,
                        tier: selectedTier == "All Tiers" ? nil : selectedTier,
                        chainId: selectedChain == "All Chains" ? nil : chainIdForName[selectedChain]
                    )
                    isPresented = false
                }) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18))
                        Text("Search")
                            .poppins(.semibold, size: 18)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.orange)
                    .cornerRadius(80)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                Spacer()
            }
        }
        .onAppear {
            // Auto-focus search input when overlay appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
            // Fetch chains if not already loaded
            if searchService.chains.isEmpty {
                searchService.fetchChains()
            }
        }
    }
}

// MARK: - Pass Model
struct Pass: Codable, Identifiable {
    let id: Int
    let gymId: Int
    let userId: String
    let gymChainId: Int?
    let gymChainName: String?
    let gymChainLogo: String?
    let gymName: String?
    let gymAddress: String?
    let gymCity: String?
    let gymPostcode: String?
    let passCode: String?
    let status: String?
    let validUntil: String?
    let qrcodeUrl: String?
    let walletPassUrl: String?
    let subscriptionTier: String?
    let createdAt: String?
    let updatedAt: String?
    let visitsUsed: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case gymId = "gym_id"
        case userId = "user_id"
        case gymChainId = "gym_chain_id"
        case gymChainName = "gym_chain_name"
        case gymChainLogo = "gym_chain_logo"
        case gymName = "gym_name"
        case gymAddress = "gym_address"
        case gymCity = "gym_city"
        case gymPostcode = "gym_postcode"
        case passCode = "pass_code"
        case status
        case validUntil = "valid_until"
        case qrcodeUrl = "qrcode_url"
        case walletPassUrl = "wallet_pass_url"
        case subscriptionTier = "subscription_tier"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case visitsUsed = "visits_used"
    }
}

// MARK: - Subscription Model
struct Subscription: Codable {
    let tier: String
    let monthlyLimit: Int
    let visitsUsed: Int
    let price: Double
    let nextBillingDate: String
    let guestPassesLimit: Int
    let guestPassesUsed: Int
    let currentPeriodStart: String
    let currentPeriodEnd: String
    
    enum CodingKeys: String, CodingKey {
        case tier
        case monthlyLimit = "monthly_limit"
        case visitsUsed = "visits_used"
        case price
        case nextBillingDate = "next_billing_date"
        case guestPassesLimit = "guest_passes_limit"
        case guestPassesUsed = "guest_passes_used"
        case currentPeriodStart = "current_period_start"
        case currentPeriodEnd = "current_period_end"
    }
}

struct PassResponse: Codable {
    let subscription: Subscription?
    let activePasses: [Pass]?
    let passHistory: [Pass]?
    
    enum CodingKeys: String, CodingKey {
        case subscription
        case activePasses = "active_passes"
        case passHistory = "pass_history"
    }
}

// MARK: - Pass Service
class PassService: ObservableObject {
    @Published var passes: [Pass] = []
    @Published var passHistory: [Pass] = []
    @Published var activePass: Pass?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var visitsUsed: Int = 0
    @Published var monthlyLimit: Int = 5
    @Published var guestPassesUsed: Int = 0
    @Published var guestPassesLimit: Int = 0
    @Published var subscription: Subscription?
    
    private let baseURL = "https://api.any-gym.com"
    private var cancellables = Set<AnyCancellable>()
    
    func fetchPasses(auth0Id: String) {
        isLoading = true
        errorMessage = nil
        
        guard let url = URL(string: "\(baseURL)/user/passes") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Add auth0_id to header
        request.setValue(auth0Id, forHTTPHeaderField: "auth0_id")
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .handleEvents(receiveOutput: { data in
                // Log raw JSON response for debugging
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("Passes API Response (first 500 chars): \(String(jsonString.prefix(500)))")
                }
            })
            .tryMap { data -> PassResponse in
                let decoder = JSONDecoder()
                // Don't use .convertFromSnakeCase since we have explicit CodingKeys
                decoder.dateDecodingStrategy = .iso8601
                
                do {
                    return try decoder.decode(PassResponse.self, from: data)
                    } catch {
                    print("Failed to decode PassResponse: \(error)")
                        // Log the actual JSON structure for debugging
                        if let json = try? JSONSerialization.jsonObject(with: data) {
                            print("Actual JSON structure: \(json)")
                        }
                    throw error
                }
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                        print("Error fetching passes: \(error)")
                    }
                },
                receiveValue: { [weak self] response in
                    guard let self = self else { return }
                    
                    // Extract passes
                    self.passes = response.activePasses ?? []
                    
                    // Extract pass history
                    self.passHistory = response.passHistory ?? []
                    
                    // Extract subscription data
                    if let subscription = response.subscription {
                        self.subscription = subscription
                        self.visitsUsed = subscription.visitsUsed
                        self.monthlyLimit = subscription.monthlyLimit
                        self.guestPassesUsed = subscription.guestPassesUsed
                        self.guestPassesLimit = subscription.guestPassesLimit
                        
                        print("Subscription data loaded:")
                        print("  Tier: \(subscription.tier)")
                        print("  Visits used: \(subscription.visitsUsed)/\(subscription.monthlyLimit)")
                        print("  Guest passes: \(subscription.guestPassesUsed)/\(subscription.guestPassesLimit)")
                    }
                    
                    self.isLoading = false
                    print("Fetched \(self.passes.count) active passes")
                    print("Fetched \(self.passHistory.count) historical passes")
                }
            )
            .store(in: &cancellables)
    }
    
    func generatePass(gymId: Int, auth0Id: String) async throws -> GeneratePassResponse {
        // Use /generate_pass endpoint (matching the API documentation)
        guard let url = URL(string: "\(baseURL)/generate_pass") else {
            throw PassGenerationError.unknown("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(auth0Id, forHTTPHeaderField: "auth0_id")
        
        // Body should include both auth0_id and gym_id (snake_case)
        let body: [String: Any] = [
            "auth0_id": auth0Id,
            "gym_id": gymId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Debug logging
        print("=== Generate Pass API Request ===")
        print("URL: \(url.absoluteString)")
        print("Method: POST")
        print("Headers:")
        print("  Content-Type: application/json")
        print("  auth0_id: \(auth0Id)")
        print("Body:")
        if let bodyData = request.httpBody,
           let bodyString = String(data: bodyData, encoding: .utf8) {
            print("  \(bodyString)")
        }
        print("================================")
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
            
            // Debug logging for response
            print("=== Generate Pass API Response ===")
            if let httpResponse = response as? HTTPURLResponse {
                print("Status Code: \(httpResponse.statusCode)")
                print("Headers: \(httpResponse.allHeaderFields)")
            }
            if let responseString = String(data: data, encoding: .utf8) {
                print("Response Body: \(responseString)")
            }
            print("==================================")
        } catch {
            print("=== Generate Pass API Error ===")
            print("Error: \(error.localizedDescription)")
            print("===============================")
            throw PassGenerationError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PassGenerationError.unknown("Invalid response")
        }
        
        // Parse error message from response body
        // Prioritize "message" field as it contains user-friendly error descriptions
        let errorMessage: String
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // First try to get the "message" field (most user-friendly)
            if let message = json["message"] as? String, !message.isEmpty {
                errorMessage = message
                print("✓ Extracted error message from 'message' field: \(message)")
            } 
            // Fall back to "error" field if message is not available
            else if let error = json["error"] as? String, !error.isEmpty {
                errorMessage = error
                print("✓ Extracted error message from 'error' field: \(error)")
            } 
            // Try ErrorResponse struct
            else if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                errorMessage = errorResponse.errorMessage
                print("✓ Extracted error message from ErrorResponse: \(errorMessage)")
            } 
            else {
                errorMessage = "An error occurred"
                print("⚠ Could not extract error message from JSON")
            }
        } else if let errorString = String(data: data, encoding: .utf8), !errorString.isEmpty {
            // Remove quotes and whitespace if it's a JSON string
            let cleaned = errorString.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") {
                errorMessage = String(cleaned.dropFirst().dropLast())
            } else {
                errorMessage = cleaned
            }
            print("✓ Extracted error message from plain text: \(errorMessage)")
        } else {
            errorMessage = "An error occurred"
            print("⚠ No error message found in response")
        }
        
        print("Final Parsed Error Message: \(errorMessage)")
        
        // Handle different status codes
        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            return try decoder.decode(GeneratePassResponse.self, from: data)
            
        case 403:
            // ForbiddenException
            throw PassGenerationError.forbidden(errorMessage)
            
        case 400:
            // BadRequestException
            throw PassGenerationError.badRequest(errorMessage)
            
        case 404:
            // NotFoundException
            throw PassGenerationError.notFound(errorMessage)
            
        case 401:
            throw PassGenerationError.forbidden("Unauthorized. Please log in.")
            
        case 500...599:
            // Server errors
            throw PassGenerationError.serverError(errorMessage)
            
        default:
            throw PassGenerationError.unknown(errorMessage)
        }
    }
    
    func fetchActivePass(auth0Id: String) {
        guard let url = URL(string: "\(baseURL)/user/active_pass") else {
            print("Invalid URL for active pass")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(auth0Id, forHTTPHeaderField: "auth0_id")
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .tryMap { data -> Pass? in
                // Check if response is empty or null
                if data.isEmpty {
                    return nil
                }
                
                // Try to decode as Pass object
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                
                do {
                    return try decoder.decode(Pass.self, from: data)
                } catch {
                    // If decoding fails, log and return nil
                    print("Failed to decode active pass: \(error)")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("Response: \(jsonString)")
                    }
                    return nil
                }
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("Error fetching active pass: \(error)")
                    }
                },
                receiveValue: { [weak self] pass in
                    self?.activePass = pass
                    if let pass = pass {
                        print("Active pass loaded: \(pass.gymName ?? "Unknown gym")")
                    } else {
                        print("No active pass found")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
}

// MARK: - My Passes View
struct MyPassesView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var passService = PassService()
    
    var standardPlanUsed: Int {
        passService.visitsUsed
    }
    
    var standardPlanTotal: Int {
        passService.monthlyLimit
    }
    
    var standardPlanRemaining: Int {
        max(0, standardPlanTotal - standardPlanUsed)
    }
    
    var guestPassesUsed: Int {
        passService.guestPassesUsed
    }
    
    var guestPassesTotal: Int {
        passService.guestPassesLimit
    }
    
    var guestPassesRemaining: Int {
        max(0, guestPassesTotal - guestPassesUsed)
    }
    
    var resetDate: String {
        // Use subscription's current_period_end if available
        if let subscription = passService.subscription {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            if let date = dateFormatter.date(from: subscription.currentPeriodEnd) {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d, yyyy"
                return formatter.string(from: date)
            }
        }
        
        // Fallback to last day of current month
        let calendar = Calendar.current
        let now = Date()
        if let nextMonth = calendar.date(byAdding: .month, value: 1, to: now),
           let startOfNextMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth)),
           let lastDayOfMonth = calendar.date(byAdding: .day, value: -1, to: startOfNextMonth) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: lastDayOfMonth)
        }
        return "N/A"
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Title Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("My Passes")
                        .poppins(.bold, size: 32)
                        .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                    
                    Text("View and manage your gym passes.")
                        .poppins(.regular, size: 16)
                        .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
                
                // Main Card
                VStack(alignment: .leading, spacing: 0) {
                    // Standard Plan Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            // Plan Label
                            Text("standard Plan")
                                .poppins(.medium, size: 12)
                                .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(red: 1.0, green: 0.8, blue: 0.6))
                                .cornerRadius(12)
                            
                            Spacer()
                            
                            // Pass Count - directly reference passService to ensure updates
                            Text("\(passService.visitsUsed)/\(passService.monthlyLimit)")
                                .poppins(.bold, size: 28)
                                .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                        }
                        
                        // Progress Bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(red: 0.9, green: 0.9, blue: 0.9))
                                    .frame(height: 8)
                                
                                // Filled portion - directly reference passService to ensure updates
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(red: 1.0, green: 0.47, blue: 0.09)) // Orange color
                                    .frame(
                                        width: passService.monthlyLimit > 0 
                                            ? min(geometry.size.width, geometry.size.width * CGFloat(passService.visitsUsed) / CGFloat(passService.monthlyLimit))
                                            : 0,
                                        height: 8
                                    )
                            }
                        }
                        .frame(height: 8)
                        
                        // Remaining passes text
                        Text("\(standardPlanRemaining) passes remaining this billing period")
                            .poppins(.regular, size: 14)
                            .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                        
                        // Reset date
                        Text("Resets on \(resetDate).")
                            .poppins(.regular, size: 12)
                            .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))
                    }
                    .padding(20)
                    
                    Divider()
                        .padding(.horizontal, 20)
                    
                    // Guest Passes Section
                    VStack(alignment: .leading, spacing: 16) {
                        // Pass Count
                        Text("\(passService.guestPassesUsed)/\(passService.guestPassesLimit)")
                            .poppins(.bold, size: 28)
                            .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                        
                        // Progress Bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(red: 0.9, green: 0.9, blue: 0.9))
                                .frame(height: 8)
                                
                                // Filled portion
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(red: 1.0, green: 0.47, blue: 0.09)) // Orange color
                                    .frame(
                                        width: passService.guestPassesLimit > 0 
                                            ? min(geometry.size.width, geometry.size.width * CGFloat(passService.guestPassesUsed) / CGFloat(passService.guestPassesLimit))
                                            : 0,
                                        height: 8
                                    )
                            }
                        }
                        .frame(height: 8)
                        
                        // Remaining passes text
                        Text("\(guestPassesRemaining) guest passes remaining")
                            .poppins(.regular, size: 14)
                            .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                        
                        // Reset frequency
                        Text("Resets monthly.")
                            .poppins(.regular, size: 12)
                            .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))
                    }
                    .padding(20)
                }
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 2)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                
                // Active Passes Section
                if !passService.passes.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        // Section Header
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.stack.fill")
                                .font(.system(size: 20))
                                .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                            Text("Active Passes")
                                .poppins(.bold, size: 22)
                                .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                        }
                        .padding(.horizontal, 20)
                        
                        // Active Pass Cards
                        ForEach(passService.passes) { pass in
                            ActivePassCard(pass: pass)
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 24)
                }
                
                // Pass History Section
                if !passService.passHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        // Section Header
                        HStack(spacing: 8) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 20))
                                .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                            Text("Pass History")
                                .poppins(.bold, size: 22)
                                .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                        }
                        .padding(.horizontal, 20)
                        
                        // Pass History Cards
                        ForEach(passService.passHistory) { pass in
                            PassHistoryCard(pass: pass)
                                .padding(.horizontal, 20)
                        }
                    }
                .padding(.bottom, 40)
                }
            }
        }
        .background(Color(red: 0.95, green: 0.95, blue: 0.95))
        .overlay {
            if passService.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            }
        }
        .onAppear {
            // Fetch passes when view appears
            if let user = authManager.user {
                passService.fetchPasses(auth0Id: user.sub)
            }
        }
        .onChange(of: authManager.user?.sub) { auth0Id in
            // Fetch passes when user's auth0_id changes
            if let auth0Id = auth0Id {
                passService.fetchPasses(auth0Id: auth0Id)
            }
        }
    }
}

// MARK: - Active Pass Card
struct ActivePassCard: View {
    let pass: Pass
    @State private var showAddToWallet = false
    
    var gymDisplayName: String {
        if let gymName = pass.gymName, !gymName.isEmpty {
            return gymName
        } else if let chainName = pass.gymChainName, !chainName.isEmpty {
            return chainName
        } else {
            return "Gym #\(pass.gymId)"
        }
    }
    
    var fullAddress: String {
        var components: [String] = []
        if let address = pass.gymAddress, !address.isEmpty {
            components.append(address)
        }
        if let city = pass.gymCity, !city.isEmpty {
            components.append(city)
        }
        if let postcode = pass.gymPostcode, !postcode.isEmpty {
            components.append(postcode)
        }
        return components.joined(separator: ", ")
    }
    
    var formattedValidUntil: String {
        guard let validUntil = pass.validUntil else {
            return "N/A"
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = dateFormatter.date(from: validUntil) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy h:mm a"
            return formatter.string(from: date)
        }
        
        // Try without fractional seconds
        let dateFormatter2 = ISO8601DateFormatter()
        dateFormatter2.formatOptions = [.withInternetDateTime]
        if let date = dateFormatter2.date(from: validUntil) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy h:mm a"
            return formatter.string(from: date)
        }
        
        return validUntil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Gym Name
            Text(gymDisplayName)
                .poppins(.bold, size: 24)
                .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
            
            // Location
            if !fullAddress.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                    Text(fullAddress)
                        .poppins(.regular, size: 14)
                        .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                }
            }
            
            // Valid Until
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                Text("Valid until \(formattedValidUntil)")
                    .poppins(.regular, size: 14)
                    .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
            }
            
            // Pass Code Section (White)
            if let passCode = pass.passCode {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pass Code")
                        .poppins(.medium, size: 12)
                        .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                    Text(passCode)
                        .poppins(.bold, size: 16)
                        .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.white)
                .cornerRadius(12)
            }
            
            // QR Code with white background
            if let qrcodeUrl = pass.qrcodeUrl, let url = URL(string: qrcodeUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 200, height: 200)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                    case .failure:
                        Image(systemName: "qrcode")
                            .font(.system(size: 100))
                            .foregroundColor(.gray)
                            .frame(width: 200, height: 200)
                    @unknown default:
                        EmptyView()
                    }
                }
                .padding(16)
                .background(Color.white)
                .cornerRadius(12)
                .frame(maxWidth: .infinity)
            } else {
                // Fallback QR code placeholder
                Image(systemName: "qrcode")
                    .font(.system(size: 100))
                    .foregroundColor(.gray)
                    .frame(width: 200, height: 200)
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(12)
                    .frame(maxWidth: .infinity)
            }
            
            // Scan instruction
            Text("Scan at gym")
                .poppins(.regular, size: 14)
                .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                .frame(maxWidth: .infinity)
            
            // Add to Apple Wallet button
            if PKAddPassesViewController.canAddPasses() {
                Button(action: {
                    addToAppleWallet()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                        Text("Add to Apple Wallet")
                            .poppins(.semibold, size: 16)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.black)
                    .cornerRadius(12)
                }
                .padding(.top, 8)
            }
        }
        .padding(20)
        .background(Color(red: 0.85, green: 0.95, blue: 0.85)) // Light green background
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    private func addToAppleWallet() {
        // If we have a wallet pass URL, download and add it
        if let walletPassUrl = pass.walletPassUrl, let url = URL(string: walletPassUrl) {
            downloadAndAddPass(from: url)
        } else {
            // Show message that wallet pass is not available
            showWalletPassUnavailableAlert()
        }
    }
    
    private func downloadAndAddPass(from url: URL) {
        // Download the .pkpass file
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    showErrorAlert(message: "Failed to download wallet pass: \(error?.localizedDescription ?? "Unknown error")")
                }
                return
            }
            
            // Create PKPass from data
            do {
                let pass = try PKPass(data: data)
                DispatchQueue.main.async {
                    presentAddPassViewController(with: pass)
                }
            } catch {
                DispatchQueue.main.async {
                    showErrorAlert(message: "Failed to create wallet pass: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    private func presentAddPassViewController(with pass: PKPass) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }
        
        let addPassViewController = PKAddPassesViewController(pass: pass)
        addPassViewController?.delegate = WalletPassDelegate.shared
        rootViewController.present(addPassViewController!, animated: true)
    }
    
    private func showWalletPassUnavailableAlert() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }
        
        let alert = UIAlertController(
            title: "Wallet Pass Unavailable",
            message: "This pass is not available for Apple Wallet. Please use the QR code to scan at the gym.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        rootViewController.present(alert, animated: true)
    }
    
    private func showErrorAlert(message: String) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }
        
        let alert = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        rootViewController.present(alert, animated: true)
    }
}

// MARK: - Active Pass Bottom Sheet
struct ActivePassBottomSheet: View {
    let pass: Pass
    @Binding var isExpanded: Bool
    @Binding var dragOffset: CGFloat
    
    var gymDisplayName: String {
        if let gymName = pass.gymName, !gymName.isEmpty {
            return gymName
        } else if let chainName = pass.gymChainName, !chainName.isEmpty {
            return chainName
        } else {
            return "Gym #\(pass.gymId)"
        }
    }
    
    private let collapsedHeight: CGFloat = 100
    private let expandedHeight: CGFloat = UIScreen.main.bounds.height * 0.85
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 0) {
                // Spacing at top to avoid notch when expanded
                if isExpanded {
                    Spacer()
                        .frame(height: 20)
                }
                
                // Drag handle
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 40, height: 4)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if value.translation.height > 0 {
                                // Dragging down
                                dragOffset = value.translation.height
                            } else if isExpanded {
                                // Dragging up when expanded
                                dragOffset = value.translation.height
                            }
                        }
                        .onEnded { value in
                            if value.translation.height > 100 || value.predictedEndTranslation.height > 200 {
                                // Swipe down to collapse
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isExpanded = false
                                    dragOffset = 0
                                }
                            } else if value.translation.height < -50 || value.predictedEndTranslation.height < -100 {
                                // Swipe up to expand
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isExpanded = true
                                    dragOffset = 0
                                }
                            } else {
                                // Spring back
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
                .onTapGesture {
                    // Tap to toggle
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                        dragOffset = 0
                    }
                }
                
                if isExpanded {
                    // Expanded view - show full ActivePassCard
                    ScrollView {
                        ActivePassCard(pass: pass)
                            .padding(.horizontal, 20)
                            .padding(.top, 8) // Small padding after drag handle
                            .padding(.bottom, 40)
                    }
                } else {
                    // Collapsed view - show gym name and logo
                    HStack(spacing: 16) {
                        // Gym Chain Logo
                        if let logoUrl = pass.gymChainLogo, !logoUrl.isEmpty, let url = URL(string: logoUrl) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(width: 50, height: 50)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 50, height: 50)
                                        .cornerRadius(8)
                                case .failure:
                                    Image(systemName: "building.2.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.gray)
                                        .frame(width: 50, height: 50)
                                @unknown default:
                                    Image(systemName: "building.2.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.gray)
                                        .frame(width: 50, height: 50)
                                }
                            }
                            .frame(width: 50, height: 50)
                        } else {
                            Image(systemName: "building.2.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.gray)
                                .frame(width: 50, height: 50)
                        }
                        
                        // Gym Name with "Active pass: " prefix
                        HStack(spacing: 4) {
                            Text("Active pass:")
                                .poppins(.regular, size: 18)
                                .foregroundColor(.black)
                            Text(gymDisplayName)
                                .poppins(.semibold, size: 18)
                                .foregroundColor(.black)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: isExpanded ? (expandedHeight - 40) : collapsedHeight) // Add 20pt to height when expanded for spacing
            .background(Color.white)
            .cornerRadius(20, corners: [.topLeft, .topRight])
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: -5)
            .offset(y: dragOffset)
        }
    }
}

// MARK: - Pass History Card
struct PassHistoryCard: View {
    let pass: Pass
    
    var gymDisplayName: String {
        if let gymName = pass.gymName, !gymName.isEmpty {
            return gymName
        } else {
            return "Gym #\(pass.gymId)"
        }
    }
    
    var formattedDate: String {
        // Try to format validUntil first, then createdAt
        let dateString = pass.validUntil ?? pass.createdAt ?? ""
        guard !dateString.isEmpty else {
            return "N/A"
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = dateFormatter.date(from: dateString) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: date)
        }
        
        // Try without fractional seconds
        let dateFormatter2 = ISO8601DateFormatter()
        dateFormatter2.formatOptions = [.withInternetDateTime]
        if let date = dateFormatter2.date(from: dateString) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: date)
        }
        
        return dateString
    }
    
    var statusText: String {
        if let status = pass.status {
            return status.capitalized
        }
        return "Completed"
    }
    
    var statusColor: Color {
        if let status = pass.status?.lowercased() {
            switch status {
            case "used", "completed":
                return Color.green
            case "expired", "cancelled":
                return Color.red
            default:
                return Color.gray
            }
        }
        return Color.gray
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Gym Chain Logo
            if let logoUrl = pass.gymChainLogo, !logoUrl.isEmpty, let url = URL(string: logoUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 50, height: 50)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .cornerRadius(8)
                    case .failure:
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                            .frame(width: 50, height: 50)
                    @unknown default:
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                            .frame(width: 50, height: 50)
                    }
                }
                .frame(width: 50, height: 50)
            } else {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.gray)
                    .frame(width: 50, height: 50)
            }
            
            // Pass Info
            VStack(alignment: .leading, spacing: 4) {
                Text(gymDisplayName)
                    .poppins(.semibold, size: 16)
                    .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                    Text(formattedDate)
                        .poppins(.regular, size: 14)
                        .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                }
                
                // Status Badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .poppins(.medium, size: 12)
                        .foregroundColor(statusColor)
                }
                .padding(.top, 2)
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Wallet Pass Delegate
class WalletPassDelegate: NSObject, PKAddPassesViewControllerDelegate {
    static let shared = WalletPassDelegate()
    
    func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
        controller.dismiss(animated: true)
    }
}

// MARK: - Safari View Controller Wrapper
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let safariVC = SFSafariViewController(url: url, configuration: config)
        safariVC.preferredControlTintColor = .systemBlue
        return safariVC
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // No updates needed
    }
}

// MARK: - Terms Modal
struct TermsModal: View {
    let chain: GymDetailChain
    @Binding var isPresented: Bool
    let onAccept: () -> Void
    let onCancel: () -> Void
    @State private var showSafariView = false
    @State private var safariURL: URL? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18))
                            .foregroundColor(.gray)
                            .padding(8)
                    }
                    Spacer()
                }
                
                Text("Terms & Health Statement")
                    .poppins(.bold, size: 24)
                    .foregroundColor(.black)
                
                Text("Please review and accept the terms and health statement to generate your pass")
                    .poppins(.regular, size: 14)
                    .foregroundColor(.gray)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Terms Section
                    if chain.hasTerms {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Terms & Conditions")
                                .poppins(.bold, size: 18)
                                .foregroundColor(.black)
                            
                            if let termsUrl = chain.termsUrl, !termsUrl.isEmpty {
                                // Show link - prioritize URL when available
                                if let url = URL(string: termsUrl) {
                                    Button(action: {
                                        safariURL = url
                                        showSafariView = true
                                    }) {
                                        HStack {
                                            Text("View Terms and Conditions")
                                                .poppins(.regular, size: 14)
                                                .foregroundColor(Color.blue)
                                            Image(systemName: "arrow.up.right.square")
                                                .font(.system(size: 14))
                                                .foregroundColor(Color.blue)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(16)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                }
                            } else if let terms = chain.terms, !terms.isEmpty {
                                // Show markdown content if no URL
                                Text(parseMarkdown(terms))
                                    .poppins(.regular, size: 14)
                                    .foregroundColor(.black)
                                    .padding(16)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    
                    // Health Statement Section
                    if chain.hasHealthStatement {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Health Statement")
                                .poppins(.bold, size: 18)
                                .foregroundColor(.black)
                            
                            if let healthUrl = chain.healthStatementUrl, !healthUrl.isEmpty {
                                // Show link - prioritize URL when available
                                if let url = URL(string: healthUrl) {
                                    Button(action: {
                                        safariURL = url
                                        showSafariView = true
                                    }) {
                                        HStack {
                                            Text("View Health and Safety Statement")
                                                .poppins(.regular, size: 14)
                                                .foregroundColor(Color.blue)
                                            Image(systemName: "arrow.up.right.square")
                                                .font(.system(size: 14))
                                                .foregroundColor(Color.blue)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(16)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                }
                            } else if let healthStatement = chain.healthStatement, !healthStatement.isEmpty {
                                // Show markdown content if no URL
                                Text(parseMarkdown(healthStatement))
                                    .poppins(.regular, size: 14)
                                    .foregroundColor(.black)
                                    .padding(16)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    
                    // Empty state
                    if !chain.hasTerms && !chain.hasHealthStatement {
                        Text("No terms or health statement available for this gym.")
                            .poppins(.regular, size: 14)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .padding(40)
                    }
                }
                .padding(24)
            }
            
            // Footer buttons - Full width, stacked vertically
            VStack(spacing: 12) {
                // Accept button
                Button(action: onAccept) {
                    Text("Accept & Generate Pass")
                        .poppins(.semibold, size: 16)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(red: 1.0, green: 0.42, blue: 0.42)) // #FF6B6B
                        .cornerRadius(12)
                }
                
                // Cancel button
                Button(action: onCancel) {
                    Text("Cancel")
                        .poppins(.semibold, size: 16)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                }
            }
            .padding(24)
            .background(Color.white)
        }
        .background(Color.white)
        .ignoresSafeArea()
        .sheet(isPresented: Binding(
            get: { showSafariView && safariURL != nil },
            set: { newValue in
                showSafariView = newValue
                if !newValue {
                    safariURL = nil
                }
            }
        )) {
            if let url = safariURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }
    
    private func parseMarkdown(_ text: String) -> String {
        // Simple markdown parsing - remove markdown syntax for basic display
        // For production, consider using a markdown library
        var parsed = text
        // Remove headers
        parsed = parsed.replacingOccurrences(of: #"^#+\s+"#, with: "", options: .regularExpression)
        // Remove bold/italic markers (basic)
        parsed = parsed.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
        parsed = parsed.replacingOccurrences(of: #"\*([^*]+)\*"#, with: "$1", options: .regularExpression)
        return parsed
    }
}


// MARK: - Profile View
struct ProfileView: View {
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Profile Header
                VStack(spacing: 16) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    if let user = authManager.user {
                        Text(user.name ?? "User")
                            .poppins(.semibold, size: 22)
                        
                        if let email = user.email {
                            Text(email)
                                .poppins(.regular, size: 14)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("User")
                            .poppins(.semibold, size: 22)
                    }
                }
                .padding(.top, 40)
                
                Spacer()
                
                // Logout Button
                Button(action: {
                    authManager.logout()
                }) {
                    Text("Log Out")
                        .poppins(.semibold, size: 16)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var selectedTab: Tab = .findGyms
    
    var body: some View {
        VStack(spacing: 0) {
            // Content
            Group {
                switch selectedTab {
                case .findGyms:
                    FindGymsView(onNavigateToPasses: {
                        selectedTab = .myPasses
                    })
                    .environmentObject(authManager)
                case .myPasses:
                    MyPassesView()
                        .environmentObject(authManager)
                case .profile:
                    ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Bottom Navigation Bar
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button(action: {
                        selectedTab = tab
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 24))
                            Text(tab.rawValue)
                                .poppins(.regular, size: 12)
                        }
                        .foregroundColor(selectedTab == tab ? .orange : .gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }
            }
            .background(Color.white)
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: -2)
        }
    }
}

// MARK: - Main View
struct MainView: View {
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        MainTabView()
            .environmentObject(authManager)
    }
}

#Preview {
    MainView()
        .environmentObject(AuthManager())
}

