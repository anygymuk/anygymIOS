//
//  GymService.swift
//  AnyGym
//
//  Created on iOS App
//

import Foundation
import Combine

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
                // Try to decode as array first
                if let gyms = try? JSONDecoder().decode([Gym].self, from: data) {
                    return gyms
                }
                // Try to decode as wrapped response
                if let response = try? JSONDecoder().decode(GymResponse.self, from: data) {
                    return response.gyms
                }
                // If both fail, throw error
                throw NSError(domain: "GymService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to decode gym data"])
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
                    self?.gyms = gyms
                    self?.isLoading = false
                }
            )
            .store(in: &cancellables)
    }
}

