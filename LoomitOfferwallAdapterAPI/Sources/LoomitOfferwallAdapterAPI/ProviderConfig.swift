//
//  ProviderConfig.swift
//  LoomitOfferwallAdapterAPI
//
//  Configuración tipada que `OfferwallSdk` entrega al adapter en initialize().
//
//  Diseño:
//  - `credentials`: secretos/identificadores del publisher en el provider
//    (ej: "sdk_key" Tapjoy, "app_id" MyChips/MAF). Vienen del backend.
//  - `settings`: parámetros no-secretos (ej: "placement_id"). Vienen del backend.
//  - `privacy`: resolución unificada de consent (TCF, GDPR, US-Privacy, COPPA).
//  - `userId`: cascada determinística currentUserId ?? publisherUserId ?? xifa.
//             **Garantizado no-nil** por core. Ver ARCHITECTURE.md §2.3.
//

import Foundation

/// Configuración entregada por core a un provider en `OfferwallProvider.initialize(...)`.
///
/// `Sendable` para cruzar actor boundaries sin warnings.
public struct ProviderConfig: Sendable, Equatable {

    /// Key normalizado del provider (ej: "tapjoy", "mychips"). Lower-case.
    public let providerKey: String

    /// Prioridad dentro del waterfall (1 = más alta). Solo informativo para el adapter.
    public let priority: Int

    /// Secretos/identificadores opacos que el provider necesita para inicializar.
    ///
    /// Ejemplos:
    /// - Tapjoy: `["sdk_key": "<...>"]`
    /// - MyChips/MAF: `["app_id": "<...>"]`
    public let credentials: [String: String]

    /// Parámetros no-secretos para configurar el comportamiento del provider.
    ///
    /// Ejemplos:
    /// - Tapjoy: `["placement_name": "main_offerwall"]`
    /// - MyChips: `["placement_id": "<id>"]`
    public let settings: [String: String]

    /// Resolución unificada de privacidad. Ver `PrivacyConfig`.
    public let privacy: PrivacyConfig

    /// User ID a usar para el provider.
    ///
    /// Cascada aplicada por core: `currentUserId ?? publisherUserId ?? xifa`.
    /// **Nunca nil**.
    public let userId: String

    /// XIFA (install identifier persistente del SDK). Usado por providers que
    /// requieren un identificador estable distinto del userId del publisher.
    public let xifa: String

    /// Identificador de aplicación en backend de Loomit.
    public let appId: String

    /// Country ISO-2 detectado o asignado por el backend (ej: "AR", "US").
    public let country: String?

    /// Versión del SDK Loomit.
    public let sdkVersion: String

    /// Versión de la app del publisher.
    public let appVersion: String?

    /// Overrides de ad_space específicos para este provider.
    /// Map de ad_space_id → credentials específicas para ese ad_space.
    /// Si hay un override para un adSpace, sus credentials reemplazan a las default.
    public let adSpaceOverrides: [String: [String: String]]

    public init(
        providerKey: String,
        priority: Int,
        credentials: [String: String] = [:],
        settings: [String: String] = [:],
        privacy: PrivacyConfig = .empty,
        userId: String,
        xifa: String,
        appId: String,
        country: String? = nil,
        sdkVersion: String,
        appVersion: String? = nil,
        adSpaceOverrides: [String: [String: String]] = [:]
    ) {
        self.providerKey = providerKey.lowercased()
        self.priority = priority
        self.credentials = credentials
        self.settings = settings
        self.privacy = privacy
        self.userId = userId
        self.xifa = xifa
        self.appId = appId
        self.country = country
        self.sdkVersion = sdkVersion
        self.appVersion = appVersion
        self.adSpaceOverrides = adSpaceOverrides
    }
}

// MARK: - PrivacyConfig

/// Resolución unificada de consent que core entrega a cada provider.
///
/// El core resuelve TCF / US-Privacy / GDPR / COPPA en `PrivacyResolver` y entrega
/// a cada adapter este objeto consistente. **Nunca leer consent crudo en adapters.**
public struct PrivacyConfig: Sendable, Equatable {

    /// El usuario está sujeto a GDPR.
    public let isGDPRApplicable: Bool

    /// El usuario otorgó consentimiento bajo GDPR. `nil` si no aplica.
    public let hasGDPRConsent: Bool?

    /// String IAB TCF v2.x (consent string). `nil` si no aplica/disponible.
    public let tcfString: String?

    /// String US-Privacy (CCPA). Formato: "1YNN", "1NNN", etc. `nil` si no aplica.
    public let usPrivacyString: String?

    /// El usuario es menor de 13 (COPPA). Si `true`, providers deben deshabilitar
    /// personalización y tracking sensible.
    public let isChildDirected: Bool

    /// El publisher solicitó modo "limited data" (mínimo de tracking).
    public let limitedDataUse: Bool

    /// CCPA opt-out. `true` si el usuario optó por no vender sus datos (US).
    /// Inferido de US-Privacy string o seteado explícitamente por el publisher.
    /// Paridad con Android `OfferwallConfig.ccpaOptOut`.
    public let ccpaOptOut: Bool?

    public init(
        isGDPRApplicable: Bool = false,
        hasGDPRConsent: Bool? = nil,
        tcfString: String? = nil,
        usPrivacyString: String? = nil,
        isChildDirected: Bool = false,
        limitedDataUse: Bool = false,
        ccpaOptOut: Bool? = nil
    ) {
        self.isGDPRApplicable = isGDPRApplicable
        self.hasGDPRConsent = hasGDPRConsent
        self.tcfString = tcfString
        self.usPrivacyString = usPrivacyString
        self.isChildDirected = isChildDirected
        self.limitedDataUse = limitedDataUse
        self.ccpaOptOut = ccpaOptOut
    }

    /// Configuración vacía (sin consent applicable). Útil como default.
    public static let empty = PrivacyConfig()
}
