//
//  DebugBridge.swift
//  LoomitOfferwallCore
//
//  Bridge read-only que expone estado interno del SDK para herramientas de
//  debug/diagnóstico (ej: `LoomitOfferwallDebug` package).
//
//  Diseño:
//  - Es un protocolo `async` para no exponer al actor del SDK directamente.
//  - Sólo lectura: la Debug Suite no muta estado del SDK.
//  - Paridad con Android `DebugBridge` + `DebugDataCollector` API surface.
//

import Foundation

/// Snapshot de la config cacheada.
public struct CachedConfigInfo: Sendable, Equatable {
    public let timestamp: Date
    public let source: String       // "NETWORK" | "CACHE_FRESH" | "CACHE_STALE"
    public let age: TimeInterval
    public let json: String         // JSON serializado de la ConfigResponse

    public init(timestamp: Date, source: String, age: TimeInterval, json: String = "") {
        self.timestamp = timestamp
        self.source = source
        self.age = age
        self.json = json
    }
}

/// Snapshot de un evento pendiente en la cola persistente.
public struct PendingEventInfo: Sendable, Equatable {
    public let id: Int64
    public let type: String
    public let provider: String
    public let timestamp: Int64
    public let retryCount: Int
    public let priority: String     // "CRITICAL" | "HIGH" | "NORMAL"
    public let payload: String      // JSON del campo `data` del evento

    public init(
        id: Int64,
        type: String,
        provider: String,
        timestamp: Int64,
        retryCount: Int,
        priority: String,
        payload: String = "{}"
    ) {
        self.id = id
        self.type = type
        self.provider = provider
        self.timestamp = timestamp
        self.retryCount = retryCount
        self.priority = priority
        self.payload = payload
    }
}

/// Estado de una custom property en el debug panel.
/// Paridad con Android `DebugCustomProperty`.
public struct DebugCustomProperty: Sendable, Equatable {
    public let key: String
    public let originalValue: String   // valor seteado por el publisher (vacío si es extra o pending)
    public let currentValue: String    // valor efectivo (tras override/inhibit)
    public let isInhibited: Bool       // true → se elimina del request
    public let isOverridden: Bool      // true → valor sustituido por debug panel
    /// true → regla guardada en disco pero el publisher aún no cargó esta propiedad en la sesión actual.
    /// El override/inhibit SE APLICARÁ igual en fetchConfig cuando el publisher la cargue.
    public let isPending: Bool

    public init(
        key: String,
        originalValue: String,
        currentValue: String,
        isInhibited: Bool,
        isOverridden: Bool,
        isPending: Bool = false
    ) {
        self.key = key
        self.originalValue = originalValue
        self.currentValue = currentValue
        self.isInhibited = isInhibited
        self.isOverridden = isOverridden
        self.isPending = isPending
    }
}

/// Bridge de debug. **Read-only.** No expone setters.
public protocol DebugBridge: Sendable {

    // MARK: - Identifiers
    func xifa() async -> String
    func deviceFingerprint() async -> String
    func bundleIdentifier() async -> String?
    func hasAdvertisingId() async -> Bool
    func advertisingId() async -> String?
    func publisherUserId() async -> String?

    // MARK: - Last config
    func lastConfig() async -> ConfigResponse?
    func lastConfigSource() async -> ConfigSource?

    // MARK: - Cache & resilience
    func cachedConfigInfo() async -> CachedConfigInfo?
    func resilienceState() async -> ResilienceState

    // MARK: - Events pipeline
    func pendingEvents() async -> [PendingEventInfo]
    func pendingEventQueueSize() async -> Int

    // MARK: - Adapters
    func registeredAdapterKeys() async -> [String]

    // MARK: - Custom properties
    func customPropertyDebugState() async -> [String: DebugCustomProperty]

    // MARK: - Environment (debug only, requires debuggingEnabled)
    func currentEnvironment() async -> BackendEnvironment
    func setEnvironmentForDebug(_ environment: BackendEnvironment) async
    /// Aplica el environment persistido en UserDefaults al arrancar el DS (si debuggingEnabled).
    func applyPersistedEnvironmentIfNeeded() async
}

/// Protocolo para que el SDK pueda enviar JSON al DebugDataCollector sin dependencia circular.
/// Implementado por DebugDataCollector en LoomitOfferwallDebug.
/// Paridad con Android reflection: en Android usan reflection, en Swift usamos protocolo.
public protocol DebugDataCollectorBridge: Sendable {
    nonisolated func recordConfigRequest(json: String)
    nonisolated func recordConfigResponse(json: String)
    nonisolated func updateCustomProperties(_ state: [String: DebugCustomProperty])
    /// Empuja los identificadores actuales al collector (paridad con Android sendDebugIdentifiers()).
    nonisolated func updateIdentifiers(xifa: String?, publisherUserId: String?, hasAdvertisingId: Bool)
    /// Registra eventos de tracking (paridad con Android sendDebugEvent).
    nonisolated func recordEvent(type: String, provider: String, payload: [String: String])
}
