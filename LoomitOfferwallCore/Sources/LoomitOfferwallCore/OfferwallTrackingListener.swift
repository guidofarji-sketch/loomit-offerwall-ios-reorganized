//
//  OfferwallTrackingListener.swift
//  LoomitOfferwallCore
//
//  Listener opcional para que el publisher recoja eventos de tracking que el
//  SDK también envía al backend de Loomit. Útil si el publisher quiere
//  reflejar la misma telemetría en Firebase / Amplitude / Mixpanel.
//
//  Diseño:
//  - **No reemplaza** el envío al backend de Loomit. Es un mirror.
//  - El publisher recibe nombre del evento + payload (snake_case).
//  - Es opcional: muchos publishers no lo usan.
//

import Foundation

/// Listener opcional que recibe los eventos de tracking que el SDK
/// despacha al backend de Loomit.
@MainActor
public protocol OfferwallTrackingListener: AnyObject {

    /// Un evento de tracking fue dispatched.
    ///
    /// - Parameters:
    ///   - name: nombre del evento (snake_case, ej: `content_show`,
    ///           `provider_init_succeeded`).
    ///   - payload: properties del evento (keys snake_case).
    func offerwallTracking(didDispatchEvent name: String, payload: [String: JSONValue])
}

extension OfferwallTrackingListener {
    public func offerwallTracking(didDispatchEvent name: String, payload: [String: JSONValue]) {}
}
