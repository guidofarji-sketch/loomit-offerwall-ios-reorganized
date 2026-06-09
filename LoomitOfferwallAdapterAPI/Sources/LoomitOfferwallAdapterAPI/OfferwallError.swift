//
//  OfferwallError.swift
//  LoomitOfferwallAdapterAPI
//
//  Error type compartido por core y adapters.
//
//  Convenciones (ver ../ARCHITECTURE.md §2.5):
//  - Errores estructurados, nunca strings sueltos cruzando boundaries.
//  - Cada caso lleva contexto suficiente para diagnosticar sin Stacktrace.
//  - LocalizedError para descripción legible al publisher.
//

import Foundation

/// Error de dominio del SDK Loomit Offerwall.
///
/// Cubre fallas de configuración, red, providers, y estado del SDK.
/// Es `Sendable` para cruzar boundaries de actor sin warnings.
public enum OfferwallError: Error, Sendable, Equatable {

    // MARK: - Configuración

    /// El SDK no fue inicializado correctamente (falta API key, clientId, appId).
    case notInitialized(reason: String)

    /// La configuración recibida (del backend o del publisher) es inválida.
    case invalidConfiguration(reason: String)

    /// La API key de Loomit no fue establecida via `OfferwallSdk.setLoomitApiKey(...)`.
    case missingApiKey

    // MARK: - Backend / Red

    /// Falló el fetch de configuración al backend.
    case backendUnreachable(underlying: String)

    /// El backend respondió con un código HTTP no exitoso.
    case backendHTTPError(statusCode: Int, body: String?)

    /// La respuesta del backend no se pudo parsear (JSON malformado, schema mismatch).
    case backendDecodingError(underlying: String)

    /// El circuit breaker está abierto y no hay cache disponible.
    case circuitOpenNoFallback

    /// Timeout en operación de red.
    case timeout(operation: String)

    // MARK: - Providers

    /// No hay adapter registrado para el provider key recibido.
    case providerNotRegistered(key: String)

    /// El provider falló al inicializarse.
    case providerInitializationFailed(provider: String, underlying: String)

    /// El provider no puede mostrar el offerwall en este momento.
    case providerUnavailable(provider: String, reason: String)

    /// El provider falló al mostrar el offerwall.
    case providerShowFailed(provider: String, underlying: String)

    /// El waterfall completo falló (todos los providers fallaron).
    case waterfallExhausted(attempted: [String])

    // MARK: - Lifecycle / Estado

    /// Operación inválida en el estado actual del SDK.
    case invalidState(expected: String, actual: String)

    /// Acción cancelada por el usuario o por el sistema.
    case cancelled

    /// Error inesperado no categorizado. Usar con moderación.
    case unknown(underlying: String)
}

// MARK: - LocalizedError

extension OfferwallError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .notInitialized(let reason):
            return "Loomit SDK not initialized: \(reason)"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .missingApiKey:
            return "Loomit API key is missing. Call OfferwallSdk.setLoomitApiKey(...) before fetchConfig."
        case .backendUnreachable(let underlying):
            return "Backend unreachable: \(underlying)"
        case .backendHTTPError(let statusCode, let body):
            return "Backend returned HTTP \(statusCode)\(body.map { ": \($0)" } ?? "")"
        case .backendDecodingError(let underlying):
            return "Failed to decode backend response: \(underlying)"
        case .circuitOpenNoFallback:
            return "Circuit breaker is open and no cached config is available."
        case .timeout(let operation):
            return "Operation timed out: \(operation)"
        case .providerNotRegistered(let key):
            return "No adapter registered for provider key '\(key)'. Call OfferwallSdk.registerAdapter(...) for all required adapters."
        case .providerInitializationFailed(let provider, let underlying):
            return "Provider '\(provider)' failed to initialize: \(underlying)"
        case .providerUnavailable(let provider, let reason):
            return "Provider '\(provider)' unavailable: \(reason)"
        case .providerShowFailed(let provider, let underlying):
            return "Provider '\(provider)' failed to show offerwall: \(underlying)"
        case .waterfallExhausted(let attempted):
            return "All providers in waterfall failed: \(attempted.joined(separator: ", "))"
        case .invalidState(let expected, let actual):
            return "Invalid SDK state. Expected: \(expected). Actual: \(actual)."
        case .cancelled:
            return "Operation cancelled."
        case .unknown(let underlying):
            return "Unknown error: \(underlying)"
        }
    }
}

// MARK: - Diagnostic codes

extension OfferwallError {

    /// Código corto estable para tracking/logging (snake_case).
    /// **Importante**: estos códigos son contrato con el backend de logging.
    /// No renombrar sin coordinar.
    public var diagnosticCode: String {
        switch self {
        case .notInitialized:                return "not_initialized"
        case .invalidConfiguration:          return "invalid_configuration"
        case .missingApiKey:                 return "missing_api_key"
        case .backendUnreachable:            return "backend_unreachable"
        case .backendHTTPError:              return "backend_http_error"
        case .backendDecodingError:          return "backend_decoding_error"
        case .circuitOpenNoFallback:         return "circuit_open_no_fallback"
        case .timeout:                       return "timeout"
        case .providerNotRegistered:         return "provider_not_registered"
        case .providerInitializationFailed:  return "provider_initialization_failed"
        case .providerUnavailable:           return "provider_unavailable"
        case .providerShowFailed:            return "provider_show_failed"
        case .waterfallExhausted:            return "waterfall_exhausted"
        case .invalidState:                  return "invalid_state"
        case .cancelled:                     return "cancelled"
        case .unknown:                       return "unknown"
        }
    }
}
