//
//  TapjoyConfig.swift
//  LoomitOfferwallAdapterTapjoy
//
//  Parsing tipado de la configuración que el backend manda en
//  `credentials` + `settings` para Tapjoy. Paridad con Android `TapjoyBlock`.
//

import Foundation
import LoomitOfferwallAdapterAPI

/// Configuración tipada del provider Tapjoy (alias: Unity Offerwall).
///
/// Mapea el subconjunto de Tapjoy SDK que el adapter aplica durante
/// `initialize`. Source: <https://docs.unity.com/grow/offerwall/ios>.
public struct TapjoyConfig: Sendable, Equatable {

    /// SDK key de Tapjoy. **Required.** Obtenida en el dashboard de Unity.
    public let sdkKey: String

    /// Placement ID para producción. **Required.**
    public let placementId: String

    /// Placement ID para pruebas. Opcional, usado cuando testMode=true.
    public let testPlacementId: String?

    /// Modo de prueba. Si true, usa testPlacementId y habilita debug logging.
    public let testMode: Bool

    /// URL del servicio de Tapjoy. Opcional, usa default si no se especifica.
    public let serviceUrl: String?

    /// URL del servicio de placements. Opcional.
    public let placementServiceUrl: String?

    /// Dominio de redirect. Opcional.
    public let redirectDomain: String?

    /// URLs de fallback en caso de que serviceUrl falle. Opcional.
    public let fallbackServiceUrls: [String]

    /// Deshabilita el offerwall gateway. Opcional.
    public let disableOfferwallGateway: Bool?

    public init(
        sdkKey: String,
        placementId: String,
        testPlacementId: String? = nil,
        testMode: Bool = false,
        serviceUrl: String? = nil,
        placementServiceUrl: String? = nil,
        redirectDomain: String? = nil,
        fallbackServiceUrls: [String] = [],
        disableOfferwallGateway: Bool? = nil
    ) {
        self.sdkKey = sdkKey
        self.placementId = placementId
        self.testPlacementId = testPlacementId
        self.testMode = testMode
        self.serviceUrl = serviceUrl
        self.placementServiceUrl = placementServiceUrl
        self.redirectDomain = redirectDomain
        self.fallbackServiceUrls = fallbackServiceUrls
        self.disableOfferwallGateway = disableOfferwallGateway
    }

    // MARK: - Parsing

    /// Construye el config desde un `ProviderConfig`. Acepta los aliases que
    /// el backend puede usar (`sdk_key` vs `sdkKey`, `placement_id` vs `placementId`).
    /// Retorna `.failure` si faltan campos obligatorios.
    public static func parse(from providerConfig: ProviderConfig) -> Result<TapjoyConfig, OfferwallError> {
        // Mergeamos credentials y settings — backend a veces los pone en uno u otro.
        let merged = providerConfig.credentials.merging(providerConfig.settings) { lhs, _ in lhs }

        let sdkKey = lookup(["sdk_key", "apiKey", "api_key"], in: merged) ?? ""
        guard !sdkKey.isEmpty else {
            return .failure(.invalidConfiguration(reason: "Tapjoy sdk_key is required"))
        }

        let placementId = lookup(["placement_id", "placementId"], in: merged) ?? ""
        guard !placementId.isEmpty else {
            return .failure(.invalidConfiguration(reason: "Tapjoy placement_id is required"))
        }

        // testMode - default false
        let testMode: Bool = {
            guard let raw = lookup(["test_mode", "testMode"], in: merged)?.lowercased() else { return false }
            return raw == "true" || raw == "1"
        }()

        // fallbackServiceUrls - parse como array separado por comas
        let fallbackServiceUrls: [String] = {
            guard let raw = lookup(["fallback_service_urls", "fallbackServiceUrls"], in: merged) else { return [] }
            return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }()

        // disableOfferwallGateway - optional boolean
        let disableOfferwallGateway: Bool? = {
            guard let raw = lookup(["disable_offerwall_gateway", "disableOfferwallGateway"], in: merged)?.lowercased() else { return nil }
            return raw == "true" || raw == "1"
        }()

        return .success(TapjoyConfig(
            sdkKey: sdkKey,
            placementId: placementId,
            testPlacementId: lookup(["test_placement_id", "testPlacementId"], in: merged),
            testMode: testMode,
            serviceUrl: lookup(["service_url", "serviceUrl"], in: merged),
            placementServiceUrl: lookup(["placement_service_url", "placementServiceUrl"], in: merged),
            redirectDomain: lookup(["redirect_domain", "redirectDomain"], in: merged),
            fallbackServiceUrls: fallbackServiceUrls,
            disableOfferwallGateway: disableOfferwallGateway
        ))
    }

    private static func lookup(_ keys: [String], in dict: [String: String]) -> String? {
        for key in keys {
            if let value = dict[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
