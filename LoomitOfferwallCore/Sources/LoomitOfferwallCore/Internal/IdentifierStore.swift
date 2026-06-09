//
//  IdentifierStore.swift
//  LoomitOfferwallCore
//
//  Manejo de identifiers persistentes del SDK.
//
//  Invariantes (ARCHITECTURE.md §2.3):
//  - `xifa` es el ÚNICO install identifier. UUID v4, persistido en UserDefaults.
//    Sobrevive a reinstalls solo si iCloud Keychain está habilitado y el
//    publisher comparte keychain group (no implementado por ahora — es UD).
//  - `install_id` PROHIBIDO. No existe.
//  - `device_fingerprint` v1 = SHA-256(IDFV + ":" + bundleIdentifier).
//  - Si IDFV es `nil` (edge case durante install/uninstall), fallback a un
//    UUID estable persistido junto al xifa.
//
//  Diseño:
//  - Protocolo `IdentifierStoring` para tests con doubles.
//  - Impl default usa `UserDefaults.standard` y `UIDevice.current`.
//  - El cómputo de fingerprint es determinístico y se cachea en memoria.
//

import Foundation
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

/// Protocolo que abstrae el acceso a identifiers.
public protocol IdentifierStoring: AnyObject, Sendable {

    /// XIFA — install identifier persistente. Generado on-first-access.
    func xifa() -> String

    /// IDFV (Identifier for Vendor). `nil` solo en edge cases muy raros.
    func idfv() -> String?

    /// Bundle identifier de la app del publisher. Casi siempre presente.
    func bundleIdentifier() -> String?

    /// Device fingerprint v1 — SHA-256(IDFV-or-fallback + ":" + bundleId).
    /// Hex lowercase, longitud 64.
    func deviceFingerprint() -> String
}

// MARK: - Implementación default

/// Impl basada en `UserDefaults` + `UIDevice` + `Bundle`.
public final class IdentifierStore: IdentifierStoring, @unchecked Sendable {

    // MARK: Keys

    private enum Keys {
        static let xifa             = "com.loomit.offerwall.xifa"
        static let idfvFallback     = "com.loomit.offerwall.idfv_fallback"
        static let fingerprintCache = "com.loomit.offerwall.fingerprint_v1"
    }

    // MARK: Dependencies

    private let defaults: UserDefaultsSafe
    private let bundle: Bundle
    private let idfvProvider: () -> String?

    /// Lock para inicialización lazy thread-safe del xifa.
    private let lock = NSLock()

    /// Cache en memoria del fingerprint (no cambia durante lifetime de la app).
    private var cachedFingerprint: String?

    public init(
        defaults: UserDefaultsSafe = UserDefaultsSafe(),
        bundle: Bundle = .main,
        idfvProvider: @escaping () -> String? = { UIDevice.current.identifierForVendor?.uuidString }
    ) {
        self.defaults = defaults
        self.bundle = bundle
        self.idfvProvider = idfvProvider
    }

    // MARK: - XIFA

    public func xifa() -> String {
        lock.lock()
        defer { lock.unlock() }

        if let existing = defaults.string(forKey: Keys.xifa), !existing.isEmpty {
            return existing
        }

        let new = UUID().uuidString.lowercased()
        defaults.set(new, forKey: Keys.xifa)
        return new
    }

    // MARK: - IDFV

    public func idfv() -> String? {
        idfvProvider()?.lowercased()
    }

    /// IDFV o, si es `nil`, un UUID fallback persistido.
    /// Privado: el fingerprint usa esto, no IDFV directo.
    private func idfvOrFallback() -> String {
        if let real = idfv() {
            return real
        }

        lock.lock()
        defer { lock.unlock() }

        if let existing = defaults.string(forKey: Keys.idfvFallback), !existing.isEmpty {
            return existing
        }

        let new = UUID().uuidString.lowercased()
        defaults.set(new, forKey: Keys.idfvFallback)
        return new
    }

    // MARK: - Bundle ID

    public func bundleIdentifier() -> String? {
        bundle.bundleIdentifier
    }

    // MARK: - Device fingerprint v1

    public func deviceFingerprint() -> String {
        lock.lock()
        if let cached = cachedFingerprint {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let idfv = idfvOrFallback()
        let bundleId = bundleIdentifier() ?? "unknown.bundle"
        let input = "\(idfv):\(bundleId)"

        let digest = SHA256.hash(data: Data(input.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()

        lock.lock()
        cachedFingerprint = hex
        lock.unlock()

        return hex
    }

    // MARK: - Test helpers (internal)

    /// Solo para tests: limpia el cache de fingerprint en memoria.
    /// No afecta UserDefaults.
    func resetMemoryCacheForTesting() {
        lock.lock()
        cachedFingerprint = nil
        lock.unlock()
    }
}
