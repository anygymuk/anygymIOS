//
//  PassStorageService.swift
//  AnyGym
//
//  Local storage service for active passes and pass history
//

import Foundation
import SwiftUI

@MainActor
class PassStorageService: ObservableObject {
    
    // MARK: - Storage Keys
    private enum StorageKey {
        static let activePass = "activePass"
        static let passHistory = "passHistory"
    }
    
    // MARK: - File Manager
    private let fileManager = FileManager.default
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    // MARK: - User Defaults
    private let userDefaults = UserDefaults.standard
    
    // MARK: - Active Pass Management
    
    func saveActivePass(_ pass: Pass, downloadQR: Bool = true) async {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(pass)
            userDefaults.set(data, forKey: StorageKey.activePass)
            print("✅ Active pass saved to local storage: Pass ID \(pass.id)")
            
            if downloadQR {
                await downloadAndCacheQRCode(for: pass)
            }
        } catch {
            print("❌ Error saving active pass: \(error.localizedDescription)")
        }
    }
    
    func loadActivePass() -> Pass? {
        guard let data = userDefaults.data(forKey: StorageKey.activePass) else {
            print("ℹ️ No active pass found in local storage")
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let pass = try decoder.decode(Pass.self, from: data)
            print("✅ Active pass loaded from local storage: Pass ID \(pass.id)")
            return pass
        } catch {
            print("❌ Error loading active pass: \(error.localizedDescription)")
            return nil
        }
    }
    
    func deleteActivePass() {
        userDefaults.removeObject(forKey: StorageKey.activePass)
        print("✅ Active pass deleted from local storage")
    }
    
    // MARK: - Pass History Management
    
    func savePassHistory(_ history: [Pass]) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(history)
            userDefaults.set(data, forKey: StorageKey.passHistory)
            print("✅ Pass history saved to local storage: \(history.count) passes")
        } catch {
            print("❌ Error saving pass history: \(error.localizedDescription)")
        }
    }
    
    func loadPassHistory() -> [Pass] {
        guard let data = userDefaults.data(forKey: StorageKey.passHistory) else {
            print("ℹ️ No pass history found in local storage")
            return []
        }
        
        do {
            let decoder = JSONDecoder()
            let history = try decoder.decode([Pass].self, from: data)
            print("✅ Pass history loaded from local storage: \(history.count) passes")
            return history
        } catch {
            print("❌ Error loading pass history: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - QR Code Image Caching
    
    func downloadAndCacheQRCode(for pass: Pass) async {
        guard let qrcodeUrlString = pass.qrcodeUrl,
              let qrcodeUrl = URL(string: qrcodeUrlString) else {
            print("⚠️ No QR code URL for pass ID \(pass.id)")
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: qrcodeUrl)
            
            if let image = UIImage(data: data),
               let pngData = image.pngData() {
                let fileURL = getQRImageURL(for: pass.id)
                try pngData.write(to: fileURL)
                print("✅ QR code cached for pass ID \(pass.id)")
            }
        } catch {
            print("❌ Error downloading/caching QR code for pass ID \(pass.id): \(error.localizedDescription)")
        }
    }
    
    func getCachedQRImage(for passId: Int) -> UIImage? {
        let fileURL = getQRImageURL(for: passId)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            return UIImage(data: data)
        } catch {
            print("❌ Error loading cached QR image for pass ID \(passId): \(error.localizedDescription)")
            return nil
        }
    }
    
    func deleteCachedQRImage(for passId: Int) {
        let fileURL = getQRImageURL(for: passId)
        
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.removeItem(at: fileURL)
                print("✅ Cached QR image deleted for pass ID \(passId)")
            } catch {
                print("❌ Error deleting cached QR image for pass ID \(passId): \(error.localizedDescription)")
            }
        }
    }
    
    private func getQRImageURL(for passId: Int) -> URL {
        documentsDirectory.appendingPathComponent("qr_\(passId).png")
    }
    
    // MARK: - Pass Expiration & Cleanup
    
    func cleanupExpiredPass(_ pass: Pass) {
        let history = loadPassHistory()
        let isInHistory = history.contains(where: { $0.id == pass.id })
        
        if isInHistory {
            print("✅ Pass ID \(pass.id) is in history, removing from active storage")
            deleteActivePass()
            deleteCachedQRImage(for: pass.id)
        } else {
            print("ℹ️ Pass ID \(pass.id) not in history yet, keeping in active storage")
        }
    }
    
    func isPassExpired(_ pass: Pass) -> Bool {
        guard let validUntilString = pass.validUntil else {
            return false
        }
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let validUntilDate = isoFormatter.date(from: validUntilString) {
            return Date() > validUntilDate
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        
        if let validUntilDate = formatter.date(from: validUntilString) {
            return Date() > validUntilDate
        }
        
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        if let validUntilDate = formatter.date(from: validUntilString) {
            return Date() > validUntilDate
        }
        
        return false
    }
    
    func checkAndCleanupExpiredActivePass() {
        guard let activePass = loadActivePass() else {
            return
        }
        
        if isPassExpired(activePass) {
            print("⚠️ Active pass ID \(activePass.id) has expired")
            cleanupExpiredPass(activePass)
        }
    }
    
    // MARK: - Complete Storage Cleanup
    
    func clearAllStorage() {
        deleteActivePass()
        userDefaults.removeObject(forKey: StorageKey.passHistory)
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            for fileURL in contents where fileURL.lastPathComponent.hasPrefix("qr_") {
                try fileManager.removeItem(at: fileURL)
            }
            print("✅ All local storage cleared")
        } catch {
            print("❌ Error clearing QR cache: \(error.localizedDescription)")
        }
    }
}
