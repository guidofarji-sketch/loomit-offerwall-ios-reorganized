//
//  ConfigSnapshot.swift
//  LoomitOfferwallCore
//
//  Snapshot de ConfigResponse con metadata para cache management.
//  Paridad con Android `ConfigSource` + `ConfigSnapshot`.
//

import Foundation

/// Fuente de la configuración cargada.
public enum ConfigSource: String, Sendable, Codable {
    /// Fresca, recién obtenida del backend.
    case network = "NETWORK"
    /// De cache, menos de 24h.
    case cacheFresh = "CACHE_FRESH"
    /// De cache, más de 24h (stale pero usable).
    case cacheStale = "CACHE_STALE"
    /// De snapshot de emergencia bundled.
    case emergency = "EMERGENCY"
}

/// Snapshot de configuración con metadata.
public struct ConfigSnapshot: Sendable, Equatable {

    /// Config response real.
    public let config: ConfigResponse

    /// Cuándo se obtuvo originalmente (epoch).
    public let timestamp: Date

    /// De dónde vino.
    public let source: ConfigSource

    /// SHA-256 del JSON serializado, para integrity check.
    public let checksum: String

    public init(
        config: ConfigResponse,
        timestamp: Date,
        source: ConfigSource,
        checksum: String
    ) {
        self.config = config
        self.timestamp = timestamp
        self.source = source
        self.checksum = checksum
    }

    /// Edad del snapshot (ahora - timestamp).
    public func age(now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(timestamp)
    }

    /// Si es "fresco" (< 24h por default).
    public func isFresh(maxAge: TimeInterval = freshThreshold, now: Date = Date()) -> Bool {
        age(now: now) < maxAge
    }

    /// Si es stale pero todavía usable (entre fresh y 7d por default).
    public func isStale(
        staleUpperBound: TimeInterval = staleThreshold,
        freshUpperBound: TimeInterval = freshThreshold,
        now: Date = Date()
    ) -> Bool {
        let a = age(now: now)
        return a >= freshUpperBound && a < staleUpperBound
    }

    /// Si está demasiado viejo para usar (> 7d por default).
    public func isExpired(maxAge: TimeInterval = staleThreshold, now: Date = Date()) -> Bool {
        age(now: now) >= maxAge
    }

    /// 24 horas en segundos.
    public static let freshThreshold: TimeInterval = 24 * 60 * 60

    /// 7 días en segundos.
    public static let staleThreshold: TimeInterval = 7 * 24 * 60 * 60
}
