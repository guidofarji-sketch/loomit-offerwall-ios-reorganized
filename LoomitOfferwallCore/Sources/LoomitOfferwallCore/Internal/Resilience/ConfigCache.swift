//
//  ConfigCache.swift
//  LoomitOfferwallCore
//
//  Cache persistente 3-tier (fresh / stale / emergency) para ConfigResponse.
//  Paridad con Android `SharedPreferencesConfigCache`. En iOS usamos `UserDefaults`
//  (equivalente a SharedPreferences) + integrity check con SHA-256.
//

import Foundation
import CryptoKit

/// Protocolo para operaciones de caching de config.
public protocol ConfigCache: Sendable {

    /// Guarda un snapshot. Retorna `true` si tuvo éxito.
    func save(_ snapshot: ConfigSnapshot) -> Bool

    /// Carga el snapshot más reciente. `nil` si no hay cache válido.
    func load() -> ConfigSnapshot?

    /// Edad del cache en segundos. `nil` si no hay cache.
    func getAge() -> TimeInterval?

    /// Si el cache está más viejo que `maxAge`.
    func isStale(maxAge: TimeInterval) -> Bool

    /// Limpia todo el cache.
    func clear()
}

/// Implementación basada en `UserDefaults` (equivalente iOS de SharedPreferences).
public final class UserDefaultsConfigCache: ConfigCache, @unchecked Sendable {

    private let defaults: UserDefaults
    private let namespace: String
    private let clock: @Sendable () -> Date

    private var keyJSON: String { "\(namespace).config_json" }
    private var keyTimestamp: String { "\(namespace).config_timestamp" }
    private var keySource: String { "\(namespace).config_source" }
    private var keyChecksum: String { "\(namespace).config_checksum" }

    public init(
        defaults: UserDefaults = .standard,
        namespace: String = "loomit.offerwall.config_cache",
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.namespace = namespace
        self.clock = clock
    }

    public func save(_ snapshot: ConfigSnapshot) -> Bool {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(snapshot.config)
            guard let json = String(data: data, encoding: .utf8) else { return false }
            let checksum = Self.sha256(json)

            defaults.set(json, forKey: keyJSON)
            defaults.set(snapshot.timestamp.timeIntervalSince1970, forKey: keyTimestamp)
            defaults.set(snapshot.source.rawValue, forKey: keySource)
            defaults.set(checksum, forKey: keyChecksum)
            return true
        } catch {
            return false
        }
    }

    public func load() -> ConfigSnapshot? {
        guard let json = defaults.string(forKey: keyJSON) else {
            print("[LoomitOW] ConfigCache.load() → nil (no data)")
            return nil
        }
        // Verificamos existencia explícita en lugar de `ts > 0` para no
        // confundir un timestamp legítimo en epoch 0 con "no cache".
        guard defaults.object(forKey: keyTimestamp) != nil else { return nil }
        let ts = defaults.double(forKey: keyTimestamp)
        guard let sourceRaw = defaults.string(forKey: keySource) else { return nil }

        // Integrity check
        if let storedChecksum = defaults.string(forKey: keyChecksum) {
            let computed = Self.sha256(json)
            if storedChecksum != computed {
                clear()
                return nil
            }
        }

        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        guard let config = try? decoder.decode(ConfigResponse.self, from: data) else {
            return nil
        }

        let source = ConfigSource(rawValue: sourceRaw) ?? .cacheFresh
        return ConfigSnapshot(
            config: config,
            timestamp: Date(timeIntervalSince1970: ts),
            source: source,
            checksum: Self.sha256(json)
        )
    }

    public func getAge() -> TimeInterval? {
        guard defaults.object(forKey: keyTimestamp) != nil else { return nil }
        let ts = defaults.double(forKey: keyTimestamp)
        return clock().timeIntervalSince1970 - ts
    }

    public func isStale(maxAge: TimeInterval) -> Bool {
        guard let age = getAge() else { return true }
        return age >= maxAge
    }

    public func clear() {
        print("[LoomitOW] ConfigCache.clear() namespace=\(namespace)")
        defaults.removeObject(forKey: keyJSON)
        defaults.removeObject(forKey: keyTimestamp)
        defaults.removeObject(forKey: keySource)
        defaults.removeObject(forKey: keyChecksum)
    }

    // MARK: - Helpers

    private static func sha256(_ data: String) -> String {
        let bytes = Data(data.utf8)
        let digest = SHA256.hash(data: bytes)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
