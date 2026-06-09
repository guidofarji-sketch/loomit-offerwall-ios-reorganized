//
//  AdapterRegistry.swift
//  LoomitOfferwallCore
//
//  Registro de adapters que el publisher registra explícitamente al bootstrap.
//
//  Decisión arquitectónica: usamos registro EXPLÍCITO (no auto-discovery por
//  reflection o ServiceLoader). Razones:
//  - iOS no tiene ServiceLoader nativo confiable para frameworks compilados.
//  - Auditable: un grep busca `registerAdapter` y muestra todos los providers
//    integrados.
//  - Evita la trampa §10.4 ARCHITECTURE.md (módulo opcional ausente / pero
//    referenciado).
//

import Foundation
import LoomitOfferwallAdapterAPI

/// Registro thread-safe de adapters. Implementado como `actor` para acceso
/// concurrente seguro desde cualquier contexto.
actor AdapterRegistry {

    /// Map normalized key (lowercase) → adapter.
    /// Una key apunta a un solo adapter (último wins si se registra dos veces).
    private var adapters: [String: any OfferwallAdapter] = [:]

    /// Lista de adapters registrados en orden de registro (útil para debug
    /// y para detectar adapters huérfanos en logs).
    private(set) var registrationOrder: [any OfferwallAdapter] = []

    init() {}

    // MARK: - Mutación

    /// Registra un adapter. Si otro adapter ya cubría alguna de sus
    /// `supportedKeys`, lo reemplaza (last-wins) y devuelve `true`.
    /// Devuelve `false` si era el primer registro y no hubo reemplazo.
    @discardableResult
    func register(_ adapter: any OfferwallAdapter) -> Bool {
        var didReplace = false

        for key in adapter.supportedKeys.map({ $0.lowercased() }) {
            if adapters[key] != nil {
                didReplace = true
            }
            adapters[key] = adapter
        }

        // Reemplazamos también en registrationOrder si era duplicado por nombre.
        if let existingIdx = registrationOrder.firstIndex(where: { $0.providerName == adapter.providerName }) {
            registrationOrder[existingIdx] = adapter
        } else {
            registrationOrder.append(adapter)
        }

        return didReplace
    }

    /// Quita el adapter que cubre `providerKey` (case-insensitive). Quita
    /// también las otras keys que el mismo adapter cubría.
    @discardableResult
    func unregister(providerKey: String) -> Bool {
        let normalized = providerKey.lowercased()
        guard let adapter = adapters[normalized] else { return false }

        for key in adapter.supportedKeys.map({ $0.lowercased() }) {
            adapters[key] = nil
        }
        registrationOrder.removeAll { $0.providerName == adapter.providerName }
        return true
    }

    /// Borra todos los adapters. Útil para tests / reinicio.
    func removeAll() {
        adapters.removeAll()
        registrationOrder.removeAll()
    }

    // MARK: - Lookup

    /// Resuelve un adapter por key. Case-insensitive.
    func adapter(for providerKey: String) -> (any OfferwallAdapter)? {
        adapters[providerKey.lowercased()]
    }

    /// `true` si hay un adapter registrado para `providerKey`.
    func hasAdapter(for providerKey: String) -> Bool {
        adapter(for: providerKey) != nil
    }

    /// Lista de keys conocidas (lowercase).
    var registeredKeys: [String] {
        Array(adapters.keys).sorted()
    }

    /// Cantidad de adapters únicos registrados.
    var count: Int {
        registrationOrder.count
    }
}
