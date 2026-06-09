//
//  DebugDataCollector.swift
//  LoomitOfferwallDebug
//
//  Collector thread-safe de eventos + snapshots de estado del SDK para
//  inspección runtime. Paridad con Android `DebugDataCollector`.
//
//  Modo de uso:
//
//  ```swift
//  let collector = DebugDataCollector()
//  await collector.attach(bridge: OfferwallSdk.shared.debugBridge())
//  let snapshot = await collector.snapshot()
//  let events = await collector.recentEvents()
//  ```
//
//  No tiene UI — sólo provee la data. UI Compose-equivalente (SwiftUI) es
//  responsabilidad del consumidor (sample app o publisher tooling).
//

import Foundation
import LoomitOfferwallCore

/// Nivel de severidad de un `DebugEvent` (no confundir con `LogLevel` del logger).
public enum DebugEventLevel: String, Sendable {
    case debug
    case info
    case warning
    case error
}

/// Evento capturado por la Debug Suite.
public struct DebugEvent: Sendable, Equatable {
    public let id: Int64
    public let timestamp: Date
    public let type: String
    public let provider: String
    public let payload: [String: String]
    public let level: DebugEventLevel

    public init(
        id: Int64,
        timestamp: Date,
        type: String,
        provider: String,
        payload: [String: String] = [:],
        level: DebugEventLevel = .info
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.provider = provider
        self.payload = payload
        self.level = level
    }
}

/// Información de un provider en el plan (para pestaña Providers).
/// Paridad con Android `DebugDataCollector.ProviderPlanInfo`.
public struct ProviderPlanInfo: Sendable, Equatable {
    public let provider: String
    public let priority: Int
    public let isActive: Bool
    public let isInitialized: Bool
    public let hasContent: Bool

    public init(
        provider: String,
        priority: Int,
        isActive: Bool,
        isInitialized: Bool,
        hasContent: Bool
    ) {
        self.provider = provider
        self.priority = priority
        self.isActive = isActive
        self.isInitialized = isInitialized
        self.hasContent = hasContent
    }
}

/// Snapshot completo del estado del SDK en un instante.
public struct DebugSnapshot: Sendable, Equatable {
    public let xifa: String
    public let deviceFingerprint: String
    public let bundleIdentifier: String?
    public let lastConfigSegment: String?
    public let lastConfigSource: String?
    public let cachedConfig: CachedConfigInfo?
    public let resilienceState: ResilienceState
    public let pendingEventQueueSize: Int
    public let registeredAdapterKeys: [String]
    public let hasAdvertisingId: Bool
    public let advertisingId: String?
    public let publisherUserId: String?

    public init(
        xifa: String,
        deviceFingerprint: String,
        bundleIdentifier: String?,
        lastConfigSegment: String?,
        lastConfigSource: String?,
        cachedConfig: CachedConfigInfo?,
        resilienceState: ResilienceState,
        pendingEventQueueSize: Int,
        registeredAdapterKeys: [String],
        hasAdvertisingId: Bool = false,
        advertisingId: String? = nil,
        publisherUserId: String? = nil
    ) {
        self.xifa = xifa
        self.deviceFingerprint = deviceFingerprint
        self.bundleIdentifier = bundleIdentifier
        self.lastConfigSegment = lastConfigSegment
        self.lastConfigSource = lastConfigSource
        self.cachedConfig = cachedConfig
        self.resilienceState = resilienceState
        self.pendingEventQueueSize = pendingEventQueueSize
        self.registeredAdapterKeys = registeredAdapterKeys
        self.hasAdvertisingId = hasAdvertisingId
        self.advertisingId = advertisingId
        self.publisherUserId = publisherUserId
    }
}

/// Collector actor - thread-safe. Mantiene un ring buffer de eventos
/// (max `eventBufferSize`, default 100) y permite tomar snapshots vía
/// el `DebugBridge` adjunto.
public actor DebugDataCollector: DebugDataCollectorBridge {

    public static let defaultEventBufferSize = 100

    // MARK: - Configuration
    private let eventBufferSize: Int
    private var bridge: DebugBridge?
    private var idGen: Int64 = 0
    private var events: [DebugEvent] = []
    
    // MARK: - JSON Storage (paridad con Android)
    private var lastConfigJson: String? = nil
    private var lastRequestJson: String? = nil

    // MARK: - Provider Plan (para pestaña Providers)
    private var lastProviderPlan: [ProviderPlanInfo] = []

    // MARK: - Custom Properties (paridad con Android)
    private var customPropertiesState: [String: DebugCustomProperty] = [:]

    private let clock: @Sendable () -> Date

    public init(
        eventBufferSize: Int = DebugDataCollector.defaultEventBufferSize,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.eventBufferSize = eventBufferSize
        self.clock = clock

        // Listen for provider plan changes from OfferwallSdk
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("com.loomit.offerwall.providerPlanChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { [weak self] in
                await self?.handleProviderPlanChanged(notification)
            }
        }
    }

    private func handleProviderPlanChanged(_ notification: Notification) {
        print("[DebugDataCollector] handleProviderPlanChanged called")
        guard let userInfo = notification.userInfo else {
            print("[DebugDataCollector] No userInfo in notification")
            return
        }
        guard let planData = userInfo["plan"] as? [[String: Any]] else {
            print("[DebugDataCollector] No 'plan' in userInfo or wrong type")
            return
        }

        print("[DebugDataCollector] Received \(planData.count) providers in notification")
        lastProviderPlan = planData.compactMap { dict in
            guard let provider = dict["provider"] as? String,
                  let priority = dict["priority"] as? Int,
                  let isActive = dict["isActive"] as? Bool,
                  let isInitialized = dict["isInitialized"] as? Bool,
                  let hasContent = dict["hasContent"] as? Bool else {
                print("[DebugDataCollector] Failed to parse provider dict: \(dict)")
                return nil
            }
            return ProviderPlanInfo(
                provider: provider,
                priority: priority,
                isActive: isActive,
                isInitialized: isInitialized,
                hasContent: hasContent
            )
        }

        print("[DebugDataCollector] Parsed \(lastProviderPlan.count) providers, notifying observers")
        notifyObservers()

        // Notify UI via NotificationCenter
        NotificationCenter.default.post(
            name: NSNotification.Name("com.loomit.debug.providerPlanUpdated"),
            object: nil
        )
    }

    /// Adjunta el bridge a observar. Reemplaza el anterior si había.
    public func attach(bridge: DebugBridge) {
        self.bridge = bridge
    }

    /// Toma un snapshot completo. Retorna `nil` si no hay bridge adjunto.
    public func snapshot() async -> DebugSnapshot? {
        guard let bridge = bridge else { return nil }

        async let xifa = bridge.xifa()
        async let fp = bridge.deviceFingerprint()
        async let bid = bridge.bundleIdentifier()
        async let cfg = bridge.lastConfig()
        async let cfgSrc = bridge.lastConfigSource()
        async let cached = bridge.cachedConfigInfo()
        async let resState = bridge.resilienceState()
        async let qSize = bridge.pendingEventQueueSize()
        async let keys = bridge.registeredAdapterKeys()
        async let hasAdId = bridge.hasAdvertisingId()
        async let adId = bridge.advertisingId()
        async let pubUserId = bridge.publisherUserId()

        return await DebugSnapshot(
            xifa: xifa,
            deviceFingerprint: fp,
            bundleIdentifier: bid,
            lastConfigSegment: cfg?.segment,
            lastConfigSource: cfgSrc?.rawValue,
            cachedConfig: cached,
            resilienceState: resState,
            pendingEventQueueSize: qSize,
            registeredAdapterKeys: keys,
            hasAdvertisingId: hasAdId,
            advertisingId: adId,
            publisherUserId: pubUserId
        )
    }

    // MARK: - DebugDataCollectorBridge Protocol
    
    /// Implementación del protocolo DebugDataCollectorBridge (paridad con Android).
    nonisolated public func recordEvent(type: String, provider: String, payload: [String: String]) {
        Task {
            await recordEvent(type: type, provider: provider, payload: payload, level: .info)
        }
    }

    // MARK: - Event ring buffer

    /// Registra manualmente un evento de debug (ej: invocado desde un
    /// `OfferwallTrackingListener` adapter).
    public func recordEvent(
        type: String,
        provider: String = "-",
        payload: [String: String] = [:],
        level: DebugEventLevel = .info
    ) {
        idGen &+= 1
        let evt = DebugEvent(
            id: idGen,
            timestamp: clock(),
            type: type,
            provider: provider,
            payload: payload,
            level: level
        )
        events.append(evt)
        if events.count > eventBufferSize {
            events.removeFirst(events.count - eventBufferSize)
        }
    }

    public func recentEvents(limit: Int? = nil) -> [DebugEvent] {
        if let limit = limit, limit < events.count {
            return Array(events.suffix(limit))
        }
        return events
    }

    public func eventCount() -> Int {
        events.count
    }

    public func clearEvents() {
        events.removeAll()
    }

    // MARK: - JSON Storage (paridad con Android)

    /// Record config response JSON - llamado por el bridge cuando el SDK recibe respuesta
    nonisolated public func recordConfigResponse(json: String) {
        Task {
            await _recordConfigResponse(json: json)
        }
    }

    private func _recordConfigResponse(json: String) {
        print("[DebugDataCollector] Received config response JSON: \(json.prefix(200))...")
        lastConfigJson = json
        // También registrar evento para consistencia con Android
        recordEvent(type: "config_received", payload: ["size": String(json.count)])
    }

    /// Record config request JSON - llamado por el bridge cuando el SDK envía request
    nonisolated public func recordConfigRequest(json: String) {
        Task {
            await _recordConfigRequest(json: json)
        }
    }

    private func _recordConfigRequest(json: String) {
        print("[DebugDataCollector] Received config request JSON: \(json.prefix(200))...")
        lastRequestJson = json
    }

    // MARK: - Provider Plan (paridad con Android)

    /// Actualiza el plan de providers desde el SDK.
    /// Llamado por OfferwallSdk cuando cambia el provider plan.
    public func updateProviderPlan(_ plan: [ProviderPlanInfo]) {
        lastProviderPlan = plan
        notifyObservers()
        print("[DebugDataCollector] Updated provider plan: \(plan.count) providers")
    }

    private func notifyObservers() {
        NotificationCenter.default.post(name: .debugDataUpdated, object: nil)
    }

    /// Obtiene el plan actual de providers.
    public func getProviderPlan() -> [ProviderPlanInfo] {
        return lastProviderPlan
    }

    // MARK: - Identifiers (paridad con Android sendDebugIdentifiers)

    /// Recibe los identificadores actualizados desde el SDK (push vía DebugDataCollectorBridge).
    /// Paridad con Android `sendDebugIdentifiers()` (OfferwallSdk.kt:4054).
    nonisolated public func updateIdentifiers(xifa: String?, publisherUserId: String?, hasAdvertisingId: Bool) {
        // Los identificadores se exponen on-demand vía snapshot() usando el bridge.
        // Este método notifica a los observers para que refresquen el snapshot.
        Task { await _notifyIdentifiersUpdated() }
    }

    private func _notifyIdentifiersUpdated() {
        notifyObservers()
    }

    // MARK: - Custom Properties API (paridad con Android)

    /// Recibe el estado actualizado desde el SDK (push vía DebugDataCollectorBridge).
    /// Paridad con Android `updateCustomProperties(Map<String, DebugCustomProperty>)`.
    nonisolated public func updateCustomProperties(_ state: [String: DebugCustomProperty]) {
        Task { await _updateCustomProperties(state) }
    }

    private func _updateCustomProperties(_ state: [String: DebugCustomProperty]) {
        customPropertiesState = state
        notifyObservers()
    }

    /// Retorna el estado actual de custom properties para el debug panel.
    /// Paridad con Android `bridge.getCustomPropertyDebugState()`.
    public func getCustomPropertyDebugState() -> [String: DebugCustomProperty] {
        customPropertiesState
    }

    /// Override / añade una propiedad extra desde el debug panel.
    /// Escribe directo al SDK (write-through). Paridad con Android `bridge.setCustomPropertyOverride`.
    public func setCustomPropertyOverride(_ key: String, value: String?) async {
        await OfferwallSdk.shared.setCustomPropertyOverride(key, value: value)
    }

    /// Inhibe o restaura una propiedad desde el debug panel.
    /// Paridad con Android `bridge.setCustomPropertyInhibited`.
    public func setCustomPropertyInhibited(_ key: String, inhibited: Bool) async {
        await OfferwallSdk.shared.setCustomPropertyInhibited(key, inhibited: inhibited)
    }

    /// Limpia todos los overrides/inhibits/extras de debug.
    /// Paridad con Android `bridge.clearCustomPropertyOverrides()`.
    public func clearCustomPropertyOverrides() async {
        await OfferwallSdk.shared.clearCustomPropertyOverrides()
    }

    // MARK: - Experiments (paridad con Android)

    /// Obtiene las asignaciones de experimentos del SDK (paridad con Android)
    public func getExperimentAssignments() async -> [OfferwallSdk.ExperimentAssignment] {
        return await OfferwallSdk.shared.getLastExperimentAssignments()
    }

    /// Obtiene los overrides de experimentos del SDK (paridad con Android)
    public func getExperimentOverrides() async -> [String: String] {
        return await OfferwallSdk.shared.getExperimentOverrides()
    }

    /// Setea un override manual para un experimento (paridad con Android)
    public func setExperimentOverride(experimentName: String, group: String?) async {
        await OfferwallSdk.shared.setExperimentOverride(experimentName: experimentName, group: group)
        print("[DebugDataCollector] Set experiment override: \(experimentName) -> \(group ?? "nil")")
    }
    
    /// Obtener último config response JSON
    public func getLastConfigJson() -> String? {
        return lastConfigJson
    }
    
    /// Obtener último config request JSON
    public func getLastRequestJson() -> String? {
        return lastRequestJson
    }

    // MARK: - Pending events (delegado al bridge)

    public func pendingEvents() async -> [PendingEventInfo] {
        guard let bridge = bridge else { return [] }
        return await bridge.pendingEvents()
    }
}

// MARK: - Notification Names

public extension Notification.Name {
    static let debugDataUpdated = Notification.Name("com.loomit.debug.dataUpdated")
}
