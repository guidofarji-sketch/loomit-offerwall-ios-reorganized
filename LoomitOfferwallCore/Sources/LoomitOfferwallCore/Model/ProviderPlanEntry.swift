//
//  ProviderPlanEntry.swift
//  LoomitOfferwallCore
//
//  Una entry dentro de `configurations` o `default_waterfall` o
//  `ad_space_overrides[].waterfall` en la respuesta del backend.
//
//  Renombramos vs Android (`ProviderConfig`) para evitar colisión con el
//  `ProviderConfig` adapter-facing del módulo `LoomitOfferwallAdapterAPI`.
//

import Foundation

/// Entrada de provider en un plan/waterfall del backend.
///
/// **Wire-level**: `credentials` viene como `JSONValue` heterogéneo. Core
/// hace la traducción a `ProviderConfig` (typed, en `LoomitOfferwallAdapterAPI`)
/// antes de entregarlo al adapter.
public struct ProviderPlanEntry: Codable, Sendable, Equatable {

    /// Key del provider tal como llega del backend. Lo normalizamos a
    /// lower-case en el matching contra adapters registrados.
    public let providerId: String

    /// Si `false`, ignorar este provider en el waterfall.
    public let isActive: Bool

    /// Prioridad numérica dentro del waterfall (0 = más alta o más baja según
    /// convención del backend; respetamos lo que llega).
    public let priority: Int

    /// Credentials + settings opacos. La estructura interna depende del
    /// provider. Core resuelve a `[String: String]` typed antes de pasar al
    /// adapter.
    public let credentials: [String: JSONValue]

    /// Placement opcional al nivel de la entry (puede también venir embebido
    /// dentro de `credentials`).
    public let placement: String?

    public init(
        providerId: String,
        isActive: Bool = true,
        priority: Int = 0,
        credentials: [String: JSONValue] = [:],
        placement: String? = nil
    ) {
        self.providerId = providerId
        self.isActive = isActive
        self.priority = priority
        self.credentials = credentials
        self.placement = placement
    }

    private enum CodingKeys: String, CodingKey {
        case providerId  = "provider_id"
        case isActive    = "is_active"
        case priority    = "provider_priority"
        case credentials
        case placement
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.providerId  = try c.decode(String.self, forKey: .providerId)
        self.isActive    = try c.decodeIfPresent(Bool.self, forKey: .isActive)   ?? true
        self.priority    = try c.decodeIfPresent(Int.self,  forKey: .priority)    ?? 0
        self.credentials = try c.decodeIfPresent([String: JSONValue].self, forKey: .credentials) ?? [:]
        self.placement   = try c.decodeIfPresent(String.self, forKey: .placement)
    }
}

// MARK: - Conveniencia

extension ProviderPlanEntry {

    /// Provider id normalizado a lower-case para matching contra adapters.
    public var normalizedProviderId: String {
        providerId.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Devuelve un valor de `credentials` coerced a String (útil para campos
    /// que el backend a veces manda como número o bool).
    public func credentialString(_ key: String) -> String? {
        credentials[key]?.coerceToString()
    }

    /// Devuelve un valor de `credentials` coerced a Bool.
    public func credentialBool(_ key: String) -> Bool? {
        credentials[key]?.coerceToBool()
    }
}
