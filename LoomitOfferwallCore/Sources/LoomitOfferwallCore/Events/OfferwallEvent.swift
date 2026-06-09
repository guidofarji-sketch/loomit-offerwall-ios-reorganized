//
//  OfferwallEvent.swift
//  LoomitOfferwallCore
//
//  Modelo del evento de telemetría que se despacha al backend (track-event)
//  o a un publisher pusher custom. Paridad con Android `OfferwallEvent`.
//

import Foundation

/// Evento de telemetría generado por el SDK.
///
/// Es `Codable`+`Sendable` para poder persistirse en la cola en disco y
/// cruzar boundaries de actor sin warnings.
public struct OfferwallEvent: Codable, Sendable, Equatable {

    /// Tipo del evento (ej: `init_provider_start`, `content_show`, `rewarded`).
    public let type: String

    /// Provider asociado al evento (ej: "tapjoy", "mychips") o "loomit" para eventos del core.
    public let provider: String

    /// XIFA del install. `nil` sólo en casos extraordinarios.
    public let xifa: String?

    /// App ID (registrado en Loomit) o bundle id como fallback.
    public let appId: String?

    /// Plataforma; en iOS siempre `"ios"`.
    public let platform: String

    /// País resuelto por el publisher (ISO 3166-1 alpha-2). Opcional.
    public let country: String?

    /// Versión de la app del publisher.
    public let appVersion: String?

    /// Versión del SDK Loomit (`SdkVersion.current`).
    public let sdkVersion: String?

    /// Modelo del device (ej: "iPhone16,1").
    public let deviceModel: String

    /// Versión del OS (ej: "17.4.1").
    public let osVersion: String

    /// Lifecycle ID — incrementa con cada init/show. Opcional.
    public let lifecycleId: Int?

    /// Timestamp en epoch ms.
    public let timestampMs: Int64

    /// Payload arbitrario adicional. Sólo valores serializables en JSON.
    public let data: [String: JSONValue]

    public init(
        type: String,
        provider: String,
        xifa: String?,
        appId: String?,
        platform: String,
        country: String?,
        appVersion: String?,
        sdkVersion: String?,
        deviceModel: String,
        osVersion: String,
        lifecycleId: Int?,
        timestampMs: Int64,
        data: [String: JSONValue] = [:]
    ) {
        self.type = type
        self.provider = provider
        self.xifa = xifa
        self.appId = appId
        self.platform = platform
        self.country = country
        self.appVersion = appVersion
        self.sdkVersion = sdkVersion
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.lifecycleId = lifecycleId
        self.timestampMs = timestampMs
        self.data = data
    }
}

/// Pusher de eventos. Permite al publisher inyectar su propia implementación
/// (ej: tests, mocks, o tracking dual a otro backend).
public protocol OfferwallEventPusher: Sendable {
    /// Envía un evento al backend. Puede tirar para indicar fallo retriable.
    func push(_ event: OfferwallEvent) async throws
}
