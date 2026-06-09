//
//  LogModels.swift
//  LoomitOfferwallCore
//
//  Modelos del subsistema de logging. Paridad con Android `LogEntry` / `LogBatch` /
//  `LogLevel` / `LogCategory`.
//

import Foundation

/// Niveles de severidad. La serialización al backend es lowercase
/// (`debug`, `info`, ...) para coincidir con Android.
public enum LogLevel: String, Sendable, Codable {
    case debug
    case info
    case warning
    case error
    case critical
}

/// Categorías conocidas. String-typed para mantener compat con backend que
/// puede agregar categorías nuevas sin actualizar el SDK.
public enum LogCategory {

    // Críticas (always on)
    public static let providerInitFailures   = "provider_init_failures"
    public static let sdkCrashes             = "sdk_crashes"

    // UX (toggle dinámico)
    public static let providerFailovers      = "provider_failovers"
    public static let contentShowFailures    = "content_show_failures"
    public static let lifecycleSequencing    = "lifecycle_sequencing"

    // Performance (toggle dinámico)
    public static let providerPerformance    = "provider_performance"
    public static let compatibilityMatrix    = "compatibility_matrix"

    // Debug (solo troubleshooting)
    public static let dependencyConflicts    = "dependency_conflicts"
    public static let backendConfigAnalysis  = "backend_config_analysis"

    // Pipelines / infra
    public static let eventTrackingHealth    = "event_tracking_health"
    public static let pusherInfrastructure   = "pusher_infrastructure"
    public static let lifecycleDiagnostic    = "lifecycle_diagnostic"
}

// MARK: - Wire models

/// Entrada individual de log que se envía al backend.
public struct LogEntry: Codable, Sendable, Equatable {

    public let id: String
    public let timestamp: Int64        // epoch ms
    public let category: String
    public let level: String           // lowercase de `LogLevel`
    public let data: [String: JSONValue]
    public let sdkVersion: String
    public let deviceId: String        // hash determinista de identifiers
    public let sessionId: String

    public init(
        id: String = UUID().uuidString,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        category: String,
        level: String,
        data: [String: JSONValue],
        sdkVersion: String,
        deviceId: String,
        sessionId: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.level = level
        self.data = data
        self.sdkVersion = sdkVersion
        self.deviceId = deviceId
        self.sessionId = sessionId
    }

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case category
        case level
        case data
        case sdkVersion = "sdk_version"
        case deviceId   = "device_id"
        case sessionId  = "session_id"
    }
}

/// Batch de logs que se sube al backend en un único POST.
public struct LogBatch: Codable, Sendable, Equatable {

    public let deviceId: String
    public let sessionId: String
    public let appId: String
    public let logs: [LogEntry]
    public let appVersion: String
    public let platform: String

    public init(
        deviceId: String,
        sessionId: String,
        appId: String,
        logs: [LogEntry],
        appVersion: String,
        platform: String = "ios"
    ) {
        self.deviceId = deviceId
        self.sessionId = sessionId
        self.appId = appId
        self.logs = logs
        self.appVersion = appVersion
        self.platform = platform
    }

    enum CodingKeys: String, CodingKey {
        case deviceId   = "device_id"
        case sessionId  = "session_id"
        case appId      = "app_id"
        case logs
        case appVersion = "app_version"
        case platform
    }
}

// MARK: - Runtime config

/// Wrapper runtime de la `LoggingConfigDTO` recibida del backend, con defaults.
///
/// La diferencia con `LoggingConfigDTO`: ésta es internal, mutable, y mapea
/// las categorías a su `CategoryRuntimeConfig`.
struct LoggingRuntimeConfig: Sendable {
    let enabled: Bool
    let endpoint: String?
    let categories: [String: CategoryRuntimeConfig]

    static let disabled = LoggingRuntimeConfig(enabled: false, endpoint: nil, categories: [:])

    static func from(_ dto: LoggingConfigDTO?) -> LoggingRuntimeConfig {
        guard let dto = dto, dto.enabled else { return .disabled }
        let cats = dto.categories.mapValues { CategoryRuntimeConfig.from($0) }
        return LoggingRuntimeConfig(enabled: true, endpoint: dto.endpoint, categories: cats)
    }
}

struct CategoryRuntimeConfig: Sendable, Equatable {
    let enabled: Bool
    let samplingRate: Double         // 0.0 .. 1.0
    let maxPerHour: Int

    static let disabled = CategoryRuntimeConfig(enabled: false, samplingRate: 0, maxPerHour: 0)
    static let alwaysOn = CategoryRuntimeConfig(enabled: true, samplingRate: 1.0, maxPerHour: 1000)

    static func from(_ dto: CategoryConfigDTO) -> CategoryRuntimeConfig {
        CategoryRuntimeConfig(
            enabled: dto.enabled,
            samplingRate: dto.samplingRate,
            maxPerHour: dto.maxPerHour ?? 100
        )
    }
}
