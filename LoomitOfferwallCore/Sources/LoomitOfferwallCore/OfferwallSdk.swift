//
//  OfferwallSdk.swift
//  LoomitOfferwallCore
//
//  Entry point del SDK. Singleton actor.
//
//  Responsabilidades (incrementales por etapa del plan):
//  - ETAPA 1: API pública + state machine + listener registration.
//  - ETAPA 2: identifiers (XIFA, fingerprint).
//  - ETAPA 3: adapter registry.
//  - ETAPA 4: fetchConfig contra backend real (con retry).
//  - ETAPA 5+: events, logging, providers, show/close.
//
//  Invariantes (ARCHITECTURE.md §2):
//  - UX callbacks vía listener global (single-path) — `setListener(...)`.
//  - userId cascade: currentUserId ?? publisherUserId ?? xifa.
//  - Sin install_id; xifa es el único install identifier.
//  - Adapter discovery EXPLÍCITO (registerAdapter); no service-loader.
//

import Foundation
import LoomitOfferwallAdapterAPI
#if canImport(UIKit)
import UIKit
#endif

/// Entry point principal del SDK. Singleton actor.
///
/// **Uso típico** desde el publisher (AppDelegate/SceneDelegate):
///
/// ```swift
/// Task {
///     await OfferwallSdk.shared.setLoomitApiKey("YOUR_API_KEY")
///     await OfferwallSdk.shared.setListener(self)
///     await OfferwallSdk.shared.registerAdapter(MyChipsAdapter())
///     do {
///         let config = try await OfferwallSdk.shared.fetchConfig()
///         print("Resolved waterfall:", config.offerwall?.defaultWaterfall ?? [])
///     } catch {
///         print("fetchConfig failed:", error)
///     }
/// }
/// ```
public actor OfferwallSdk {

    // MARK: - Singleton

    /// Instancia única del SDK.
    public static let shared = OfferwallSdk()

    // MARK: - State

    private var _legacyState: LifecycleState = .uninitialized
    
    /// State machine with validated transitions. Parity with Android `SdkStateMachine`.
    private let stateMachine = SdkStateMachine()
    
    /// Legacy state property for backward compatibility.
    /// TODO: Migrate all usages to stateMachine and remove this.
    private(set) var state: LifecycleState {
        get { _legacyState }
        set { _legacyState = newValue }
    }

    /// Última config exitosamente fetched. `nil` hasta el primer `fetchConfig`.
    private(set) var lastConfig: ConfigResponse?

    /// Fuente de la última config (network / cacheFresh / cacheStale / emergency).
    /// `nil` si nunca se fetchó.
    private(set) var lastConfigSource: ConfigSource?

    /// Configuración del publisher (API key + user IDs + privacy + custom).
    private var publisherConfig: PublisherConfig?

    /// Environment del backend (default: `.live`).
    private var environment: BackendEnvironment = .live

    // MARK: - Subsystems

    private let identifiers: IdentifierStoring
    private let registry: AdapterRegistry
    private let dispatcher: ListenerDispatcher
    private let userDefaults: UserDefaultsSafe

    /// Backend client. Se construye al setear apiKey y se reemplaza si cambia
    /// apiKey o environment.
    private var backendClient: BackendClient?

    /// Permite a tests inyectar un client mockeado.
    private var injectedBackendClient: BackendClient?

    /// Política de retry para fetchConfig. Settable por tests / debug builds.
    private var retryPolicy: RetryPolicy = .default

    /// Cache persistente de config (resiliencia 4-bis).
    private var configCache: ConfigCache = UserDefaultsConfigCache()

    /// Política de fetch (cache fallback). Settable por tests.
    private var fetchPolicy: ConfigFetchPolicy = .default

    /// Config del circuit breaker. Settable por tests.
    private var circuitConfig: CircuitBreakerConfig = .default

    /// Resilient client cacheado (envuelve HTTP + retry + cache + breaker).
    private var resilientClient: ResilientBackendClient?

    /// Política del event pipeline. Settable por tests.
    private var eventPushPolicy: EventPushPolicy = .default

    /// Event pusher resiliente (cacheado). Se construye lazy al primer trackEvent.
    private var eventPusher: ResilientEventPusher?

    /// Pusher inyectable por tests. Si está seteado, se usa en vez de construir uno HTTP.
    private var injectedEventPusherDelegate: OfferwallEventPusher?

    /// Cola persistente de eventos (cacheada).
    private var eventQueue: EventQueue?

    /// Cola inyectada por tests; si está seteada, se usa en vez de `FileEventQueue.defaultLocation()`.
    private var injectedEventQueue: EventQueue?

    /// Lifecycle ID que se incrementa en cada init/show.
    private var lifecycleId: Int = 0

    /// Lifecycle ID atómico (current session). 0 = no lifecycle started yet.
    private var currentLifecycleId: Int = 0

    /// Counter total de lifecycle starts (diagnóstico).
    private var lifecycleStartCount: Int = 0

    /// Lifecycle ID capturado al llamar show(), para asociar callbacks out-of-order.
    private var pendingShowLifecycleId: Int = 0

    /// Index del provider activo en el plan (0 = primario).
    private var currentProviderIndex: Int = 0

    /// Key normalizado del provider activo (ej: "maf").
    private var currentProviderKey: String?

    /// `true` después de startNewLifecycle() y `false` después de endLifecycle().
    /// Indica si hay un ciclo activo que permite llamar show().
    private var lifecycleIdFromAvailability: Bool = false

    /// Ad space activo para la sesión de show actual (scope = single show request).
    private var currentAdSpace: String?

    // MARK: - Provider plan state

    /// Plan de providers priorizado (del último fetchConfig exitoso).
    private var providerPlan: [ProviderPlanEntry] = []

    /// Instancias de providers creados por `initAllFromPlan`.
    private var providerInstances: [OfferwallProvider] = []

    /// Listeners internos por provider (retained para evitar deallocation).
    private var providerListeners: [InternalProviderListener] = []

    /// Estado de inicialización por provider (parallel array con providerPlan).
    private var providerInitialized: [Bool] = []

    /// Estado de disponibilidad de contenido por provider (parallel array con providerPlan).
    private var providerHasContent: [Bool] = []

    /// Tracking de providers que respondieron en el ciclo actual (paridad con Android).
    private var providerAvailabilityKnown: [Bool] = []

    /// Deadline para el barrier de disponibilidad (paridad con Android).
    private var availabilityBarrierDeadline: TimeInterval = 0

    /// Último estado conocido de disponibilidad (paridad con Android).
    private var lastKnownAvailability: Bool = false

    /// Task para el debounce de availability snapshot (paridad con Android).
    private var availabilityEmitTask: Task<Void, Never>?

    /// `true` una vez que `fetchConfig` completó exitosamente.
    private var configFetchCompleted: Bool = false

    /// Guard contra init concurrentes.
    private var isInitializingProviders: Bool = false

    /// `true` una vez que `initAllFromPlan` completó con al menos un provider.
    private var providersInitialized: Bool = false

    /// Guard contra double-show (§10.11 anti-pattern prevention, paridad con Android).
    private var isShowingOfferwall: Bool = false

    /// Guard contra callbacks duplicados del mismo provider (defensa en profundidad).
    /// Un adapter con bugs de NotificationCenter o delegate puede emitir didShow/didClose
    /// múltiples veces; estos flags previenen eventos duplicados.
    private var hasProviderReportedShow = false
    private var hasProviderReportedClose = false

    /// Guard contra snapshots duplicados: trackea el hash del último estado emitido
    /// para este lifecycle. Si el estado no cambió, no se emite snapshot nuevo.
    private var lastSnapshotLifecycleId: Int = 0
    private var lastSnapshotAvailabilityHash: Int = 0

    // MARK: - Availability Barrier Constants (paridad con Android)

    /// Debounce delay antes de emitir availability snapshot.
    private static let AVAILABILITY_DEBOUNCE_MS: TimeInterval = 1.5

    /// Tiempo máximo de espera por providers lentos.
    /// 8s para absorber providers lentos en device real (ej: Tapjoy tarda ~5s en contentIsReady).
    private static let CYCLE_MAX_WAIT_MS: TimeInterval = 8.0

    /// Production logger (se construye lazy luego del primer fetchConfig).
    private var productionLogger: ProductionLogger?

    /// Uploader del logger (cacheado para reutilizar entre fetchConfigs).
    private var logUploader: HTTPLogUploader?
    
    /// Lifecycle diagnostic logger. Parity with Android `LifecycleDiagnosticLogger`.
    private var lifecycleDiagnosticLogger: LifecycleDiagnosticLogger?
    
    /// Event tracking logger. Parity with Android `EventTrackingLogger`.
    private var eventTrackingLogger: EventTrackingLogger?
    
    /// Pusher health logger. Parity with Android `PusherHealthLogger`.
    private var pusherHealthLogger: PusherHealthLogger?
    
    /// Event manager with batching. Parity with Android `OfferwallEventManager`.
    private var eventManager: OfferwallEventManager?

    /// `true` si el debug panel está habilitado (app-initiated o backend-forzado).
    private var debuggingEnabled: Bool = false

    /// DebugDataCollector instance (solo en debug builds, inyectado por DebugPanel)
    /// Usamos el protocolo DebugDataCollectorBridge para evitar dependencia circular (paridad con Android reflection).
    private var debugDataCollector: DebugDataCollectorBridge? = nil

    /// Inyectable por tests.
    private var injectedLogUploader: LogUploader?

    // MARK: - Custom properties debug overlay (paridad con Android)

    /// Regla de debug para una custom property.
    /// Paridad con Android `CustomRule`.
    struct CustomRule: Sendable {
        let mode: String   // "OVERRIDE" | "DROP"
        let value: String? // nil para DROP
    }

    /// Propiedades del publisher seteadas via setCustomProperty / setCustomProperties.
    /// Dict standalone, paridad con Android `private val customProperties: MutableMap<String, String>`.
    private var customProperties: [String: String] = [:]
    /// Overrides/inhibits seteados por el debug panel. No afectan a `customProperties`.
    private var customPropertyRules: [String: CustomRule] = [:]
    /// Propiedades extra añadidas por el debug panel (no presentes en customProperties).
    private var customPropertyExtras: [String: String] = [:]
    /// Evita recargar de UserDefaults en cada llamada.
    private var customPropertyRulesLoaded: Bool = false

    // MARK: - Experiments state (paridad con Android)

    /// Últimas asignaciones de experimentos del backend (paridad con Android)
    private var lastExperimentAssignments: [ExperimentAssignment] = []

    /// Overrides de experimentos persistidos (paridad con Android)
    private var _experimentOverrides: [String: String]?
    private var experimentOverrides: [String: String] {
        get {
            if let cached = _experimentOverrides {
                return cached
            }
            let (overrides, _) = Self.loadExperimentOverridesStatic()
            _experimentOverrides = overrides
            return overrides
        }
        set {
            _experimentOverrides = newValue
        }
    }

    /// IDs de experimentos para overrides (paridad con Android)
    private var _experimentOverrideIds: [String: String]?
    private var experimentOverrideIds: [String: String] {
        get {
            if let cached = _experimentOverrideIds {
                return cached
            }
            let (_, ids) = Self.loadExperimentOverridesStatic()
            _experimentOverrideIds = ids
            return ids
        }
        set {
            _experimentOverrideIds = newValue
        }
    }

    // MARK: - Init

    /// Init principal. `private` para forzar uso de `shared`.
    /// Acepta dependencias inyectables sólo desde tests via `__forTesting`.
    private init(
        identifiers: IdentifierStoring = IdentifierStore(),
        registry: AdapterRegistry = AdapterRegistry()
    ) {
        self.identifiers = identifiers
        self.registry = registry
        self.dispatcher = ListenerDispatcher()
        self.userDefaults = UserDefaultsSafe.shared
        // Load experiment overrides lazily on first access
        // Load DS environment override lazily on first access
    }

    /// Init para tests. **No llamar desde código de producción.**
    /// Internal porque `AdapterRegistry` es internal — accesible desde tests
    /// con `@testable import`.
    init(
        __forTestingIdentifiers identifiers: IdentifierStoring,
        registry: AdapterRegistry = AdapterRegistry(),
        backendClient: BackendClient? = nil,
        retryPolicy: RetryPolicy = .default
    ) {
        self.identifiers = identifiers
        self.registry = registry
        self.dispatcher = ListenerDispatcher()
        self.userDefaults = UserDefaultsSafe.shared
        self.injectedBackendClient = backendClient
        self.retryPolicy = retryPolicy
    }

    // MARK: - Public API: Configuration

    /// Setea la API key de Loomit (para headers `x-api-key`). Requerido antes de `fetchConfig`.
    public func setLoomitApiKey(_ apiKey: String) {
        let current = publisherConfig ?? PublisherConfig.empty(apiKey: apiKey)
        publisherConfig = PublisherConfig(
            loomitApiKey: apiKey,
            clientId: current.clientId,
            appId: current.appId,
            publisherUserId: current.publisherUserId,
            currentUserId: current.currentUserId,
            country: current.country,
            appVersion: current.appVersion,
            customProperties: current.customProperties,
            abTestOverride: current.abTestOverride,
            advertisingId: current.advertisingId,
            hasAdvertisingId: current.hasAdvertisingId,
            privacy: current.privacy
        )

        backendClient = nil

        if state == .uninitialized {
            state = .configured
        }
    }

    /// Setea el Client ID (para el campo `client_id` del body del request).
    /// Requerido antes de `fetchConfig`.
    public func setClientId(_ clientId: String) {
        guard var config = publisherConfig else {
            assertionFailure("setLoomitApiKey must be called before setClientId")
            return
        }
        config = PublisherConfig(
            loomitApiKey: config.loomitApiKey,
            clientId: clientId,
            appId: config.appId,
            publisherUserId: config.publisherUserId,
            currentUserId: config.currentUserId,
            country: config.country,
            appVersion: config.appVersion,
            customProperties: config.customProperties,
            abTestOverride: config.abTestOverride,
            advertisingId: config.advertisingId,
            hasAdvertisingId: config.hasAdvertisingId,
            privacy: config.privacy
        )
        publisherConfig = config
    }

    /// Cambia el environment del backend (live/test/custom).
    /// Si el debug panel tiene un override persistido y debugging está activo,
    /// las llamadas del publisher son ignoradas (el DS tiene prioridad).
    public func setEnvironment(_ environment: BackendEnvironment) {
        if let raw = userDefaults.string(forKey: OfferwallSdk.udKeyDebugEnvironment),
           !raw.isEmpty {
            print("[LoomitOW] setEnvironment(\(environment.baseURL.host ?? "?")) ignored — DS override active (\(raw))")
            return
        }
        print("[LoomitOW] setEnvironment → \(environment.baseURL.absoluteString)")
        self.environment = environment
        backendClient = nil
        resilientClient = nil
    }

    /// Setea el listener global de UX. Reemplaza el anterior.
    public func setListener(_ listener: OfferwallListener?) {
        dispatcher.setUXListener(listener)
    }

    /// Setea el listener opcional de tracking.
    public func setTrackingListener(_ listener: OfferwallTrackingListener?) {
        dispatcher.setTrackingListener(listener)
    }

    /// Setea el `publisherUserId` (opcional). Persiste hasta que se cambie.
    /// Paridad con Android: trim + nil si blank.
    public func setPublisherUserId(_ userId: String?) {
        guard var config = publisherConfig else {
            assertionFailure("setLoomitApiKey must be called before setPublisherUserId")
            return
        }
        let sanitized: String? = {
            let trimmed = userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }()
        config = PublisherConfig(
            loomitApiKey: config.loomitApiKey,
            clientId: config.clientId,
            appId: config.appId,
            publisherUserId: sanitized,
            currentUserId: config.currentUserId,
            country: config.country,
            appVersion: config.appVersion,
            customProperties: config.customProperties,
            abTestOverride: config.abTestOverride,
            advertisingId: config.advertisingId,
            hasAdvertisingId: config.hasAdvertisingId,
            privacy: config.privacy
        )
        publisherConfig = config
        sendDebugIdentifiers()
    }

    /// Limpia el `publisherUserId`. Paridad con Android `clearUserId()`.
    public func clearPublisherUserId() {
        setPublisherUserId(nil)
    }

    /// Retorna el `publisherUserId` seteado, o `nil` si no está seteado.
    /// Paridad con Android `getPublisherUserId()`.
    public func getPublisherUserId() -> String? {
        publisherConfig?.publisherUserId
    }

    /// Setea el `currentUserId` (mayor prioridad en cascade).
    public func setCurrentUserId(_ userId: String?) {
        guard var config = publisherConfig else {
            assertionFailure("setLoomitApiKey must be called before setCurrentUserId")
            return
        }
        config = PublisherConfig(
            loomitApiKey: config.loomitApiKey,
            clientId: config.clientId,
            appId: config.appId,
            publisherUserId: config.publisherUserId,
            currentUserId: userId,
            country: config.country,
            appVersion: config.appVersion,
            customProperties: config.customProperties,
            abTestOverride: config.abTestOverride,
            advertisingId: config.advertisingId,
            hasAdvertisingId: config.hasAdvertisingId,
            privacy: config.privacy
        )
        publisherConfig = config
    }

    /// Setea el `appId` que el backend usará para resolver config (opcional).
    public func setAppId(_ appId: String?) {
        guard var config = publisherConfig else { return }
        config = PublisherConfig(
            loomitApiKey: config.loomitApiKey,
            clientId: config.clientId,
            appId: appId,
            publisherUserId: config.publisherUserId,
            currentUserId: config.currentUserId,
            country: config.country,
            appVersion: config.appVersion,
            customProperties: config.customProperties,
            abTestOverride: config.abTestOverride,
            advertisingId: config.advertisingId,
            hasAdvertisingId: config.hasAdvertisingId,
            privacy: config.privacy
        )
        publisherConfig = config
    }

    /// Reemplaza las custom properties que se mandan en el request.
    public func setCustomProperties(_ properties: [String: String]) {
        customProperties = properties
        if var config = publisherConfig {
            config = PublisherConfig(
                loomitApiKey: config.loomitApiKey,
                clientId: config.clientId,
                appId: config.appId,
                publisherUserId: config.publisherUserId,
                currentUserId: config.currentUserId,
                country: config.country,
                appVersion: config.appVersion,
                customProperties: properties,
                abTestOverride: config.abTestOverride,
                advertisingId: config.advertisingId,
                hasAdvertisingId: config.hasAdvertisingId,
                privacy: config.privacy
            )
            publisherConfig = config
        }
        sendDebugCustomProperties()
    }

    /// Setea o elimina una propiedad individual. `nil` como value la elimina.
    /// Paridad con Android `setCustomProperty(key, value)`.
    public func setCustomProperty(_ key: String, value: String?) {
        let sanitizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedKey.isEmpty else { return }
        if let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            customProperties[sanitizedKey] = v
        } else {
            customProperties.removeValue(forKey: sanitizedKey)
        }
        sendDebugCustomProperties()
    }

    /// Elimina una propiedad individual.
    /// Paridad con Android `removeCustomProperty(key)`.
    public func removeCustomProperty(_ key: String) {
        setCustomProperty(key, value: nil)
    }

    /// Limpia todas las custom properties del publisher.
    /// Paridad con Android `clearCustomProperties()`.
    public func clearCustomProperties() {
        setCustomProperties([:])
    }

    // MARK: - Custom properties debug overlay (paridad con Android)

    /// Setea un override de debug para la propiedad `key`.
    /// Si `value == nil` o vacío, limpia el override (o extra si era extra).
    /// Paridad con Android `setCustomPropertyOverride(key, value)`.
    public func setCustomPropertyOverride(_ key: String, value: String?) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        loadCustomPropertyRulesIfNeeded()
        if let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            if customProperties[k] == nil {
                customPropertyExtras[k] = v
                customPropertyRules.removeValue(forKey: k)
            } else {
                customPropertyRules[k] = CustomRule(mode: "OVERRIDE", value: v)
            }
        } else {
            if case .some(let r) = customPropertyRules[k], r.mode == "OVERRIDE" {
                customPropertyRules.removeValue(forKey: k)
            }
            customPropertyExtras.removeValue(forKey: k)
        }
        persistCustomPropertyRules()
        sendDebugCustomProperties()
    }

    /// Inhibe (`DROP`) o restaura una propiedad existente del publisher.
    /// Paridad con Android `setCustomPropertyInhibited(key, inhibited)`.
    public func setCustomPropertyInhibited(_ key: String, inhibited: Bool) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        loadCustomPropertyRulesIfNeeded()
        if inhibited {
            customPropertyRules[k] = CustomRule(mode: "DROP", value: nil)
        } else if case .some(let r) = customPropertyRules[k], r.mode == "DROP" {
            customPropertyRules.removeValue(forKey: k)
        }
        persistCustomPropertyRules()
        sendDebugCustomProperties()
    }

    /// Limpia todos los overrides/inhibits/extras de debug.
    /// Paridad con Android `clearCustomPropertyOverrides()`.
    public func clearCustomPropertyOverrides() {
        customPropertyRules.removeAll()
        customPropertyExtras.removeAll()
        persistCustomPropertyRules()
        sendDebugCustomProperties()
    }

    /// Retorna las custom properties efectivas que se enviarán en el próximo request,
    /// aplicando reglas de override/inhibit/extras del debug panel.
    /// Paridad con Android `getCustomPropertiesSnapshot()`.
    func getCustomPropertiesSnapshot() -> [String: String] {
        let detected = customProperties
        guard debuggingEnabled else { return detected }
        loadCustomPropertyRulesIfNeeded()
        var out: [String: String] = [:]
        for (k, v) in detected {
            switch customPropertyRules[k] {
            case nil:
                out[k] = v
            case .some(let r) where r.mode == "KEEP":
                out[k] = v
            case .some(let r) where r.mode == "DROP":
                break
            case .some(let r) where r.mode == "OVERRIDE":
                out[k] = r.value ?? v
            default:
                out[k] = v
            }
        }
        for (k, v) in customPropertyExtras {
            out[k] = v
        }
        return out
    }

    /// Construye el estado completo para el debug panel.
    /// Paridad con Android `buildCustomPropertyDebugState()`.
    func buildCustomPropertyDebugState() -> [String: DebugCustomProperty] {
        let detected = customProperties
        loadCustomPropertyRulesIfNeeded()
        var combinedKeys: [String] = []
        combinedKeys.append(contentsOf: detected.keys)
        for k in customPropertyExtras.keys where !detected.keys.contains(k) {
            combinedKeys.append(k)
        }
        // Reglas guardadas en disco para keys que el publisher aún no cargó en esta sesión.
        // isPending=true: el override/inhibit se aplicará igual en fetchConfig.
        for k in customPropertyRules.keys
            where !detected.keys.contains(k) && !customPropertyExtras.keys.contains(k) {
            combinedKeys.append(k)
        }
        var result: [String: DebugCustomProperty] = [:]
        for key in combinedKeys {
            let original = detected[key] ?? ""
            let rule = customPropertyRules[key]
            let isPending = detected[key] == nil && customPropertyExtras[key] == nil && rule != nil
            let isInhibited = rule?.mode == "DROP"
            let isOverridden = rule?.mode == "OVERRIDE" || (detected[key] == nil && customPropertyExtras[key] != nil)
            let current: String = {
                if isInhibited { return original }
                if rule?.mode == "OVERRIDE" { return rule?.value ?? (original.isEmpty ? customPropertyExtras[key] ?? "" : original) }
                if detected[key] == nil { return customPropertyExtras[key] ?? "" }
                return original
            }()
            result[key] = DebugCustomProperty(
                key: key,
                originalValue: original,
                currentValue: current,
                isInhibited: isInhibited,
                isOverridden: isOverridden,
                isPending: isPending
            )
        }
        return result
    }

    /// Helper para `SdkDebugBridge`.
    func customPropertiesForDebug() -> [String: DebugCustomProperty] {
        buildCustomPropertyDebugState()
    }

    /// Envía el estado actual de custom properties al debug panel (si está conectado).
    /// Paridad con Android `sendDebugCustomProperties()`.
    private func sendDebugCustomProperties() {
        guard debuggingEnabled, let collector = debugDataCollector else { return }
        collector.updateCustomProperties(buildCustomPropertyDebugState())
    }

    // MARK: - Custom property rules persistence (UserDefaults)

    private static let udKeyCustomRules      = "loomit_debug_custom_rules"
    private static let udKeyCustomExtras     = "loomit_debug_custom_extras"
    private static let udKeyDebugEnvironment = "loomit_debug_environment"

    private func loadCustomPropertyRulesIfNeeded() {
        guard !customPropertyRulesLoaded else { return }
        customPropertyRulesLoaded = true
        if let rulesData = userDefaults.data(forKey: OfferwallSdk.udKeyCustomRules),
           let rulesDict = try? JSONDecoder().decode([String: [String: String]].self, from: rulesData) {
            customPropertyRules = rulesDict.compactMapValues { dict in
                guard let mode = dict["mode"], mode == "OVERRIDE" || mode == "DROP" else { return nil }
                return CustomRule(mode: mode, value: dict["value"])
            }
        }
        if let extrasData = userDefaults.data(forKey: OfferwallSdk.udKeyCustomExtras),
           let extrasDict = try? JSONDecoder().decode([String: String].self, from: extrasData) {
            customPropertyExtras = extrasDict
        }
    }

    private func persistCustomPropertyRules() {
        let encoded = customPropertyRules.mapValues { r -> [String: String] in
            var d: [String: String] = ["mode": r.mode]
            if let v = r.value { d["value"] = v }
            return d
        }
        if let data = try? JSONEncoder().encode(encoded) {
            userDefaults.set(data, forKey: OfferwallSdk.udKeyCustomRules)
        }
        if let data = try? JSONEncoder().encode(customPropertyExtras) {
            userDefaults.set(data, forKey: OfferwallSdk.udKeyCustomExtras)
        }
    }

    /// Persiste el environment elegido desde el debug panel.
    func persistDebugEnvironment(_ env: BackendEnvironment) {
        let value: String
        switch env {
        case .live:               value = "live"
        case .test:               value = "test"
        case .custom(let url):    value = "custom:\(url.absoluteString)"
        }
        userDefaults.set(value, forKey: OfferwallSdk.udKeyDebugEnvironment)
    }

    /// Si hay un environment guardado y debuggingEnabled, lo aplica al arrancar el DS.
    /// Paridad con Android `loadAndApplyEnvironmentPreference()`.
    public func loadAndApplyDebugEnvironmentIfNeeded() {
        guard let raw = userDefaults.string(forKey: OfferwallSdk.udKeyDebugEnvironment) else { return }
        let env: BackendEnvironment
        switch raw {
        case "live": env = .live
        case "test": env = .test
        default:
            if raw.hasPrefix("custom:"), let url = URL(string: String(raw.dropFirst("custom:".count))) {
                env = .custom(baseURL: url)
            } else { return }
        }
        guard env != environment else {
            print("[LoomitOW] loadAndApplyDebugEnvironmentIfNeeded: env already \(raw), no-op")
            return
        }
        forceSetEnvironment(env)
    }

    /// Override de A/B test (debug/QA). `nil` para limpiar.
    /// Paridad con Android `setAbTestOverride`.
    public func setAbTestOverride(experimentId: String?, experimentName: String?, group: String?) {
        guard var config = publisherConfig else { return }
        let override: AbTestOverridePayload? = {
            if let e = experimentId, let n = experimentName, let g = group, !e.isEmpty, !n.isEmpty, !g.isEmpty {
                return AbTestOverridePayload(experimentId: e, experimentName: n, group: g)
            }
            return nil
        }()
        config = PublisherConfig(
            loomitApiKey: config.loomitApiKey,
            clientId: config.clientId,
            appId: config.appId,
            publisherUserId: config.publisherUserId,
            currentUserId: config.currentUserId,
            country: config.country,
            appVersion: config.appVersion,
            customProperties: config.customProperties,
            abTestOverride: override,
            advertisingId: config.advertisingId,
            hasAdvertisingId: config.hasAdvertisingId,
            privacy: config.privacy
        )
        publisherConfig = config
    }

    /// Setea el bloque de privacy del publisher.
    public func setPrivacy(
        tcfConsentString: String? = nil,
        usPrivacyString: String? = nil,
        subjectToGdpr: Bool? = nil,
        gdprConsent: Bool? = nil,
        ccpaOptOut: Bool? = nil,
        isChildDirected: Bool = false,
        limitedDataUse: Bool = false
    ) {
        guard var config = publisherConfig else { return }
        let privacy = PublisherPrivacy(
            tcfConsentString: tcfConsentString,
            usPrivacyString: usPrivacyString,
            subjectToGdpr: subjectToGdpr,
            gdprConsent: gdprConsent,
            ccpaOptOut: ccpaOptOut,
            isChildDirected: isChildDirected,
            limitedDataUse: limitedDataUse
        )
        config = PublisherConfig(
            loomitApiKey: config.loomitApiKey,
            clientId: config.clientId,
            appId: config.appId,
            publisherUserId: config.publisherUserId,
            currentUserId: config.currentUserId,
            country: config.country,
            appVersion: config.appVersion,
            customProperties: config.customProperties,
            abTestOverride: config.abTestOverride,
            advertisingId: config.advertisingId,
            hasAdvertisingId: config.hasAdvertisingId,
            privacy: privacy
        )
        publisherConfig = config
        sendDebugIdentifiers()
    }

    /// Setea el Advertising ID (IDFA en iOS). Opcional, para test devices.
    public func setAdvertisingId(_ advertisingId: String?) {
        guard var config = publisherConfig else { return }
        config = PublisherConfig(
            loomitApiKey: config.loomitApiKey,
            clientId: config.clientId,
            appId: config.appId,
            publisherUserId: config.publisherUserId,
            currentUserId: config.currentUserId,
            country: config.country,
            appVersion: config.appVersion,
            customProperties: config.customProperties,
            abTestOverride: config.abTestOverride,
            advertisingId: advertisingId,
            hasAdvertisingId: config.hasAdvertisingId,
            privacy: config.privacy
        )
        publisherConfig = config
        sendDebugIdentifiers()
    }

    /// Setea si el dispositivo tiene Advertising ID disponible (ATT granted).
    public func setHasAdvertisingId(_ hasAdvertisingId: Bool) {
        guard var config = publisherConfig else { return }
        config = PublisherConfig(
            loomitApiKey: config.loomitApiKey,
            clientId: config.clientId,
            appId: config.appId,
            publisherUserId: config.publisherUserId,
            currentUserId: config.currentUserId,
            country: config.country,
            appVersion: config.appVersion,
            customProperties: config.customProperties,
            abTestOverride: config.abTestOverride,
            advertisingId: config.advertisingId,
            hasAdvertisingId: hasAdvertisingId,
            privacy: config.privacy
        )
        publisherConfig = config
        sendDebugIdentifiers()
    }

    /// Setea el country del dispositivo (ISO 3166-1 alpha-2, ej: "US", "AR").
    /// Si no se setea, el SDK intentará resolverlo automáticamente (paridad con Android).
    public func setCountry(_ country: String?) {
        guard var config = publisherConfig else { return }
        config = PublisherConfig(
            loomitApiKey: config.loomitApiKey,
            clientId: config.clientId,
            appId: config.appId,
            publisherUserId: config.publisherUserId,
            currentUserId: config.currentUserId,
            country: country,
            appVersion: config.appVersion,
            customProperties: config.customProperties,
            abTestOverride: config.abTestOverride,
            advertisingId: config.advertisingId,
            hasAdvertisingId: config.hasAdvertisingId,
            privacy: config.privacy
        )
        publisherConfig = config
    }

    // MARK: - Public API: Adapters

    /// Registra un adapter. Necesario antes de `initAllFromPlan` (futura ETAPA).
    public func registerAdapter(_ adapter: any OfferwallAdapter) async {
        await registry.register(adapter)
    }

    /// Quita un adapter por key.
    public func unregisterAdapter(providerKey: String) async {
        await registry.unregister(providerKey: providerKey)
    }

    /// Lista de keys de adapters registrados (lowercase, sorted).
    public func registeredAdapterKeys() async -> [String] {
        await registry.registeredKeys
    }

    // MARK: - Public API: Identifiers (read-only)

    /// XIFA actual (UUID v4 persistido). Generado on first access.
    public func xifa() -> String {
        identifiers.xifa()
    }

    /// Device fingerprint v1 — SHA-256(IDFV + ":" + bundleId).
    public func deviceFingerprint() -> String {
        identifiers.deviceFingerprint()
    }

    /// IDFV crudo (`nil` en edge cases).
    public func idfv() -> String? {
        identifiers.idfv()
    }

    /// Bundle identifier de la app del publisher.
    public func bundleIdentifier() -> String? {
        identifiers.bundleIdentifier()
    }

    /// Resuelve el userId actual aplicando la cascade.
    public func resolvedUserId() -> String {
        let resolver = UserIdResolver(
            currentUserId: publisherConfig?.currentUserId,
            publisherUserId: publisherConfig?.publisherUserId,
            xifa: identifiers.xifa()
        )
        return resolver.resolved
    }

    // MARK: - Public API: Fetch config

    /// Fetchea la config del backend.
    ///
    /// Side-effects:
    /// - Si exitoso, `lastConfig` se actualiza y `state` pasa a `.ready`.
    /// - Despacha al `OfferwallListener` global con el resultado.
    /// - Aplica retry según `retryPolicy` ante errores transientes.
    @discardableResult
    public func fetchConfig() async throws -> ConfigResponse {
        guard let pubConfig = publisherConfig else {
            let err = OfferwallError.notInitialized(reason: "setLoomitApiKey not called")
            await dispatch(configResult: .failure(err))
            throw err
        }

        guard !pubConfig.loomitApiKey.isEmpty else {
            let err = OfferwallError.missingApiKey
            await dispatch(configResult: .failure(err))
            throw err
        }

        let client = ensureBackendClient(for: pubConfig)
        let request = buildConfigRequest(from: pubConfig)

        // Si el client es ResilientBackendClient, usamos la API detallada
        // para conocer la fuente (network/cache fresh/cache stale).
        if let resilient = client as? ResilientBackendClient {
            let result = await resilient.fetchConfigDetailed(request)
            switch result {
            case .success(let response, let source):
                print("[LoomitOW] fetchConfig result source=\(source.rawValue)")
                self.lastConfig = response
                self.lastConfigSource = source
                self.state = .ready
                await applyLoggingConfig(from: response, pubConfig: pubConfig)
                await onConfigFetchSuccess(response: response, source: source.rawValue)
                await dispatch(configResult: .success(response))
                return response
            case .failure(let error, let fallbackAvailable):
                await emitEvent(
                    type: "config_error",
                    provider: "SDK",
                    payload: [
                        "error": .string(error.localizedDescription),
                        "fallback_available": .bool(fallbackAvailable)
                    ],
                    includeLifecycle: false
                )
                await dispatch(configResult: .failure(error))
                throw error
            }
        }

        // Fallback: cliente sin source tracking (ej: mock en tests).
        do {
            let response = try await client.fetchConfig(request)
            self.lastConfig = response
            self.lastConfigSource = .network
            self.state = .ready
            await applyLoggingConfig(from: response, pubConfig: pubConfig)
            await onConfigFetchSuccess(response: response, source: "network")
            await dispatch(configResult: .success(response))
            return response
        } catch let error as OfferwallError {
            await emitEvent(
                type: "config_error",
                provider: "SDK",
                payload: ["error": .string(error.localizedDescription)],
                includeLifecycle: false
            )
            await dispatch(configResult: .failure(error))
            throw error
        } catch {
            let wrapped = OfferwallError.unknown(underlying: error.localizedDescription)
            await emitEvent(
                type: "config_error",
                provider: "SDK",
                payload: ["error": .string(wrapped.localizedDescription)],
                includeLifecycle: false
            )
            await dispatch(configResult: .failure(wrapped))
            throw wrapped
        }
    }

    /// Called after successful fetchConfig to build plan and emit config_success.
    private func onConfigFetchSuccess(response: ConfigResponse, source: String) async {
        // Build provider plan: prefer offerwall.default_waterfall, fallback to configurations
        var plan: [ProviderPlanEntry]
        if let waterfall = response.offerwall?.defaultWaterfall, !waterfall.isEmpty {
            plan = waterfall.filter { $0.isActive }
                .sorted { $0.priority < $1.priority }
        } else if !response.configurations.isEmpty {
            plan = response.configurations.filter { $0.isActive }
                .sorted { $0.priority < $1.priority }
        } else {
            plan = []
        }

        // Also include providers from ad_space_overrides for initialization
        // (they may be used when show() is called with specific adSpace)
        if let offerwall = response.offerwall {
            print("[OfferwallSDK] Processing ad_space_overrides: \(offerwall.adSpaceOverrides.count) spaces")
            for (adSpaceId, override) in offerwall.adSpaceOverrides {
                print("[OfferwallSDK] AdSpace '\(adSpaceId)' enabled: \(override.enabled), waterfall count: \(override.waterfall.count)")
                if override.enabled {
                    for entry in override.waterfall where entry.isActive {
                        print("[OfferwallSDK] Found provider in override: \(entry.providerId), priority: \(entry.priority)")
                        // Add to plan if not already present (by providerId)
                        if !plan.contains(where: { $0.providerId == entry.providerId }) {
                            print("[OfferwallSDK] Adding provider to plan: \(entry.providerId)")
                            plan.append(entry)
                        } else {
                            print("[OfferwallSDK] Provider already in plan: \(entry.providerId)")
                        }
                    }
                }
            }
        }

        // Sort final plan by priority
        plan.sort { $0.priority < $1.priority }

        self.providerPlan = plan
        self.configFetchCompleted = true

        // Send to debug collector (plan without init status yet)
        sendDebugProviderPlan()

        // Update debugging status from backend (backend-forced has priority)
        if response.debuggingStatus == true {
            debuggingEnabled = true
        }

        // Set experiment assignments from config response (paridad con Android)
        let experimentPayloads = response.collectExperimentPayloads()
        print("[OfferwallSDK] Collected \(experimentPayloads.count) experiment payload(s)")
        setLastExperimentAssignments(rawExperiments: experimentPayloads)

        // Emit config_success (no lifecycle — this is a config event)
        await emitEvent(
            type: "config_success",
            provider: "SDK",
            payload: [
                "providers_count": .int(Int64(plan.count)),
                "providers": .array(plan.map { .string($0.providerId) }),
                "priorities": .array(plan.map { .int(Int64($0.priority)) }),
                "segment": response.segment.map { .string($0) } ?? .null,
                "source": .string(source)
            ],
            includeLifecycle: false
        )

        // Log config success
        await log(category: LogCategory.backendConfigAnalysis, level: .info, data: [
            "event": .string("config_fetch_success"),
            "source": .string(source),
            "providers_count": .int(Int64(plan.count)),
            "segment": response.segment.map { .string($0) } ?? .null
        ])
    }

    // MARK: - Public API: Resilience state

    /// Estado actual de resiliencia (modo, fuente de config, circuit state).
    public func resilienceState() async -> ResilienceState {
        let circuitState: CircuitState
        if let resilient = resilientClient {
            circuitState = await resilient.circuitState()
        } else {
            circuitState = .closed
        }
        let cacheAge = configCache.getAge()
        let mode: SdkOperationMode = {
            switch lastConfigSource {
            case .network, .none: return .normal
            case .cacheFresh: return .normal
            case .cacheStale: return .degraded
            case .emergency: return .emergency
            }
        }()
        return ResilienceState(
            operationMode: mode,
            configSource: lastConfigSource,
            cacheAge: cacheAge,
            backendCircuitState: circuitState
        )
    }

    // MARK: - Test hooks (internal)

    /// Permite a tests cambiar el retry policy.
    func __setRetryPolicyForTesting(_ policy: RetryPolicy) {
        self.retryPolicy = policy
    }

    /// Permite a tests inyectar el cache persistente.
    func __setConfigCacheForTesting(_ cache: ConfigCache) {
        self.configCache = cache
        self.backendClient = nil
        self.resilientClient = nil
    }

    /// Permite a tests cambiar la fetch policy (cache thresholds).
    func __setFetchPolicyForTesting(_ policy: ConfigFetchPolicy) {
        self.fetchPolicy = policy
        self.backendClient = nil
        self.resilientClient = nil
    }

    /// Permite a tests cambiar la config del circuit breaker.
    func __setCircuitBreakerConfigForTesting(_ config: CircuitBreakerConfig) {
        self.circuitConfig = config
        self.backendClient = nil
        self.resilientClient = nil
    }

    /// Permite a tests cambiar la política de event push.
    func __setEventPushPolicyForTesting(_ policy: EventPushPolicy) {
        self.eventPushPolicy = policy
        self.eventPusher = nil
    }

    /// Permite a tests inyectar un event pusher delegate (ej: mock).
    func __setEventPusherDelegateForTesting(_ delegate: OfferwallEventPusher?) {
        self.injectedEventPusherDelegate = delegate
        self.eventPusher = nil
    }

    /// Permite a tests inyectar la cola de eventos.
    func __setEventQueueForTesting(_ queue: EventQueue?) {
        self.injectedEventQueue = queue
        self.eventQueue = nil
        self.eventPusher = nil
    }

    /// Permite a tests inyectar el log uploader.
    func __setLogUploaderForTesting(_ uploader: LogUploader?) {
        self.injectedLogUploader = uploader
        self.productionLogger = nil
        self.logUploader = nil
    }

    /// Permite a tests obtener acceso al ProductionLogger interno.
    func __getProductionLoggerForTesting() -> ProductionLogger? {
        productionLogger
    }

    /// Permite a tests inyectar / reemplazar el backend client.
    func __setBackendClientForTesting(_ client: BackendClient?) {
        self.injectedBackendClient = client
        self.backendClient = nil
    }

    /// Resetea estado para tests. **No usar en producción.**
    func __resetForTesting() {
        self.state = .uninitialized
        self.lastConfig = nil
        self.lastConfigSource = nil
        self.publisherConfig = nil
        self.environment = .live
        self.backendClient = nil
        self.injectedBackendClient = nil
        self.resilientClient = nil
        self.retryPolicy = .default
        self.fetchPolicy = .default
        self.circuitConfig = .default
        self.eventPushPolicy = .default
        self.eventPusher = nil
        self.injectedEventPusherDelegate = nil
        self.eventQueue = nil
        self.injectedEventQueue = nil
        self.lifecycleId = 0
        self.currentLifecycleId = 0
        self.lifecycleStartCount = 0
        self.pendingShowLifecycleId = 0
        self.currentProviderIndex = 0
        self.currentProviderKey = nil
        self.lifecycleIdFromAvailability = false
        self.currentAdSpace = nil
        self.providerPlan = []
        self.providerInstances = []
        self.providerListeners = []
        self.providerInitialized = []
        self.providerHasContent = []
        self.configFetchCompleted = false
        self.isInitializingProviders = false
        self.providersInitialized = false
        self.productionLogger = nil
        self.logUploader = nil
        self.injectedLogUploader = nil
    }

    // MARK: - Internal helpers

    private func ensureBackendClient(for config: PublisherConfig) -> BackendClient {
        if let injected = injectedBackendClient {
            return injected
        }
        if let existing = backendClient {
            return existing
        }
        let http = HTTPBackendClient(environment: environment, apiKey: config.loomitApiKey)
        let retrying = RetryingBackendClient(wrapping: http, policy: retryPolicy)
        let breaker = CircuitBreaker(name: "backend", config: circuitConfig)
        let resilient = ResilientBackendClient(
            wrapping: retrying,
            cache: configCache,
            breaker: breaker,
            policy: fetchPolicy
        )
        self.backendClient = resilient
        self.resilientClient = resilient
        return resilient
    }

    private func buildConfigRequest(from config: PublisherConfig) -> ConfigRequest {
        let xifa = identifiers.xifa()
        let bundleId = identifiers.bundleIdentifier()
        let resolvedAppId = config.appId ?? bundleId  // fallback a bundleId si no se setteó appId (como en Android)

        // Resolver country automáticamente si no está seteado (paridad con Android)
        let resolvedCountry = config.country ?? resolveDeviceCountry()

        // Resolver override de A/B test para enviar al backend (paridad con Android)
        let abTestOverridePayload = resolveAbTestOverridePayload()

        // Resolver privacy con cascada device (CMP) → publisher → defaults
        // Paridad con Android mergePrivacy() aplicado en buildConfigRequest (OfferwallSdk.kt:2808).
        let resolvedPrivacy = resolvePrivacy(pubConfig: config)

        return ConfigRequest(
            clientId: config.clientId,
            appId: resolvedAppId,
            packageName: bundleId,
            publisherUserId: config.publisherUserId,
            xifa: xifa,
            tcfConsentString: resolvedPrivacy.tcfString,
            usPrivacyString: resolvedPrivacy.usPrivacyString,
            subjectToGdpr: resolvedPrivacy.isGDPRApplicable ? true : nil,
            gdprConsent: resolvedPrivacy.hasGDPRConsent,
            ccpaOptOut: resolvedPrivacy.ccpaOptOut,
            country: resolvedCountry,
            platform: SdkVersion.platform,
            sdkVersion: SdkVersion.current,
            appVersion: config.appVersion,
            hasAdvertisingId: config.hasAdvertisingId,
            aaid: config.advertisingId,
            customProperties: { let s = getCustomPropertiesSnapshot(); return s.isEmpty ? nil : s }(),
            abTestOverride: abTestOverridePayload
        )
    }

    private func dispatch(configResult: Result<ConfigResponse, OfferwallError>) async {
        dispatcher.dispatchConfigResult(configResult)
    }

    // MARK: - Public API: Provider initialization

    // MARK: - Public API: Experiments

    /// Asignación de experimento A/B (paridad con Android)
    public struct ExperimentAssignment {
        public let name: String
        public let group: String?
        public let isActive: Bool
        public let rawPayload: [String: Any]
    }

    /// Retorna las asignaciones de experimentos del último fetchConfig (paridad con Android)
    public func getLastExperimentAssignments() -> [ExperimentAssignment] {
        return lastExperimentAssignments
    }

    /// Retorna true si hay experimentos activos (paridad con Android)
    public func hasActiveExperiments() -> Bool {
        return lastExperimentAssignments.contains { $0.isActive }
    }

    /// Retorna los overrides de experimentos persistidos (paridad con Android)
    public func getExperimentOverrides() -> [String: String] {
        return experimentOverrides
    }

    /// Setea un override manual para un experimento (paridad con Android)
    public func setExperimentOverride(experimentName: String, group: String?) {
        if let group = group {
            experimentOverrides[experimentName] = group
            // Guardar experiment_id si está disponible
            if let experiment = lastExperimentAssignments.first(where: { $0.name == experimentName }) {
                if let experimentId = experiment.rawPayload["experiment_id"] as? String {
                    experimentOverrideIds[experimentName] = experimentId
                }
            }
        } else {
            experimentOverrides.removeValue(forKey: experimentName)
            experimentOverrideIds.removeValue(forKey: experimentName)
        }
        // Persistir en UserDefaults
        userDefaults.set(experimentOverrides, forKey: "loomit_experiment_overrides")
        userDefaults.set(experimentOverrideIds, forKey: "loomit_experiment_override_ids")
    }

    /// Limpia todos los overrides de experimentos (paridad con Android)
    public func clearExperimentOverrides() {
        experimentOverrides.removeAll()
        experimentOverrideIds.removeAll()
        userDefaults.removeObject(forKey: "loomit_experiment_overrides")
        userDefaults.removeObject(forKey: "loomit_experiment_override_ids")
    }

    // MARK: - Internal methods for experiments (paridad con Android)

    /// Setea las asignaciones de experimentos desde el config response (paridad con Android)
    internal func setLastExperimentAssignments(rawExperiments: [[String: Any]]) {
        if rawExperiments.isEmpty {
            clearLastExperimentAssignments()
            print("[OfferwallSDK] No experiment assignments present in backend response")
            return
        }

        let normalized = rawExperiments.compactMap { normalizeExperimentAssignment(raw: $0) }

        if normalized.isEmpty {
            clearLastExperimentAssignments()
            print("[OfferwallSDK] Experiment payloads were present but none could be normalized")
            return
        }

        lastExperimentAssignments = normalized
        let activeCount = normalized.filter { $0.isActive }.count
        print("[OfferwallSDK] Resolved \(normalized.count) experiment assignment(s); active=\(activeCount)")
    }

    /// Limpia las asignaciones de experimentos (paridad con Android)
    internal func clearLastExperimentAssignments() {
        if !lastExperimentAssignments.isEmpty {
            print("[OfferwallSDK] Clearing \(lastExperimentAssignments.count) cached experiment assignment(s)")
        }
        lastExperimentAssignments.removeAll()
    }

    /// Normaliza un payload de experimento del backend (paridad con Android)
    private func normalizeExperimentAssignment(raw: [String: Any]) -> ExperimentAssignment? {
        let sanitized = sanitizeExperimentMap(raw)
        if sanitized.isEmpty {
            return nil
        }

        // Buscar nombre del experimento (paridad con Android)
        let resolvedName = sanitized["name"] as? String
            ?? sanitized["experiment_name"] as? String
            ?? sanitized["experimentName"] as? String
            ?? sanitized["id"] as? String
            ?? "unknown"

        // Buscar grupo (paridad con Android)
        let resolvedGroup = sanitized["group"] as? String
            ?? sanitized["variant"] as? String
            ?? sanitized["assignment"] as? String
            ?? sanitized["cohort"] as? String

        // Determinar si está activo (paridad con Android)
        let isActive = sanitized["isActive"] as? Bool
            ?? sanitized["is_active"] as? Bool
            ?? sanitized["enabled"] as? Bool
            ?? sanitized["isEnabled"] as? Bool
            ?? sanitized["participating"] as? Bool
            ?? sanitized["assigned"] as? Bool
            ?? true

        return ExperimentAssignment(
            name: resolvedName,
            group: resolvedGroup,
            isActive: isActive,
            rawPayload: sanitized
        )
    }

    /// Sanitiza el mapa de experimento para asegurar tipos correctos (paridad con Android)
    private func sanitizeExperimentMap(_ raw: [String: Any]) -> [String: Any] {
        var sanitized: [String: Any] = [:]
        for (key, value) in raw {
            if let stringValue = value as? String {
                sanitized[key] = stringValue
            } else if let boolValue = value as? Bool {
                sanitized[key] = boolValue
            } else if let numberValue = value as? Int {
                sanitized[key] = numberValue
            } else if let numberValue = value as? Double {
                sanitized[key] = numberValue
            } else {
                sanitized[key] = String(describing: value)
            }
        }
        return sanitized
    }

    /// Carga overrides persistidos desde UserDefaults (paridad con Android)
    private nonisolated static func loadExperimentOverridesStatic() -> ([String: String], [String: String]) {
        var overrides: [String: String] = [:]
        var overrideIds: [String: String] = [:]

        if let loadedOverrides = UserDefaultsSafe.shared.dictionary(forKey: "loomit_experiment_overrides") as? [String: String] {
            overrides = loadedOverrides
        }
        if let loadedIds = UserDefaultsSafe.shared.dictionary(forKey: "loomit_experiment_override_ids") as? [String: String] {
            overrideIds = loadedIds
        }

        return (overrides, overrideIds)
    }

    /// Carga overrides persistidos desde UserDefaults (paridad con Android)
    private func loadExperimentOverrides() -> ([String: String], [String: String]) {
        return (experimentOverrides, experimentOverrideIds)
    }

    /// Resuelve el payload de override de A/B test para enviar al backend (paridad con Android)
    /// Esto permite que el backend sepa qué grupo forzar cuando hay un override manual.
    private func resolveAbTestOverridePayload() -> AbTestOverridePayload? {
        // Recargar overrides de UserDefaults para asegurar que tenemos los últimos valores
        let (overrides, overrideIds) = loadExperimentOverrides()

        if overrides.isEmpty { return nil }

        // Tomar el primer override (asumimos 1 experimento activo a la vez, como en Android)
        guard let (overrideExperimentName, overrideGroup) = overrides.first else { return nil }

        // Intentar obtener el experiment_id del cache persistente
        if let cachedExperimentId = overrideIds[overrideExperimentName] {
            print("[OfferwallSDK] Using cached experiment_id for '\(overrideExperimentName)': \(cachedExperimentId)")
            return AbTestOverridePayload(
                experimentId: cachedExperimentId,
                experimentName: overrideExperimentName,
                group: overrideGroup
            )
        }

        // Si no está en cache, buscar en lastExperimentAssignments
        if let experiment = lastExperimentAssignments.first(where: { $0.name == overrideExperimentName }) {
            let experimentId = experiment.rawPayload["experiment_id"] as? String
                ?? experiment.rawPayload["id"] as? String
                ?? experiment.rawPayload["experimentId"] as? String
                ?? overrideExperimentName

            print("[OfferwallSDK] Sending experiment override: id=\(experimentId), name=\(experiment.name), group=\(overrideGroup)")
            return AbTestOverridePayload(
                experimentId: experimentId,
                experimentName: experiment.name,
                group: overrideGroup
            )
        }

        // Fallback: usar el nombre como ID
        print("[OfferwallSDK] Override set for '\(overrideExperimentName)' but no ID found. Using name as ID.")
        return AbTestOverridePayload(
            experimentId: overrideExperimentName,
            experimentName: overrideExperimentName,
            group: overrideGroup
        )
    }

    // MARK: - Privacy resolution (paridad con Android mergePrivacy)

    /// Resuelve la cascada de privacy para entregar a los providers:
    /// device (CMP auto-read) ?? publisher (setPrivacy) ?? defaults
    ///
    /// Paridad con Android `mergePrivacy(context, config, tcfConsentString, ...)` (OfferwallSdk.kt:3406).
    /// Prioridad:
    ///   1. CMP / device (IAB TCF v2 y US-Privacy de UserDefaults)
    ///   2. Publisher explícito (setPrivacy)
    ///   3. Defaults seguros (false / nil)
    private func resolvePrivacy(pubConfig: PublisherConfig) -> PrivacyConfig {
        let device = PrivacyResolver.resolve()
        let pub = pubConfig.privacy

        let tcf = device.tcfConsentString ?? pub.tcfConsentString
        let us  = device.usPrivacyString  ?? pub.usPrivacyString
        let gdprSubject = device.subjectToGdpr ?? pub.subjectToGdpr ?? false
        let gdprConsent = pub.gdprConsent
        let ccpaOptOut = device.ccpaOptOut ?? pub.ccpaOptOut

        return PrivacyConfig(
            isGDPRApplicable: gdprSubject,
            hasGDPRConsent: gdprConsent,
            tcfString: tcf,
            usPrivacyString: us,
            isChildDirected: pub.isChildDirected,
            limitedDataUse: pub.limitedDataUse,
            ccpaOptOut: ccpaOptOut
        )
    }

    // MARK: - Device country resolution (paridad con Android)

    /// Resuelve el country del dispositivo (paridad con Android resolveDeviceCountry).
    ///
    /// Cascade de fuentes (paridad con Android TelephonyManager → locale cascade):
    ///   1. `Locale.current.regionCode` — region configurada por el usuario (más confiable)
    ///   2. `Locale.autoupdatingCurrent.regionCode` — region dinámica
    ///   3. `preferredLanguages` — extraer region del primer idioma preferido (ej: "en-US" → "US")
    ///   4. `Locale(identifier: NSLocale.current.identifier).regionCode` — NSLocale fallback
    private func resolveDeviceCountry() -> String? {
        // Fuente 1: region configurada por el usuario
        if let code = sanitizeIsoCountryCode(Locale.current.regionCode) {
            return code
        }

        // Fuente 2: region dinámica (puede diferir de current en edge cases)
        if let code = sanitizeIsoCountryCode(Locale.autoupdatingCurrent.regionCode) {
            return code
        }

        // Fuente 3: extraer region del primer idioma preferido del sistema
        // Formato BCP-47: "en-US", "es-AR", "fr-FR", etc.
        if let preferredLang = Locale.preferredLanguages.first {
            let locale = Locale(identifier: preferredLang)
            if let code = sanitizeIsoCountryCode(locale.regionCode) {
                return code
            }
        }

        // Fuente 4: NSLocale.current como último fallback
        let nsLocale = Locale(identifier: NSLocale.current.identifier)
        return sanitizeIsoCountryCode(nsLocale.regionCode)
    }

    /// Sanitiza el country code ISO 3166-1 alpha-2 (paridad con Android)
    private func sanitizeIsoCountryCode(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.count >= 2 else {
            return nil
        }
        return String(raw.prefix(2)).uppercased()
    }

    /// Returns the current provider plan (from last successful fetchConfig).
    public func getProviderPlan() -> [ProviderPlanEntry] {
        providerPlan
    }

    /// Returns the name of the currently active provider.
    /// Paridad con Android `getActiveProviderName()`.
    public func getActiveProviderName() -> String? {
        guard currentProviderIndex >= 0, currentProviderIndex < providerPlan.count else {
            return nil
        }
        return providerPlan[currentProviderIndex].providerId
    }

    /// Returns list of providers that have content available, respecting plan order.
    /// Paridad con Android `getAvailableProviders()`.
    public func getAvailableProviders() -> [String] {
        return providerPlan.enumerated().compactMap { (index, entry) -> String? in
            guard index < providerHasContent.count, providerHasContent[index] else {
                return nil
            }
            return entry.providerId
        }
    }

    /// `true` if providers have been successfully initialized.
    public func hasProvidersInitialized() -> Bool {
        providersInitialized
    }

    /// Returns the last raw config response as JSON string.
    /// Mirrors Android `getLastRawConfigResponse()`.
    public func getLastRawConfigResponse() -> String? {
        guard let config = lastConfig else { return nil }
        // Encode ConfigResponse back to JSON
        if let data = try? JSONEncoder().encode(config),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return nil
    }

    /// Returns the source of the last config fetch.
    /// Mirrors Android `getLastConfigSource()`.
    public func getLastConfigSource() -> String? {
        return lastConfigSource?.rawValue
    }

    /// Returns the resolved segment name from the last config.
    /// Mirrors Android `getLastSegmentName()` which returns `"Default"` when no segment is resolved.
    public func getLastSegmentName() -> String {
        let segment = lastConfig?.segment?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return segment.isEmpty ? "Default" : segment
    }

    /// Runs network diagnostics and returns a summary.
    /// Mirrors Android `runNetworkDiagnostics(context, callback)`.
    public func runNetworkDiagnostics() async -> NetworkDiagnosticsSummary {
        // Default hosts to check - matches Android implementation
        let hosts = [
            "google.com",
            "apple.com",
            environment.baseURL.host ?? "loomit.io"
        ].compactMap { $0 }
        return await NetworkDiagnostics.collect(hosts: hosts)
    }

    /// Returns a preview of the config request payload that would be sent.
    /// Mirrors Android `getConfigRequestPreview(context, clientId, appId)`.
    public func getConfigRequestPreview(clientId: String, appId: String?) -> String {
        let payload: [String: Any] = [
            "client_id": clientId,
            "app_id": appId ?? publisherConfig?.appId ?? "",
            "user_id": resolvedUserId(),
            "xifa": identifiers.xifa ?? "",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "platform": "ios",
            "environment": environment.description
        ]

        if let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }

    /// Initializes all providers from the plan built by `fetchConfig`.
    ///
    /// Mirrors Kotlin `initAllFromPlan(context)`. Must be called after `fetchConfig`.
    /// Creates provider instances via registered adapters and initializes them.
    ///
    /// Events emitted (backend):
    /// - `providers_initialization_complete` (aggregate)
    /// - `providers_availability_snapshot` (after 2s grace + lifecycle start)
    public func initAllFromPlan() async {
        // Protection 1: Must complete fetchConfig first
        guard configFetchCompleted else {
            dispatcher.dispatchDidFailToInitialize("Config not fetched. Call fetchConfig first.")
            return
        }

        // Protection 2: Block concurrent initializations
        guard !isInitializingProviders else {
            return
        }

        // Protection 3: Ignore if already initialized (idempotency)
        guard !providersInitialized else {
            // Already initialized, don't re-emit events
            return
        }

        guard !providerPlan.isEmpty else {
            dispatcher.dispatchDidFailToInitialize("Plan de proveedores vacío")
            return
        }

        print("[OfferwallSDK] initAllFromPlan called with \(providerPlan.count) providers in plan")
        for (index, entry) in providerPlan.enumerated() {
            print("[OfferwallSDK] Provider in plan[\(index)]: \(entry.providerId), priority: \(entry.priority), isActive: \(entry.isActive)")
        }

        isInitializingProviders = true
        let startTime = Date()
        var results: [ProviderInitResult] = []

        // Resolve identity for providers (§2.3 cascade)
        let xifa = identifiers.xifa()
        let pubConfig = publisherConfig ?? PublisherConfig.empty(apiKey: "")
        let resolver = UserIdResolver(
            currentUserId: pubConfig.currentUserId,
            publisherUserId: pubConfig.publisherUserId,
            xifa: xifa
        )
        let userId = resolver.resolved
        let bundleId = identifiers.bundleIdentifier()
        let resolvedAppId = pubConfig.appId ?? bundleId ?? "unknown"

        // Initialize availability tracking arrays (paridad con Android)
        providerAvailabilityKnown.removeAll()
        for _ in 0..<providerPlan.count {
            providerAvailabilityKnown.append(false)
        }
        availabilityEmitTask?.cancel()
        availabilityBarrierDeadline = 0

        for (_, planEntry) in providerPlan.enumerated() {
            let providerKey = planEntry.normalizedProviderId
            let providerStart = Date()

            print("[OfferwallSDK] Initializing provider: \(providerKey)")

            // Look up adapter
            guard let adapter = await registry.adapter(for: providerKey) else {
                let duration = Date().timeIntervalSince(providerStart) * 1000
                print("[OfferwallSDK] No adapter registered for: \(providerKey)")
                results.append(ProviderInitResult(
                    provider: providerKey,
                    status: "failed",
                    durationMs: Int64(duration),
                    error: "No adapter registered for '\(providerKey)'"
                ))
                continue
            }

            print("[OfferwallSDK] Adapter found for: \(providerKey)")

            // Create provider instance (must be on MainActor)
            let provider = await adapter.createProvider()

            // Build ProviderConfig for the adapter
            let credentials = planEntry.credentials.compactMapValues { $0.coerceToString() }

            // Build adSpaceOverrides for this provider from backend config
            var adSpaceOverrides: [String: [String: String]] = [:]
            if let offerwall = lastConfig?.offerwall {
                for (adSpaceId, override) in offerwall.adSpaceOverrides {
                    // Find the entry for this provider in the override waterfall
                    if let providerEntry = override.waterfall.first(where: { $0.normalizedProviderId == providerKey }) {
                        let overrideCredentials = providerEntry.credentials.compactMapValues { $0.coerceToString() }
                        adSpaceOverrides[adSpaceId] = overrideCredentials
                    }
                }
            }

            let resolvedPrivacy = resolvePrivacy(pubConfig: pubConfig)

            let providerConfig = ProviderConfig(
                providerKey: providerKey,
                priority: planEntry.priority,
                credentials: credentials,
                settings: [:],
                privacy: resolvedPrivacy,
                userId: userId,
                xifa: xifa,
                appId: resolvedAppId,
                country: pubConfig.country,
                sdkVersion: SdkVersion.current,
                appVersion: pubConfig.appVersion,
                adSpaceOverrides: adSpaceOverrides
            )

            // Create internal listener for this provider (MainActor-isolated)
            let internalListener = await InternalProviderListener(sdk: self)
            providerListeners.append(internalListener) // Retain to avoid deallocation

            // Initialize the provider
            let initResult = await provider.initialize(config: providerConfig, listener: internalListener)
            let duration = Date().timeIntervalSince(providerStart) * 1000

            print("[OfferwallSDK] Provider \(providerKey) init result: \(initResult)")

            switch initResult {
            case .success:
                providerInstances.append(provider)
                providerInitialized.append(true)
                let available = await provider.isAvailable()
                providerHasContent.append(available)
                print("[OfferwallSDK] Provider \(providerKey) initialized successfully, available: \(available)")
                results.append(ProviderInitResult(
                    provider: providerKey,
                    status: "success",
                    durationMs: Int64(duration)
                ))

            case .failure(let error):
                providerInitialized.append(false)
                providerHasContent.append(false)
                print("[OfferwallSDK] Provider \(providerKey) failed to initialize: \(error.localizedDescription)")
                results.append(ProviderInitResult(
                    provider: providerKey,
                    status: "failed",
                    durationMs: Int64(duration),
                    error: error.localizedDescription
                ))
            }
        }

        let totalDuration = Date().timeIntervalSince(startTime) * 1000

        // Emit providers_initialization_complete
        await emitProvidersInitializationComplete(results: results, totalDurationMs: Int64(totalDuration))

        // Log provider initialization results
        let successCount = results.filter { $0.status == "success" }.count
        let failedProviders = results.filter { $0.status == "failed" }.map { $0.provider }

        await log(category: LogCategory.providerPerformance, level: .info, data: [
            "event": .string("providers_initialization_complete"),
            "total_duration_ms": .int(Int64(totalDuration)),
            "success_count": .int(Int64(successCount)),
            "failed_count": .int(Int64(failedProviders.count)),
            "total_count": .int(Int64(results.count))
        ])

        for result in results where result.status == "failed" {
            await log(category: LogCategory.providerInitFailures, level: .error, data: [
                "event": .string("provider_init_failed"),
                "provider": .string(result.provider),
                "error": result.error.map { .string($0) } ?? .null,
                "duration_ms": .int(result.durationMs)
            ])
        }

        // Notify listener

        // Send to debug collector (with init status)
        sendDebugProviderPlan()

        if successCount > 0 {
            dispatcher.dispatchDidInitialize()
        } else {
            dispatcher.dispatchDidFailToInitialize("Todos los proveedores fallaron")
        }

        // Grace period for content validation, then start lifecycle (matches Kotlin delay(2000))
        let capturedSuccessCount = successCount
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s grace period
            guard let self = self else { return }
            await self.completeInitAndStartLifecycle(successCount: capturedSuccessCount)
        }
    }

    /// Called after 2s grace period to finalize init and start first lifecycle.
    private func completeInitAndStartLifecycle(successCount: Int) async {
        isInitializingProviders = false
        if successCount > 0 {
            providersInitialized = true
            
            // State transition: INITIALIZING -> READY
            let transitioned = await stateMachine.transition(from: .initializing, to: .ready)
            if transitioned {
                await lifecycleDiagnosticLogger?.onStateTransition(from: .initializing, to: .ready, trigger: "initComplete-success")
            }
            
            // GUARD: Prevent duplicate lifecycle starts (anti-pattern §10.9)
            if currentLifecycleId == 0 {
                await startNewLifecycle()
                // Set availability barrier and schedule snapshot (paridad con Android)
                availabilityBarrierDeadline = Date().timeIntervalSince1970 + Self.CYCLE_MAX_WAIT_MS
                scheduleAvailabilitySnapshot(reason: "lifecycle_start")
            } else {
                await lifecycleDiagnosticLogger?.onDoubleStartPrevented(
                    currentLifecycleId: currentLifecycleId,
                    attemptedBy: "completeInitAndStartLifecycle"
                )
            }
        } else {
            providersInitialized = false
            
            // State transition: INITIALIZING -> CONFIG_READY (all failed)
            await stateMachine.forceState(.configReady)
            await lifecycleDiagnosticLogger?.onStateTransition(from: .initializing, to: .configReady, trigger: "initComplete-allFailed")
        }
    }

    /// Schedule availability snapshot with barrier logic (paridad con Android)
    private func scheduleAvailabilitySnapshot(reason: String) {
        guard !isInitializingProviders else {
            print("[OfferwallSDK] scheduleAvailabilitySnapshot ignored (initialization in progress), reason=\(reason)")
            return
        }
        // No active barrier? Avoid emitting more than once per cycle.
        guard availabilityBarrierDeadline > 0 else {
            print("[OfferwallSDK] scheduleAvailabilitySnapshot ignored (no active barrier), reason=\(reason)")
            return
        }
        
        availabilityEmitTask?.cancel()
        availabilityEmitTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(Self.AVAILABILITY_DEBOUNCE_MS * 1_000_000_000))
                
                while true {
                    let allKnown = !providerAvailabilityKnown.isEmpty && 
                               providerAvailabilityKnown.prefix(providerPlan.count).allSatisfy { $0 }
                    let timedOut = Date().timeIntervalSince1970 >= availabilityBarrierDeadline
                    
                    if allKnown || timedOut { break }
                    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                }
                
                print("[OfferwallSDK] Emitting providers_availability_snapshot (reason=\(reason))")
                await emitProvidersAvailabilitySnapshot()
            } catch {
                // Task was cancelled or interrupted
            }
            availabilityBarrierDeadline = 0
        }
    }

    /// Handle provider availability changes (paridad con Android)
    func handleProviderDidChangeAvailability(providerKey: String, isAvailable: Bool) async {
        // Find provider index
        guard let index = providerPlan.firstIndex(where: { $0.normalizedProviderId == providerKey }) else {
            return
        }
        
        guard providerHasContent.indices.contains(index) else { return }
        
        // Update availability state
        providerHasContent[index] = isAvailable
        
        // Mark provider as having responded at least once in this cycle
        if providerAvailabilityKnown.indices.contains(index) {
            providerAvailabilityKnown[index] = true
        }
        
        print("[OfferwallSDK] Provider \(providerKey) availability changed: \(isAvailable), known: \(providerAvailabilityKnown[index])")

        // Log availability change
        await log(category: LogCategory.lifecycleSequencing, level: .info, data: [
            "event": .string("provider_availability_changed"),
            "provider": .string(providerKey),
            "is_available": .bool(isAvailable),
            "lifecycle_id": .int(Int64(currentLifecycleId))
        ])

        // Send to debug collector (content status changed)
        sendDebugProviderPlan()

        // Dispatch UX callback (single-path §2.2)
        dispatcher.dispatchAvailabilityChanged(isAvailable)

        if availabilityBarrierDeadline > 0 {
            // Barrier still active — let the normal debounce path handle it
            scheduleAvailabilitySnapshot(reason: "availability_change")
        } else if isAvailable {
            // Barrier already expired but provider just became available (e.g. Tapjoy
            // contentIsReady fires after the initial 3 s window). Re-arm a short barrier
            // so scheduleAvailabilitySnapshot emits one more snapshot with the updated state.
            availabilityBarrierDeadline = Date().timeIntervalSince1970 + 0.5
            scheduleAvailabilitySnapshot(reason: "late_availability")
        }
    }

    // MARK: - Public API: Show offerwall

    /// Returns `true` if at least one provider is initialized and has content.
    public func hasAvailableOfferwall() -> Bool {
        for (index, _) in providerPlan.enumerated() {
            let isInit = providerInitialized.indices.contains(index) && providerInitialized[index]
            let hasContent = providerHasContent.indices.contains(index) && providerHasContent[index]
            if isInit && hasContent { return true }
        }
        return false
    }

    /// Notifica cambio de disponibilidad solo si cambió (paridad con Android).
    private func notifyAvailabilityChangedIfNeeded() {
        let anyAvailable = hasAvailableOfferwall()
        if anyAvailable != lastKnownAvailability {
            lastKnownAvailability = anyAvailable
            Task { @MainActor in
                dispatcher.dispatchAvailabilityChanged(anyAvailable)
            }
        }
    }

    /// Shows the offerwall from the given presenter.
    ///
    /// Mirrors Kotlin `show(activity, providerIdOverride, adSpace)`.
    /// Validates preconditions, emits `show_request`, delegates to the active provider.
    ///
    /// Events emitted:
    /// - `show_request` (before presenting)
    /// - `content_show` (provider confirms display — via UX callback)
    /// - `content_dismiss` (provider closed — via UX callback)
    /// - `provider_show_failed` (if provider fails — via UX callback)
    /// - `rewarded` (if provider emits client-side reward — via UX callback)
    ///
    /// Lifecycle:
    /// - On close or show_failed: endLifecycle → 500ms delay → recheck → startNewLifecycle + snapshot.
    public func show(
        from presenter: UIViewController,
        providerOverride: String? = nil,
        adSpace: String? = nil
    ) async {
        // Clear previous ad_space (single-request scope)
        currentAdSpace = nil

        guard providersInitialized else {
            dispatcher.dispatchDidFailToShow(
                .notInitialized(reason: "SDK no inicializado"),
                adSpace: adSpace
            )
            return
        }

        // Guard: Prevent double-show (§10.11 anti-pattern)
        guard !isShowingOfferwall else {
            print("[OfferwallSDK] show() aborted: offerwall already showing (double-show prevented)")
            await lifecycleDiagnosticLogger?.logDoubleShowPrevented(
                currentState: String(describing: state),
                attemptedProvider: providerOverride ?? "AUTO"
            )
            return
        }
        
        // CRITICAL: Set flag immediately after guard, before any await
        // This prevents race conditions when multiple show() calls arrive concurrently
        isShowingOfferwall = true
        hasProviderReportedShow = false
        hasProviderReportedClose = false

        // If providerOverride is specified, find that specific provider
        if let override = providerOverride {
            if let (targetIndex, planEntry) = findProviderById(override) {
                let provider = providerInstances[targetIndex]
                let providerKey = planEntry.normalizedProviderId
                
                currentProviderKey = providerKey
                currentProviderIndex = targetIndex
                pendingShowLifecycleId = currentLifecycleId
                currentAdSpace = adSpace
                
                var showPayload: [String: JSONValue] = [
                    "lifecycle_id": .int(Int64(currentLifecycleId)),
                    "provider_override": .string(override)
                ]
                if let adSpace = adSpace {
                    showPayload["ad_space"] = .string(adSpace)
                }
                
                await emitEvent(type: "show_request", provider: providerKey, payload: showPayload)
                
                let showResult = await provider.show(from: presenter, adSpace: adSpace)
                
                switch showResult {
                case .success:
                    // content_show is emitted by the provider via providerDidShow callback,
                    // NOT here. This prevents duplicate events when providers like Tapjoy
                    // also fire a delegate callback after showing.
                    break
                case .failure(let error):
                    await handleShowFailed(
                        providerKey: providerKey,
                        providerIndex: targetIndex,
                        error: error,
                        adSpace: adSpace
                    )
                }
                return
            } else {
                dispatcher.dispatchDidFailToShow(
                    .providerUnavailable(provider: override, reason: "Provider '\(override)' no encontrado en el plan"),
                    adSpace: adSpace
                )
                return
            }
        }

        // Resolve waterfall for adSpace
        let resolvedWaterfall = lastConfig?.offerwall?.resolvedWaterfall(for: adSpace)

        // If override is enabled but waterfall is empty, fail with appropriate message
        if let adSpace = adSpace,
           let override = lastConfig?.offerwall?.adSpaceOverrides[adSpace],
           override.enabled,
           (resolvedWaterfall == nil || resolvedWaterfall?.isEmpty == true) {
            dispatcher.dispatchDidFailToShow(
                .providerUnavailable(provider: "SDK", reason: "No hay provider disponible para ad_space '\(adSpace)'"),
                adSpace: adSpace
            )
            return
        }

        // Use resolved waterfall if available, otherwise use providerPlan
        let waterfallToSearch = resolvedWaterfall ?? providerPlan

        // Find first available provider from resolved waterfall
        guard let (targetIndex, planEntry) = findFirstAvailableProviderInWaterfall(waterfallToSearch) else {
            dispatcher.dispatchDidFailToShow(
                .providerUnavailable(provider: "SDK", reason: "No hay provider disponible en waterfall"),
                adSpace: adSpace
            )
            return
        }

        let provider = providerInstances[targetIndex]
        let providerKey = planEntry.normalizedProviderId

        // Update current provider tracking
        currentProviderKey = providerKey
        currentProviderIndex = targetIndex

        // Capture lifecycle before show() for out-of-order callback safety
        pendingShowLifecycleId = currentLifecycleId
        currentAdSpace = adSpace

        // Emit show_request event
        var showPayload: [String: JSONValue] = [
            "lifecycle_id": .int(Int64(currentLifecycleId))
        ]
        if let adSpace = adSpace {
            showPayload["ad_space"] = .string(adSpace)
        }
        
        // Mark as showing before emitting event (guard against double-show)
        isShowingOfferwall = true
        
        await emitEvent(type: "show_request", provider: providerKey, payload: showPayload)

        // Present the offerwall
        let showResult = await provider.show(from: presenter, adSpace: adSpace)

        switch showResult {
        case .success:
            // Provider started showing. content_show is emitted exclusively by the
            // provider's providerDidShow callback to avoid duplicates.
            break

        case .failure(let error):
            // Provider failed to show
            await handleShowFailed(
                providerKey: providerKey,
                providerIndex: targetIndex,
                error: error,
                adSpace: adSpace
            )
        }
    }

    // MARK: - Public: Manual Control

    /// Close the currently showing offerwall programmatically.
    /// This delegates to the current provider to dismiss its UI.
    ///
    /// Paridad con Android close(): después de cerrar, rechequea disponibilidad
    /// real al provider y reinicia lifecycle si hay contenido disponible.
    public func close() async {
        guard !providerInstances.isEmpty else {
            print("[OfferwallSdk] close() called but no providers initialized")
            return
        }

        let closingIndex = currentProviderIndex
        let provider = providerInstances[closingIndex]
        let providerKey = providerPlan.indices.contains(closingIndex)
            ? providerPlan[closingIndex].providerId
            : "unknown"

        await provider.close()

        // Emit close event
        await emitEvent(type: "content_dismiss", provider: providerKey, payload: [
            "provider_index": .int(Int64(closingIndex)),
            "lifecycle_id": .int(Int64(currentLifecycleId)),
            "reason": .string("manual_close")
        ])

        // Re-query provider for actual availability (paridad con Android close())
        // Android: updateProviderAvailability(idx, provider.hasAvailableContent()) + refreshAvailableProviders()
        let hasContent = await provider.isAvailable()
        updateProviderAvailability(closingIndex, hasContent)

        // Restart lifecycle after manual close (paridad con Android)
        let capturedIndex = closingIndex
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            guard let self = self else { return }
            await self.recheckAndRestartLifecycle(providerIndex: capturedIndex)
        }
    }

    /// Manually trigger failover to the next available provider.
    /// Returns true if failover was initiated, false if no more providers available.
    @discardableResult
    public func failoverToNext(from presenter: UIViewController, adSpace: String? = nil) async -> Bool {
        print("[OfferwallSdk] Manual failover requested from index \(currentProviderIndex)")

        // Mark current provider as unavailable
        updateProviderAvailability(currentProviderIndex, false)

        // Try to find next available provider
        guard let nextProviderInfo = findNextAvailableProvider(startingAt: currentProviderIndex + 1) else {
            print("[OfferwallSdk] No more providers available for failover")
            await emitEvent(type: "failover_exhausted", provider: "none", payload: [
                "lifecycle_id": .int(Int64(currentLifecycleId)),
                "last_provider_index": .int(Int64(currentProviderIndex))
            ])
            return false
        }

        let (nextIndex, nextProviderKey, _) = nextProviderInfo

        print("[OfferwallSdk] Failing over to provider \(nextProviderKey) at index \(nextIndex)")

        // Emit failover event (Android parity: provider_failover)
        await emitEvent(type: "provider_failover", provider: nextProviderKey, payload: [
            "reason": "manual",
            "from_provider": .string(providerPlan.indices.contains(currentProviderIndex) ? providerPlan[currentProviderIndex].providerId : "unknown"),
            "from_index": .int(Int64(currentProviderIndex)),
            "to_provider": .string(nextProviderKey),
            "to_index": .int(Int64(nextIndex)),
            "lifecycle_id": .int(Int64(currentLifecycleId)),
            "ad_space": adSpace.map(JSONValue.string) ?? .null
        ])

        // Log failover
        let fromProvider = providerPlan.indices.contains(currentProviderIndex) ? providerPlan[currentProviderIndex].providerId : "unknown"
        await log(category: LogCategory.providerFailovers, level: .warning, data: [
            "event": .string("provider_failover"),
            "from_provider": .string(fromProvider),
            "to_provider": .string(nextProviderKey),
            "from_index": .int(Int64(currentProviderIndex)),
            "to_index": .int(Int64(nextIndex)),
            "reason": .string("manual")
        ])

        // Update current index only (Android parity: no automatic show)
        currentProviderIndex = nextIndex
        currentAdSpace = adSpace
        
        // Notify availability change if needed (Android parity)
        notifyAvailabilityChangedIfNeeded()
        
        print("[OfferwallSdk] Failover completed: switched to provider \(nextProviderKey) at index \(nextIndex)")
        return true
    }

    // MARK: - Internal: Helper methods

    /// Update provider availability status.
    private func updateProviderAvailability(_ index: Int, _ available: Bool) {
        guard index >= 0 && index < providerHasContent.count else { return }
        providerHasContent[index] = available
    }

    /// Find a provider by its ID in the provider plan.
    /// Returns tuple of (index, planEntry) or nil if not found.
    private func findProviderById(_ providerId: String) -> (Int, ProviderPlanEntry)? {
        for (index, entry) in providerPlan.enumerated() {
            if entry.providerId.lowercased() == providerId.lowercased() {
                return (index, entry)
            }
        }
        return nil
    }

    /// Find the next available provider starting from a given index.
    /// Returns tuple of (index, providerKey, provider) or nil if none found.
    private func findNextAvailableProvider(startingAt startIndex: Int) -> (Int, String, OfferwallProvider)? {
        for i in startIndex..<providerPlan.count {
            guard i < providerInstances.count else { continue }
            if providerHasContent[i] {
                let providerKey = providerPlan[i].providerId
                return (i, providerKey, providerInstances[i])
            }
        }
        return nil
    }

    // MARK: - Internal: Show callback handlers (called by InternalProviderListener)

    /// Called when a provider confirms the offerwall is visible.
    func handleProviderDidShow(providerKey: String) async {
        guard !hasProviderReportedShow else {
            print("[OfferwallSdk] ⚠️ Duplicate providerDidShow ignored for \(providerKey)")
            return
        }
        hasProviderReportedShow = true

        let lcId = pendingShowLifecycleId != 0 ? pendingShowLifecycleId : currentLifecycleId

        // Use provider from plan for consistency (providerKey from adapter may differ)
        let planProvider = providerPlan.indices.contains(currentProviderIndex)
            ? providerPlan[currentProviderIndex].providerId
            : providerKey

        await emitEvent(type: "content_show", provider: planProvider, payload: [
            "provider_index": .int(Int64(currentProviderIndex)),
            "lifecycle_id": .int(Int64(lcId)),
            "total_available_providers": .int(Int64(providerHasContent.filter { $0 }.count)),
            "ad_space": .string(currentAdSpace ?? "")
        ])

        // Log content show
        await log(category: LogCategory.lifecycleSequencing, level: .info, data: [
            "event": .string("content_show"),
            "provider": .string(planProvider),
            "lifecycle_id": .int(Int64(lcId)),
            "ad_space": .string(currentAdSpace ?? "")
        ])

        // UX callback (single-path §2.2)
        dispatcher.dispatchDidShow(providerKey: providerKey, adSpace: currentAdSpace)
    }

    /// Called when a provider reports show failure.
    private func handleShowFailed(
        providerKey: String,
        providerIndex: Int,
        error: OfferwallError,
        adSpace: String?
    ) async {
        // Reset showing state (guard for double-show)
        isShowingOfferwall = false
        
        let lcId = currentLifecycleId

        await emitEvent(type: "provider_show_failed", provider: providerKey, payload: [
            "error": .string(error.localizedDescription),
            "provider_index": .int(Int64(providerIndex)),
            "lifecycle_id": .int(Int64(lcId)),
            "total_available_providers": .int(Int64(providerHasContent.filter { $0 }.count)),
            "fallback_available": .bool(providerPlan.count > 1)
        ])

        // Log show failure
        await log(category: LogCategory.contentShowFailures, level: .error, data: [
            "event": .string("content_show_failed"),
            "provider": .string(providerKey),
            "error": .string(error.localizedDescription),
            "lifecycle_id": .int(Int64(lcId))
        ])

        // State transition: SHOWING -> READY
        let transitioned = await stateMachine.transition(from: .showing, to: .ready)
        if transitioned {
            await lifecycleDiagnosticLogger?.onStateTransition(from: .showing, to: .ready, trigger: "showFailed")
        }
        
        // End lifecycle
        await endLifecycle(status: "show_failed", reason: error.localizedDescription)

        // UX callback
        dispatcher.dispatchDidFailToShow(error, adSpace: adSpace)

        // Restart lifecycle after provider refill (500ms delay like Kotlin)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            guard let self = self else { return }
            await self.recheckAndRestartLifecycle(providerIndex: providerIndex)
        }
    }

    /// Called when the offerwall is closed.
    func handleProviderDidClose(providerKey: String) async {
        guard !hasProviderReportedClose else {
            print("[OfferwallSdk] ⚠️ Duplicate providerDidClose ignored for \(providerKey)")
            return
        }
        hasProviderReportedClose = true

        // Reset showing state (guard for double-show)
        isShowingOfferwall = false

        let lcIdForEvent = pendingShowLifecycleId != 0 ? pendingShowLifecycleId : currentLifecycleId
        
        // Use provider from plan for consistency (providerKey from adapter may differ)
        let planProvider = providerPlan.indices.contains(currentProviderIndex) 
            ? providerPlan[currentProviderIndex].providerId 
            : providerKey

        await emitEvent(type: "content_dismiss", provider: planProvider, payload: [
            "provider_index": .int(Int64(currentProviderIndex)),
            "lifecycle_id": .int(Int64(lcIdForEvent)),
            "total_available_providers": .int(Int64(providerHasContent.filter { $0 }.count)),
            "fallback_available": .bool(providerPlan.count > 1)
        ])

        // Log content dismiss
        await log(category: LogCategory.lifecycleSequencing, level: .info, data: [
            "event": .string("content_dismiss"),
            "provider": .string(planProvider),
            "reason": .string("user closed offerwall")
        ])

        // UX callback (single-path)
        dispatcher.dispatchDidClose(providerKey: planProvider)

        // State transition: SHOWING -> READY
        let transitioned = await stateMachine.transition(from: .showing, to: .ready)
        if transitioned {
            await lifecycleDiagnosticLogger?.onStateTransition(from: .showing, to: .ready, trigger: "contentDismiss")
        }
        
        // End lifecycle
        await endLifecycle(status: "content_dismiss", reason: "user closed offerwall")
        pendingShowLifecycleId = 0

        // Restart lifecycle after provider refill (500ms delay like Kotlin)
        let capturedIndex = currentProviderIndex
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            guard let self = self else { return }
            await self.recheckAndRestartLifecycle(providerIndex: capturedIndex)
        }
    }

    /// Called when a provider emits a client-side reward.
    func handleProviderDidEarnReward(providerKey: String, amount: Int, currency: String) async {
        let lcId = currentLifecycleId != 0 ? currentLifecycleId : pendingShowLifecycleId
        
        // Use provider from plan for consistency (providerKey from adapter may differ)
        let planProvider = providerPlan.indices.contains(currentProviderIndex)
            ? providerPlan[currentProviderIndex].providerId
            : providerKey

        await emitEvent(type: "rewarded", provider: planProvider, payload: [
            "currency": .string(currency),
            "amount": .int(Int64(amount)),
            "provider_index": .int(Int64(currentProviderIndex)),
            "lifecycle_id": .int(Int64(lcId)),
            "total_available_providers": .int(Int64(providerHasContent.filter { $0 }.count)),
            "fallback_available": .bool(providerPlan.count > 1)
        ])

        // Log reward
        await log(category: LogCategory.lifecycleSequencing, level: .info, data: [
            "event": .string("reward_earned"),
            "provider": .string(planProvider),
            "amount": .int(Int64(amount)),
            "currency": .string(currency)
        ])

        // UX callback (single-path)
        dispatcher.dispatchReward(amount: amount, currency: currency, providerKey: planProvider)
    }

    // MARK: - Private: Show helpers

    /// Find the first initialized provider with content in the plan.
    private func findFirstAvailableProvider() -> (index: Int, entry: ProviderPlanEntry)? {
        // First, try current provider index
        if currentProviderIndex < providerPlan.count,
           providerInitialized.indices.contains(currentProviderIndex),
           providerInitialized[currentProviderIndex],
           providerHasContent.indices.contains(currentProviderIndex),
           providerHasContent[currentProviderIndex] {
            return (currentProviderIndex, providerPlan[currentProviderIndex])
        }
        // Fallback: scan waterfall in priority order
        for (index, entry) in providerPlan.enumerated() {
            let isInit = providerInitialized.indices.contains(index) && providerInitialized[index]
            let hasContent = providerHasContent.indices.contains(index) && providerHasContent[index]
            if isInit && hasContent {
                return (index, entry)
            }
        }
        return nil
    }

    /// Find the first initialized provider with content from a specific waterfall.
    private func findFirstAvailableProviderInWaterfall(_ waterfall: [ProviderPlanEntry]) -> (index: Int, entry: ProviderPlanEntry)? {
        for waterfallEntry in waterfall {
            // Find this provider in the main providerPlan by matching provider + credentials
            let planIndex = providerPlan.firstIndex { planEntry in
                planEntry.normalizedProviderId == waterfallEntry.normalizedProviderId
            }

            if let index = planIndex,
               providerInitialized.indices.contains(index),
               providerInitialized[index],
               providerHasContent.indices.contains(index),
               providerHasContent[index] {
                return (index, providerPlan[index])
            }
        }
        return nil
    }

    /// Recheck provider availability after close/fail and start a new lifecycle.
    private func recheckAndRestartLifecycle(providerIndex: Int) async {
        // Re-query provider for current availability
        if providerInstances.indices.contains(providerIndex),
           providerInitialized.indices.contains(providerIndex),
           providerInitialized[providerIndex] {
            let provider = providerInstances[providerIndex]
            let hasContent = await provider.isAvailable()
            if providerHasContent.indices.contains(providerIndex) {
                providerHasContent[providerIndex] = hasContent
            }
        }

        // GUARD: Prevent duplicate lifecycle starts from concurrent callbacks
        guard currentLifecycleId == 0 else {
            await lifecycleDiagnosticLogger?.onDoubleStartPrevented(
                currentLifecycleId: currentLifecycleId,
                attemptedBy: "recheckAndRestartLifecycle"
            )
            return
        }
        
        // Start new lifecycle
        await startNewLifecycle()
        
        // Re-arm barrier and schedule snapshot with debounce.
        // This gives providers like Tapjoy time to complete auto-refill
        // before emitting the snapshot, avoiding an intermediate state.
        availabilityBarrierDeadline = Date().timeIntervalSince1970 + Self.CYCLE_MAX_WAIT_MS
        scheduleAvailabilitySnapshot(reason: "lifecycle_restart")
    }

    // MARK: - Private: Provider init helpers

    /// Result of a single provider initialization.
    private struct ProviderInitResult {
        let provider: String
        let status: String  // "success" | "failed"
        let durationMs: Int64
        let error: String?

        init(provider: String, status: String, durationMs: Int64, error: String? = nil) {
            self.provider = provider
            self.status = status
            self.durationMs = durationMs
            self.error = error
        }
    }

    private func emitProvidersInitializationComplete(
        results: [ProviderInitResult],
        totalDurationMs: Int64
    ) async {
        let successCount = results.filter { $0.status == "success" }.count
        let failedCount = results.filter { $0.status == "failed" }.count
        let sdkStatus: String
        if successCount == 0 {
            sdkStatus = "no_providers_available"
        } else if successCount == results.count {
            sdkStatus = "fully_operational"
        } else {
            sdkStatus = "partially_operational"
        }

        let activeProvider = results.first { $0.status == "success" }?.provider

        let providersSummary: [JSONValue] = results.map { r in
            .object([
                "provider": .string(r.provider),
                "status": .string(r.status),
                "duration_ms": .int(r.durationMs),
                "error": r.error.map { .string($0) } ?? .null
            ])
        }

        await emitEvent(
            type: "providers_initialization_complete",
            provider: "SDK",
            payload: [
                "total_providers": .int(Int64(results.count)),
                "successful_providers": .int(Int64(successCount)),
                "failed_providers": .int(Int64(failedCount)),
                "initialization_duration_ms": .int(totalDurationMs),
                "sdk_status": .string(sdkStatus),
                "active_provider": activeProvider.map { .string($0) } ?? .null,
                "providers_summary": .array(providersSummary),
                "all_providers_failed": .bool(successCount == 0),
                "partial_failure": .bool(successCount > 0 && successCount < results.count)
            ],
            includeLifecycle: false
        )
    }

    // MARK: - Private: Lifecycle

    private func startNewLifecycle() async {
        // GUARD: Prevent duplicate lifecycle starts (parity with Android)
        if currentLifecycleId != 0 {
            await lifecycleDiagnosticLogger?.onDoubleStartPrevented(
                currentLifecycleId: currentLifecycleId,
                attemptedBy: "startNewLifecycle"
            )
            return
        }
        
        lifecycleStartCount += 1
        currentLifecycleId = allocateNextLifecycleId()
        lifecycleIdFromAvailability = true

        // Reset snapshot tracking for new lifecycle
        lastSnapshotLifecycleId = 0
        lastSnapshotAvailabilityHash = 0
        
        // Capture caller stack for diagnostics
        let callerStack = LifecycleDiagnosticLogger.captureCallerStack(skipFrames: 2, maxFrames: 3)
        await lifecycleDiagnosticLogger?.onLifecycleStarted(
            lifecycleId: currentLifecycleId,
            totalCount: lifecycleStartCount,
            callerStack: callerStack
        )
    }

    private func endLifecycle(status: String, reason: String? = nil) async {
        let endedLc = currentLifecycleId
        let reasonText = reason ?? status
        
        await lifecycleDiagnosticLogger?.onLifecycleEnded(lifecycleId: endedLc, reason: reasonText)
        
        currentLifecycleId = 0
        currentProviderKey = nil
        currentAdSpace = nil
        lifecycleIdFromAvailability = false
    }

    private func allocateNextLifecycleId() -> Int {
        lifecycleId += 1
        // Overflow protection (parity with Android)
        if lifecycleId <= 0 {
            lifecycleId = 1
        }
        return lifecycleId
    }

    private func emitProvidersAvailabilitySnapshot() async {
        // Compute availability hash: combination of hasContent + initialized bits
        let availabilityHash = providerPlan.indices.reduce(into: 0) { hash, index in
            let hasContent = providerHasContent.indices.contains(index) ? providerHasContent[index] : false
            let isInit = providerInitialized.indices.contains(index) ? providerInitialized[index] : false
            let bit = (hasContent ? 1 : 0) | (isInit ? 2 : 0)
            hash = hash * 4 + bit
        }

        // Skip if same lifecycle and same availability state already emitted
        if currentLifecycleId == lastSnapshotLifecycleId && availabilityHash == lastSnapshotAvailabilityHash {
            print("[OfferwallSDK] ⚠️ Duplicate providers_availability_snapshot skipped (same state for LC=\(currentLifecycleId))")
            return
        }

        lastSnapshotLifecycleId = currentLifecycleId
        lastSnapshotAvailabilityHash = availabilityHash

        var providersStatus: [JSONValue] = []
        var availableCount = 0

        for (index, planEntry) in providerPlan.enumerated() {
            let hasContent = providerHasContent.indices.contains(index)
                ? providerHasContent[index]
                : false
            let isInit = providerInitialized.indices.contains(index)
                ? providerInitialized[index]
                : false
            let isAvailable = isInit && hasContent

            if isAvailable { availableCount += 1 }

            providersStatus.append(.object([
                "provider": .string(planEntry.providerId),
                "available": .bool(isAvailable),
                "has_content": .bool(hasContent),
                "last_checked": .int(Int64(Date().timeIntervalSince1970 * 1000))
            ]))
        }

        let activeProvider = providerPlan.indices.contains(currentProviderIndex)
            ? providerPlan[currentProviderIndex].providerId
            : nil

        await emitEvent(
            type: "providers_availability_snapshot",
            provider: "SDK",
            payload: [
                "lifecycle_id": .int(Int64(currentLifecycleId)),
                "total_providers": .int(Int64(providerPlan.count)),
                "available_providers": .int(Int64(availableCount)),
                "active_provider": activeProvider.map { .string($0) } ?? .null,
                "active_index": .int(Int64(currentProviderIndex)),
                "providers": .array(providersStatus),
                "sdk_ready": .bool(availableCount > 0),
                "no_providers_available": .bool(availableCount == 0),
                "all_providers_unavailable": .bool(availableCount == 0 && !providerPlan.isEmpty)
            ],
            includeLifecycle: false
        )
    }

    // MARK: - Public API: Event tracking

    /// Trackea un evento de telemetría. Fire-and-forget por default; el pipeline
    /// resiliente se encarga de retry y persistencia.
    ///
    /// - Parameters:
    ///   - type: Nombre del evento (ej: `content_show`, `rewarded`).
    ///   - provider: Provider asociado, o `"loomit"` para eventos del core.
    ///   - data: Payload arbitrario adicional (debe ser serializable a JSON).
    public func trackEvent(
        type: String,
        provider: String = "loomit",
        data: [String: JSONValue] = [:]
    ) async {
        await emitEvent(type: type, provider: provider, payload: data)
    }

    // MARK: - Internal: emitEvent (single path)

    /// Internal emit that:
    /// 1. Dispatches to tracking listener (mirror for publisher analytics).
    /// 2. Pushes to backend via resilient pipeline.
    ///
    /// Mirrors Kotlin `emitEvent(type, provider, payload, lifecycleId, ...)`.
    private func emitEvent(
        type: String,
        provider: String = "SDK",
        payload: [String: JSONValue] = [:],
        includeLifecycle: Bool = true
    ) async {
        guard let pubConfig = publisherConfig, !pubConfig.loomitApiKey.isEmpty else {
            return
        }

        // Enrich payload with provider
        var enriched = payload
        if enriched["provider"] == nil {
            enriched["provider"] = .string(provider)
        }
        if includeLifecycle, currentLifecycleId != 0 {
            enriched["lifecycle_id"] = .int(Int64(currentLifecycleId))
        }

        // 1. Dispatch to tracking listener
        dispatcher.dispatchTrackingEvent(type, payload: enriched)

        // 1b. Send to Debug Suite (para Unity - no depende del tracking listener)
        sendDebugEvent(type: type, provider: provider, payload: enriched)

        // 2. Push to backend
        let pusher = ensureEventPusher(for: pubConfig)
        let event = buildEvent(type: type, provider: provider, data: enriched, config: pubConfig)
        try? await pusher.push(event)
    }

    /// Flushea ahora la cola persistente. Retorna cantidad enviada.
    @discardableResult
    public func flushEvents() async -> Int {
        guard let pusher = eventPusher else { return 0 }
        return await pusher.flushOnce()
    }

    /// Tamaño actual de la cola persistente de eventos.
    public func pendingEventQueueSize() async -> Int {
        guard let pusher = eventPusher else { return 0 }
        return await pusher.queueSize()
    }

    private func buildEvent(
        type: String,
        provider: String,
        data: [String: JSONValue],
        config: PublisherConfig
    ) -> OfferwallEvent {
        let xifa = identifiers.xifa()
        let bundleId = identifiers.bundleIdentifier()
        let resolvedAppId = config.appId ?? bundleId
        let resolvedCountry = config.country ?? resolveDeviceCountry()

        // Cascade §2.3: currentUserId ?? publisherUserId ?? xifa.
        // Paridad con Android buildEventMetadata() → currentUserId = effectiveUserId.
        let resolver = UserIdResolver(
            currentUserId: config.currentUserId,
            publisherUserId: config.publisherUserId,
            xifa: xifa
        )
        var enrichedData = data
        if enrichedData["user_id"] == nil {
            enrichedData["user_id"] = .string(resolver.resolved)
        }

        return OfferwallEvent(
            type: type,
            provider: provider,
            xifa: xifa,
            appId: resolvedAppId,
            platform: SdkVersion.platform,
            country: resolvedCountry,
            appVersion: config.appVersion,
            sdkVersion: SdkVersion.current,
            deviceModel: DeviceInfo.model,
            osVersion: DeviceInfo.osVersion,
            lifecycleId: lifecycleId,
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
            data: enrichedData
        )
    }

    private func ensureEventPusher(for config: PublisherConfig) -> ResilientEventPusher {
        if let existing = eventPusher { return existing }

        let queue = ensureEventQueue()
        let delegate: OfferwallEventPusher = injectedEventPusherDelegate
            ?? HTTPEventPusher(environment: environment, apiKey: config.loomitApiKey)

        let pusher = ResilientEventPusher(
            delegate: delegate,
            queue: queue,
            policy: eventPushPolicy
        )
        Task { await pusher.start() }
        self.eventPusher = pusher
        return pusher
    }

    private func ensureEventQueue() -> EventQueue {
        if let injected = injectedEventQueue { return injected }
        if let existing = eventQueue { return existing }
        let queue = FileEventQueue(
            fileURL: FileEventQueue.defaultLocation(),
            maxQueueSize: eventPushPolicy.maxQueueSize
        )
        self.eventQueue = queue
        return queue
    }

    // MARK: - Public API: Debug

    /// Construye un `DebugBridge` que la Debug Suite externa puede usar para
    /// inspeccionar estado del SDK. **Read-only.**
    public func debugBridge() -> DebugBridge {
        SdkDebugBridge(sdk: self)
    }

    /// Activa o desactiva el debug panel manualmente.
    /// El backend puede forzar `debuging_status=true` en `fetchConfig`, lo cual
    /// tiene prioridad sobre este setter.
    public func setDebuggingEnabled(_ enabled: Bool) {
        debuggingEnabled = enabled
    }

    /// Inyecta el DebugDataCollector desde la Debug Suite.
    /// Se llama desde DebugPanel cuando se inicializa.
    /// Usamos el protocolo DebugDataCollectorBridge para evitar dependencia circular (paridad con Android reflection).
    public func setDebugDataCollector(_ collector: DebugDataCollectorBridge?) {
        debugDataCollector = collector
        if collector != nil {
            sendDebugCustomProperties()
            sendDebugIdentifiers()
        }
    }

    /// Empuja los identificadores actuales al DebugDataCollector.
    /// Paridad con Android `sendDebugIdentifiers()` (OfferwallSdk.kt:4054).
    private func sendDebugIdentifiers() {
        guard debuggingEnabled, let collector = debugDataCollector else { return }
        collector.updateIdentifiers(
            xifa: identifiers.xifa(),
            publisherUserId: publisherConfig?.publisherUserId,
            hasAdvertisingId: publisherConfig?.hasAdvertisingId ?? false
        )
    }

    /// Método público para registrar config request JSON (paridad con Android)
    public func recordDebugConfigRequest(json: String) {
        print("[OfferwallSDK] recordDebugConfigRequest called, debuggingEnabled=\(debuggingEnabled)")
        sendDebugConfigRequest(json: json)
    }

    /// Método público para registrar config response JSON (paridad con Android)
    public func recordDebugConfigResponse(json: String) {
        print("[OfferwallSDK] recordDebugConfigResponse called, debuggingEnabled=\(debuggingEnabled)")
        sendDebugConfigResponse(json: json)
    }

    // MARK: - Debug JSON helpers (paridad con Android)

    /// Envía el JSON del request config al DebugDataCollector.
    private func sendDebugConfigRequest(json: String) {
        guard debuggingEnabled else { return }
        print("[OfferwallSDK] sendDebugConfigRequest: collector=\(debugDataCollector != nil)")
        debugDataCollector?.recordConfigRequest(json: json)
    }

    /// Envía el JSON de la respuesta config al DebugDataCollector.
    private func sendDebugConfigResponse(json: String) {
        guard debuggingEnabled else { return }
        print("[OfferwallSDK] sendDebugConfigResponse: collector=\(debugDataCollector != nil)")
        debugDataCollector?.recordConfigResponse(json: json)
    }
    
    /// Envía un evento al DebugDataCollector (paridad con Android sendDebugEvent).
    /// Los eventos como show_request, content_show, etc. usan este método.
    private func sendDebugEvent(type: String, provider: String = "SDK", payload: [String: JSONValue] = [:]) {
        guard debuggingEnabled, let collector = debugDataCollector else { return }
        
        Task { @MainActor in
            // Convert JSONValue to String for DebugDataCollector compatibility
            let stringPayload: [String: String] = payload.mapValues { value in
                switch value {
                case .string(let str): return str
                case .int(let int): return String(int)
                case .bool(let bool): return String(bool)
                case .double(let double): return String(double)
                case .array(let array): return "[\(array.count) items]"
                case .object(let object): return "{\(object.count) keys}"
                case .null: return "null"
                }
            }
            
            collector.recordEvent(type: type, provider: provider, payload: stringPayload)
        }
    }

    /// `true` si el debug panel está habilitado (por app o por backend).
    public func isDebuggingEnabled() -> Bool {
        debuggingEnabled
    }

    // MARK: - Debug helpers (internal — usados por SdkDebugBridge)

    func bundleIdentifierForDebug() -> String? {
        identifiers.bundleIdentifier()
    }

    func hasAdvertisingIdForDebug() -> Bool {
        publisherConfig?.hasAdvertisingId ?? false
    }

    func advertisingIdForDebug() -> String? {
        publisherConfig?.advertisingId
    }

    func publisherUserIdForDebug() -> String? {
        publisherConfig?.publisherUserId
    }

    func cachedConfigInfoForDebug() async -> CachedConfigInfo? {
        guard let resilient = resilientClient else { return nil }
        guard let snapshot = await resilient.cachedSnapshot() else { return nil }
        let json: String
        if let data = try? JSONEncoder().encode(snapshot.config),
           let str = String(data: data, encoding: .utf8) {
            json = str
        } else {
            json = "{}"
        }
        return CachedConfigInfo(
            timestamp: snapshot.timestamp,
            source: snapshot.source.rawValue,
            age: snapshot.age(),
            json: json
        )
    }

    func pendingEventsForDebug() async -> [PendingEventInfo] {
        guard let queue = eventQueue ?? injectedEventQueue else { return [] }
        let events = await queue.getAllForDebug()
        return events.map { p in
            let payloadJson: String
            if p.event.data.isEmpty {
                payloadJson = "{}"
            } else if let data = try? JSONEncoder().encode(p.event.data),
                      let str = String(data: data, encoding: .utf8) {
                payloadJson = str
            } else {
                payloadJson = "{}"
            }
            return PendingEventInfo(
                id: p.id,
                type: p.event.type,
                provider: p.event.provider,
                timestamp: p.timestamp,
                retryCount: p.retryCount,
                priority: String(describing: p.priority).uppercased(),
                payload: payloadJson
            )
        }
    }

    func registeredAdapterKeysForDebug() async -> [String] {
        await registry.registeredKeys
    }

    func environmentForDebug() -> BackendEnvironment {
        environment
    }

    /// Fuerza el cambio de environment desde el DS, bypaseando el guard de override.
    func forceSetEnvironment(_ environment: BackendEnvironment) {
        print("[LoomitOW] setEnvironment (DS) → \(environment.baseURL.absoluteString)")
        self.environment = environment
        backendClient = nil
        resilientClient = nil
        configCache.clear()
    }

    func debuggingEnabledForDebug() -> Bool {
        debuggingEnabled
    }

    // MARK: - Public API: Logging

    /// Obtiene un `CategoryLogger` para una categoría. Retorna `nil` si todavía
    /// no se hizo `fetchConfig` (sin config no podemos respetar las políticas).
    public func logger(category: String) async -> CategoryLogger? {
        guard let prod = productionLogger else { return nil }
        return await prod.category(category)
    }

    /// Fuerza flush del buffer del logger.
    public func flushLogs() async {
        await productionLogger?.flush()
    }

    // MARK: - Logging wireup

    private func applyLoggingConfig(from response: ConfigResponse, pubConfig: PublisherConfig) async {
        let bundleId = identifiers.bundleIdentifier() ?? "unknown.bundle"
        let resolvedAppId = pubConfig.appId ?? bundleId
        let resolvedAppVersion = pubConfig.appVersion ?? "unknown"

        // 1. Construir / actualizar uploader.
        let endpointURL: URL? = {
            guard let s = response.loggingConfig?.endpoint, !s.isEmpty else { return nil }
            return URL(string: s)
        }()

        if injectedLogUploader == nil {
            if let existing = logUploader {
                existing.updateApiKey(pubConfig.loomitApiKey)
                existing.updateEndpoint(endpointURL)
            } else {
                self.logUploader = HTTPLogUploader(
                    apiKey: pubConfig.loomitApiKey,
                    endpoint: endpointURL
                )
            }
        }

        let uploader: LogUploader = injectedLogUploader ?? logUploader!

        // 2. Construir o actualizar el ProductionLogger.
        if let existing = productionLogger {
            await existing.updateConfig(response.loggingConfig)
        } else {
            let xifa = identifiers.xifa()
            let device = ProductionLogger.deviceHash(forIdentifier: xifa)
            self.productionLogger = ProductionLogger(
                deviceHash: device,
                appId: resolvedAppId,
                appVersion: resolvedAppVersion,
                uploader: uploader,
                config: response.loggingConfig
            )
            
            // Initialize diagnostic loggers (parity with Android)
            self.lifecycleDiagnosticLogger = LifecycleDiagnosticLogger { [weak self] in
                guard let self = self, let logger = await self.productionLogger else {
                    return CategoryLogger.disabled()
                }
                return await logger.category(LogCategory.lifecycleDiagnostic)
            }
            
            self.eventTrackingLogger = EventTrackingLogger { [weak self] in
                guard let self = self, let logger = await self.productionLogger else {
                    return CategoryLogger.disabled()
                }
                return await logger.category(LogCategory.eventTrackingHealth)
            }
            
            self.pusherHealthLogger = PusherHealthLogger { [weak self] in
                guard let self = self, let logger = await self.productionLogger else {
                    return CategoryLogger.disabled()
                }
                return await logger.category(LogCategory.pusherInfrastructure)
            }
        }

        // 3. Emitir log de configuración recibida
        await log(category: LogCategory.backendConfigAnalysis, level: .info, data: [
            "event": .string("logging_config_applied"),
            "enabled": .bool(response.loggingConfig?.enabled ?? false),
            "categories_count": .int(Int64(response.loggingConfig?.categories.count ?? 0)),
            "endpoint_present": .bool(response.loggingConfig?.endpoint != nil)
        ])
    }

    // MARK: - Internal Logging Helper

    /// Emite un log al backend si el ProductionLogger está disponible.
    private func log(category: String, level: LogLevel, data: [String: JSONValue]) async {
        guard let logger = await productionLogger?.category(category) else { return }
        await logger.log(level, data: data)
    }

    // MARK: - Debug Integration

    /// Sends the current provider plan state via NotificationCenter.
    /// DebugDataCollector listens to this notification to update its state.
    /// Called whenever provider plan or provider state changes.
    private func sendDebugProviderPlan() {
        guard !providerPlan.isEmpty else {
            print("[OfferwallSDK] sendDebugProviderPlan: provider plan is empty, skipping")
            return
        }

        // Build plan info as dictionary (avoid type dependency on DebugDataCollector)
        let planData: [[String: Any]] = providerPlan.enumerated().map { index, entry in
            [
                "provider": entry.providerId,
                "priority": entry.priority,
                "isActive": entry.isActive,
                "isInitialized": index < providerInitialized.count ? providerInitialized[index] : false,
                "hasContent": index < providerHasContent.count ? providerHasContent[index] : false
            ]
        }

        print("[OfferwallSDK] sendDebugProviderPlan: posting notification with \(planData.count) providers")
        for (idx, data) in planData.enumerated() {
            print("[OfferwallSDK]   Provider[\(idx)]: \(data)")
        }

        NotificationCenter.default.post(
            name: NSNotification.Name("com.loomit.offerwall.providerPlanChanged"),
            object: nil,
            userInfo: ["plan": planData]
        )
    }
}
