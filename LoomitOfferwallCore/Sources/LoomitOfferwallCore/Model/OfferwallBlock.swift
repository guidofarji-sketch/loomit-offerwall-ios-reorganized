//
//  OfferwallBlock.swift
//  LoomitOfferwallCore
//
//  Bloque `offerwall` de la respuesta del backend.
//
//  Estructura:
//  - `default_waterfall`: lista ordenada de providers a probar cuando no hay
//    override por ad_space.
//  - `ad_space_overrides`: map de ad_space_id → waterfall específico para ese
//    ad space. Si está, reemplaza al default.
//

import Foundation

/// Bloque `offerwall` de la respuesta del backend.
public struct OfferwallBlock: Codable, Sendable, Equatable {

    public let defaultWaterfall: [ProviderPlanEntry]
    public let adSpaceOverrides: [String: AdSpaceOverride]

    public init(
        defaultWaterfall: [ProviderPlanEntry] = [],
        adSpaceOverrides: [String: AdSpaceOverride] = [:]
    ) {
        self.defaultWaterfall = defaultWaterfall
        self.adSpaceOverrides = adSpaceOverrides
    }

    private enum CodingKeys: String, CodingKey {
        case defaultWaterfall  = "default_waterfall"
        case adSpaceOverrides  = "ad_space_overrides"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.defaultWaterfall  = try c.decodeIfPresent([ProviderPlanEntry].self, forKey: .defaultWaterfall) ?? []
        self.adSpaceOverrides  = try c.decodeIfPresent([String: AdSpaceOverride].self, forKey: .adSpaceOverrides) ?? [:]
    }
}

// MARK: - AdSpaceOverride

/// Override de waterfall específico para un ad_space.
public struct AdSpaceOverride: Codable, Sendable, Equatable {

    /// Si `false`, este ad_space está deshabilitado (publisher no debería
    /// intentar mostrar offerwall en ese contexto).
    public let enabled: Bool

    /// Waterfall específico para este ad_space.
    public let waterfall: [ProviderPlanEntry]

    public init(enabled: Bool = true, waterfall: [ProviderPlanEntry] = []) {
        self.enabled = enabled
        self.waterfall = waterfall
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled   = try c.decodeIfPresent(Bool.self, forKey: .enabled)   ?? true
        self.waterfall = try c.decodeIfPresent([ProviderPlanEntry].self, forKey: .waterfall) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case waterfall
    }
}

// MARK: - Resolución de waterfall

extension OfferwallBlock {

    /// Resuelve qué waterfall aplica para un `adSpace` dado.
    ///
    /// Reglas:
    /// 1. Si hay override para `adSpace` y está enabled:
    ///    - Si el waterfall no está vacío → devuelve su waterfall
    ///    - Si el waterfall está vacío → devuelve nil (no hay muros para ese adSpace)
    /// 2. Si hay override pero está disabled → fallback a `defaultWaterfall` (caso defensivo)
    /// 3. Si no hay override (o `adSpace == nil`) → devuelve `defaultWaterfall`.
    ///
    /// Filtra entries con `isActive == false` y ordena por `priority` ascendente.
    public func resolvedWaterfall(for adSpace: String?) -> [ProviderPlanEntry]? {
        let raw: [ProviderPlanEntry]

        if let adSpace = adSpace, let override = adSpaceOverrides[adSpace] {
            if override.enabled {
                // Override está enabled: respetar su waterfall (incluso si está vacío)
                raw = override.waterfall
            } else {
                // Override disabled: fallback a default_waterfall (caso defensivo)
                raw = defaultWaterfall
            }
        } else {
            raw = defaultWaterfall
        }

        let filtered = raw.filter { $0.isActive }.sorted { $0.priority < $1.priority }

        // Si el override estaba enabled pero el waterfall filtrado está vacío, devuelve nil
        if let adSpace = adSpace, let override = adSpaceOverrides[adSpace], override.enabled {
            return filtered.isEmpty ? nil : filtered
        }

        return filtered.isEmpty ? nil : filtered
    }
}
