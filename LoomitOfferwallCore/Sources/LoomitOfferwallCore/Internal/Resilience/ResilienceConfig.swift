//
//  ResilienceConfig.swift
//  LoomitOfferwallCore
//
//  Políticas y estado runtime de resiliencia (cache + circuit breaker).
//  Paridad con Android `ConfigFetchPolicy` + `SdkOperationMode` + `ResilienceState`.
//

import Foundation
import LoomitOfferwallAdapterAPI

/// Política para fetch de configuración.
public struct ConfigFetchPolicy: Sendable, Equatable {

    /// Si `true`, al fallar el request se intenta cache fresh primero.
    public let useCacheIfFailed: Bool

    /// Max age (segundos) para considerar el cache "fresh".
    public let cacheMaxAge: TimeInterval

    /// Si `true`, en último recurso se acepta cache stale (mayor a `cacheMaxAge`).
    public let allowStaleCache: Bool

    /// Max age (segundos) hasta el cual el cache stale es aceptable.
    public let staleMaxAge: TimeInterval

    public init(
        useCacheIfFailed: Bool = true,
        cacheMaxAge: TimeInterval = ConfigSnapshot.freshThreshold,
        allowStaleCache: Bool = true,
        staleMaxAge: TimeInterval = ConfigSnapshot.staleThreshold
    ) {
        self.useCacheIfFailed = useCacheIfFailed
        self.cacheMaxAge = cacheMaxAge
        self.allowStaleCache = allowStaleCache
        self.staleMaxAge = staleMaxAge
    }

    public static let `default` = ConfigFetchPolicy()
}

/// Modo de operación actual del SDK.
public enum SdkOperationMode: String, Sendable {
    /// Funcionalidad completa, red disponible.
    case normal = "NORMAL"
    /// Usando cache stale, funcionalidad limitada.
    case degraded = "DEGRADED"
    /// Usando emergency snapshot, mínima funcionalidad.
    case emergency = "EMERGENCY"
    /// Sin red, sólo eventos cacheados.
    case offline = "OFFLINE"
}

/// Estado runtime de resiliencia del SDK (lectura).
public struct ResilienceState: Sendable, Equatable {
    public let operationMode: SdkOperationMode
    public let configSource: ConfigSource?
    public let cacheAge: TimeInterval?
    public let backendCircuitState: CircuitState

    public init(
        operationMode: SdkOperationMode,
        configSource: ConfigSource?,
        cacheAge: TimeInterval?,
        backendCircuitState: CircuitState
    ) {
        self.operationMode = operationMode
        self.configSource = configSource
        self.cacheAge = cacheAge
        self.backendCircuitState = backendCircuitState
    }
}

/// Resultado detallado de un fetch resiliente.
public enum ConfigFetchResult: Sendable {
    case success(ConfigResponse, source: ConfigSource)
    case failure(error: OfferwallError, fallbackAvailable: Bool)
}
