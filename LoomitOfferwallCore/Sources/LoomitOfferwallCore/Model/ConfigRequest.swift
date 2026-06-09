//
//  ConfigRequest.swift
//  LoomitOfferwallCore
//
//  Wire request body para POST /get-app-config.
//
//  Paridad exacta con Android `ConfigRequest` en `BackendClient.kt`. Cualquier
//  cambio acá requiere coordinación con backend Y Android (mismo schema).
//
//  Convención: usamos snake_case en JSON via CodingKeys para mantener un schema
//  uniforme con Android/backend.
//

import Foundation

/// Body del request a `/get-app-config`.
///
/// **Contrato wire**: este schema lo comparten Android, iOS y backend.
/// Renames requieren coordinación cross-team. Los campos opcionales (`nil`)
/// se omiten del JSON via `JSONEncoder` con `keyEncodingStrategy` apropiada.
public struct ConfigRequest: Codable, Sendable, Equatable {

    /// Identificador del cliente (publisher) en backend Loomit.
    public let clientId: String

    /// App ID en backend Loomit (suele coincidir con bundle id pero puede diferir).
    public let appId: String?

    /// Bundle identifier de la app iOS. En Android es `package_name`.
    /// Mantenemos ese nombre en wire por paridad cross-platform.
    public let packageName: String?

    /// User ID provisto por el publisher (opcional).
    public let publisherUserId: String?

    /// Install identifier persistente del SDK. **Siempre presente**.
    public let xifa: String

    // MARK: Privacy

    public let tcfConsentString: String?
    public let usPrivacyString: String?
    public let subjectToGdpr: Bool?
    public let gdprConsent: Bool?
    public let ccpaOptOut: Bool?

    // MARK: Context

    public let country: String?
    /// Plataforma. En iOS usar `"ios"` (en Android es `"android"`).
    public let platform: String?
    public let sdkVersion: String?
    public let appVersion: String?

    // MARK: Advertising ID

    /// `true` si tenemos AAID (Android) / IDFA (iOS) disponible.
    public let hasAdvertisingId: Bool

    /// El AAID/IDFA propiamente dicho. Mantenemos el nombre `aaid` para paridad
    /// cross-platform (en iOS es semánticamente `idfa`, pero el backend conoce
    /// el campo por su nombre Android histórico).
    public let aaid: String?

    // MARK: Custom

    public let customProperties: [String: String]?

    public let abTestOverride: AbTestOverridePayload?

    public init(
        clientId: String,
        appId: String? = nil,
        packageName: String? = nil,
        publisherUserId: String? = nil,
        xifa: String,
        tcfConsentString: String? = nil,
        usPrivacyString: String? = nil,
        subjectToGdpr: Bool? = nil,
        gdprConsent: Bool? = nil,
        ccpaOptOut: Bool? = nil,
        country: String? = nil,
        platform: String? = nil,
        sdkVersion: String? = nil,
        appVersion: String? = nil,
        hasAdvertisingId: Bool = false,
        aaid: String? = nil,
        customProperties: [String: String]? = nil,
        abTestOverride: AbTestOverridePayload? = nil
    ) {
        self.clientId = clientId
        self.appId = appId
        self.packageName = packageName
        self.publisherUserId = publisherUserId
        self.xifa = xifa
        self.tcfConsentString = tcfConsentString
        self.usPrivacyString = usPrivacyString
        self.subjectToGdpr = subjectToGdpr
        self.gdprConsent = gdprConsent
        self.ccpaOptOut = ccpaOptOut
        self.country = country
        self.platform = platform
        self.sdkVersion = sdkVersion
        self.appVersion = appVersion
        self.hasAdvertisingId = hasAdvertisingId
        self.aaid = aaid
        self.customProperties = customProperties
        self.abTestOverride = abTestOverride
    }

    private enum CodingKeys: String, CodingKey {
        case clientId            = "client_id"
        case appId               = "app_id"
        case packageName         = "package_name"
        case publisherUserId     = "publisher_user_id"
        case xifa
        case tcfConsentString    = "tcf_consent_string"
        case usPrivacyString     = "us_privacy_string"
        case subjectToGdpr       = "subject_to_gdpr"
        case gdprConsent         = "gdpr_consent"
        case ccpaOptOut          = "ccpa_opt_out"
        case country
        case platform
        case sdkVersion          = "sdk_version"
        case appVersion          = "app_version"
        case hasAdvertisingId    = "has_advertising_id"
        case aaid
        case customProperties    = "custom_properties"
        case abTestOverride      = "ab_test_override"
    }
}

// MARK: - AbTestOverridePayload

/// Override explícito de A/B test que el publisher puede setear para forzar
/// una variante (debug/QA). El backend respeta esto si está dentro de los
/// experimentos configurados.
///
/// Paridad con Android `AbTestOverridePayload` en `OfferwallSdk.kt`.
public struct AbTestOverridePayload: Codable, Sendable, Equatable {

    public let experimentId: String
    public let experimentName: String
    public let group: String

    public init(experimentId: String, experimentName: String, group: String) {
        self.experimentId = experimentId
        self.experimentName = experimentName
        self.group = group
    }

    private enum CodingKeys: String, CodingKey {
        case experimentId    = "experiment_id"
        case experimentName = "experiment_name"
        case group
    }
}
