//
//  EmergencyConfigLoader.swift
//  LoomitOfferwallCore
//
//  Emergency configuration loader from bundled resources.
//  Paridad con Android `EmergencyConfigLoader.kt`.
//

import Foundation

/// Emergency configuration loader from bundled assets.
/// 
/// Provides a last-resort fallback when network and cache both fail.
/// The emergency config should be bundled in Resources/EmergencyConfig.json
/// and updated with each SDK release.
public final class EmergencyConfigLoader: Sendable {
    
    private static let fileName = "EmergencyConfig"
    private static let fileExtension = "json"
    
    /// Loads emergency configuration from bundled resources.
    /// Returns nil if file doesn't exist or is invalid.
    public func load() -> ConfigSnapshot? {
        guard let url = Bundle.main.url(
            forResource: Self.fileName,
            withExtension: Self.fileExtension
        ) else {
            print("[EmergencyConfig] Emergency config file not found in bundle")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            let json = String(data: data, encoding: .utf8) ?? ""
            
            let config = try JSONDecoder().decode(ConfigResponse.self, from: data)
            
            print("[EmergencyConfig] Emergency config loaded from bundle")
            
            return ConfigSnapshot(
                config: config,
                timestamp: Date(),
                source: .emergency,
                checksum: computeChecksum(json)
            )
        } catch {
            print("[EmergencyConfig] Failed to load emergency config: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Compute SHA-256 checksum for integrity validation.
    private func computeChecksum(_ jsonString: String) -> String {
        let data = Data(jsonString.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - SHA256 Implementation

import CryptoKit

/// SHA-256 hashing for integrity checks.
private enum SHA256 {
    static func hash(data: Data) -> some Digest {
        return CryptoKit.SHA256.hash(data: data)
    }
}
