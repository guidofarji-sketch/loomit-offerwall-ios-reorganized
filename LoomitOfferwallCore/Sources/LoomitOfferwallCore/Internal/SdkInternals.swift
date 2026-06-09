//
//  SdkInternals.swift
//  LoomitOfferwallCore
//
//  Tipos internos compartidos por OfferwallSdk y subsistemas.
//  Mantenemos en archivo separado para no engordar OfferwallSdk.swift.
//

import Foundation

/// Configuración inmutable que el publisher provee antes de `fetchConfig`.
///
/// Contiene API key + client ID (required) + identificación + privacy + custom properties.
struct PublisherConfig: Sendable, Equatable {

    let loomitApiKey: String
    let clientId: String
    let appId: String?
    let publisherUserId: String?
    let currentUserId: String?
    let country: String?
    let appVersion: String?
    let customProperties: [String: String]
    let abTestOverride: AbTestOverridePayload?
    let advertisingId: String?
    let hasAdvertisingId: Bool

    /// Privacy crudo provisto por el publisher. Core lo unifica a `PrivacyConfig`
    /// antes de pasar a adapters.
    let privacy: PublisherPrivacy

    static func empty(apiKey: String) -> PublisherConfig {
        PublisherConfig(
            loomitApiKey: apiKey,
            clientId: apiKey,  // fallback temporal, pero setClientId debe ser llamado
            appId: nil,
            publisherUserId: nil,
            currentUserId: nil,
            country: nil,
            appVersion: nil,
            customProperties: [:],
            abTestOverride: nil,
            advertisingId: nil,
            hasAdvertisingId: false,
            privacy: .empty
        )
    }
}

/// Bloque de privacy crudo que el publisher reporta al SDK.
struct PublisherPrivacy: Sendable, Equatable {

    let tcfConsentString: String?
    let usPrivacyString: String?
    let subjectToGdpr: Bool?
    let gdprConsent: Bool?
    let ccpaOptOut: Bool?
    let isChildDirected: Bool
    let limitedDataUse: Bool

    static let empty = PublisherPrivacy(
        tcfConsentString: nil,
        usPrivacyString: nil,
        subjectToGdpr: nil,
        gdprConsent: nil,
        ccpaOptOut: nil,
        isChildDirected: false,
        limitedDataUse: false
    )
}

/// Resuelve la cascada de userId para tracking/eventos:
/// `currentUserId ?? publisherUserId ?? xifa`. **Nunca nil**.
///
/// Invariante §2.3 (ARCHITECTURE.md). Cualquier código que envíe `user_id`
/// al backend debe usar este resolver.
struct UserIdResolver: Sendable {

    let currentUserId: String?
    let publisherUserId: String?
    let xifa: String

    var resolved: String {
        if let id = currentUserId, !id.isEmpty { return id }
        if let id = publisherUserId, !id.isEmpty { return id }
        return xifa
    }
}
