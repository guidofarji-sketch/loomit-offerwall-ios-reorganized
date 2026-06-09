//
//  ConfigResponse.swift
//  LoomitOfferwallCore
//
//  Wire response del endpoint POST /get-app-config.
//
//  Paridad con Android `ConfigResponse` en `BackendClient.kt`. Campos opcionales
//  son tolerantes: si el backend no manda algunos, el SDK funciona con defaults.
//

import Foundation

/// Respuesta del backend a `/get-app-config`.
///
/// **Contrato wire** compartido con Android y backend.
public struct ConfigResponse: Codable, Sendable, Equatable {

    /// Segmento asignado al usuario (ej: "high_value", "control"). Informativo.
    public let segment: String?

    /// Lista plana de providers configurados. **Legacy / fallback**: si el
    /// backend manda `offerwall.default_waterfall`, ese tiene precedencia.
    public let configurations: [ProviderPlanEntry]

    /// Bloque principal de offerwall (waterfall + overrides por ad_space).
    public let offerwall: OfferwallBlock?

    /// Configuraciones de safety/antifraud (opaco; lo consume el módulo
    /// `LoomitAntifraud` via reflection).
    public let safety: [String: JSONValue]?

    /// Singular: experimento principal asignado.
    public let experiment: [String: JSONValue]?

    /// Singular: A/B test principal asignado.
    public let abTest: [String: JSONValue]?

    /// Lista de experimentos múltiples (cuando aplica).
    public let experiments: [[String: JSONValue]]

    /// Lista de A/B tests múltiples (cuando aplica).
    public let abTests: [[String: JSONValue]]

    /// `true` si debug panel debe activarse para este usuario/dispositivo.
    public let debuggingStatus: Bool?

    /// Configuración del logger (categorías, sampling, rate-limit).
    public let loggingConfig: LoggingConfigDTO?

    /// Configuración de native ads (opaco; lo consume el módulo `LoomitNativeAds`).
    public let nativeAds: [String: JSONValue]?

    public init(
        segment: String? = nil,
        configurations: [ProviderPlanEntry] = [],
        offerwall: OfferwallBlock? = nil,
        safety: [String: JSONValue]? = nil,
        experiment: [String: JSONValue]? = nil,
        abTest: [String: JSONValue]? = nil,
        experiments: [[String: JSONValue]] = [],
        abTests: [[String: JSONValue]] = [],
        debuggingStatus: Bool? = nil,
        loggingConfig: LoggingConfigDTO? = nil,
        nativeAds: [String: JSONValue]? = nil
    ) {
        self.segment = segment
        self.configurations = configurations
        self.offerwall = offerwall
        self.safety = safety
        self.experiment = experiment
        self.abTest = abTest
        self.experiments = experiments
        self.abTests = abTests
        self.debuggingStatus = debuggingStatus
        self.loggingConfig = loggingConfig
        self.nativeAds = nativeAds
    }

    private enum CodingKeys: String, CodingKey {
        case segment
        case configurations
        case offerwall
        case safety
        case experiment
        case abTest          = "ab_test"
        case experiments
        case abTests         = "ab_tests"
        case debuggingStatus = "debugging"
        case loggingConfig   = "logging_config"
        case nativeAds       = "native_ads"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.segment         = try c.decodeIfPresent(String.self, forKey: .segment)
        self.configurations  = try c.decodeIfPresent([ProviderPlanEntry].self, forKey: .configurations) ?? []
        self.offerwall       = try c.decodeIfPresent(OfferwallBlock.self, forKey: .offerwall)
        self.safety          = try c.decodeIfPresent([String: JSONValue].self, forKey: .safety)
        self.experiment      = try c.decodeIfPresent([String: JSONValue].self, forKey: .experiment)
        self.abTest          = try c.decodeIfPresent([String: JSONValue].self, forKey: .abTest)
        self.experiments     = try c.decodeIfPresent([[String: JSONValue]].self, forKey: .experiments) ?? []
        self.abTests         = try c.decodeIfPresent([[String: JSONValue]].self, forKey: .abTests) ?? []
        self.debuggingStatus = try c.decodeIfPresent(Bool.self, forKey: .debuggingStatus)
        self.loggingConfig   = try c.decodeIfPresent(LoggingConfigDTO.self, forKey: .loggingConfig)
        self.nativeAds       = try c.decodeIfPresent([String: JSONValue].self, forKey: .nativeAds)
    }
}

// MARK: - LoggingConfigDTO

/// DTO wire del bloque `logging_config`. El logger interno transforma esto a
/// su modelo runtime. Mantenemos los nombres del backend.
public struct LoggingConfigDTO: Codable, Sendable, Equatable {

    public let enabled: Bool
    public let endpoint: String?
    public let batchSize: Int?
    public let flushIntervalMs: Int?
    public let categories: [String: CategoryConfigDTO]

    public init(
        enabled: Bool = false,
        endpoint: String? = nil,
        batchSize: Int? = nil,
        flushIntervalMs: Int? = nil,
        categories: [String: CategoryConfigDTO] = [:]
    ) {
        self.enabled = enabled
        self.endpoint = endpoint
        self.batchSize = batchSize
        self.flushIntervalMs = flushIntervalMs
        self.categories = categories
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case endpoint
        case batchSize        = "batch_size"
        case flushIntervalMs  = "flush_interval_ms"
        case categories
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled         = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.endpoint        = try c.decodeIfPresent(String.self, forKey: .endpoint)
        self.batchSize       = try c.decodeIfPresent(Int.self, forKey: .batchSize)
        self.flushIntervalMs = try c.decodeIfPresent(Int.self, forKey: .flushIntervalMs)
        self.categories      = try c.decodeIfPresent([String: CategoryConfigDTO].self, forKey: .categories) ?? [:]
    }
}

public struct CategoryConfigDTO: Codable, Sendable, Equatable {

    public let enabled: Bool
    public let samplingRate: Double
    public let maxPerHour: Int?
    public let minLevel: String?

    public init(
        enabled: Bool = false,
        samplingRate: Double = 1.0,
        maxPerHour: Int? = nil,
        minLevel: String? = nil
    ) {
        self.enabled = enabled
        self.samplingRate = samplingRate
        self.maxPerHour = maxPerHour
        self.minLevel = minLevel
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case samplingRate = "sampling_rate"
        case maxPerHour   = "max_per_hour"
        case minLevel     = "min_level"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled      = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.samplingRate = try c.decodeIfPresent(Double.self, forKey: .samplingRate) ?? 1.0
        self.maxPerHour   = try c.decodeIfPresent(Int.self, forKey: .maxPerHour)
        self.minLevel     = try c.decodeIfPresent(String.self, forKey: .minLevel)
    }
}

// MARK: - Experiment collection (paridad con Android)

extension ConfigResponse {

    /// Colecciona todos los payloads de experimentos del config response (paridad con Android)
    /// Convierte JSONValue a [String: Any] para ser usado por OfferwallSdk
    func collectExperimentPayloads() -> [[String: Any]] {
        var payloads: [[String: Any]] = []

        // Singular experiment
        if let exp = experiment {
            payloads.append(convertJSONValueToDict(exp))
        }

        // Singular abTest
        if let abTest = abTest {
            payloads.append(convertJSONValueToDict(abTest))
        }

        // Lista de experiments
        for exp in experiments {
            payloads.append(convertJSONValueToDict(exp))
        }

        // Lista de abTests
        for abTest in abTests {
            payloads.append(convertJSONValueToDict(abTest))
        }

        return payloads
    }

    /// Convierte [String: JSONValue] a [String: Any] (paridad con Android)
    private func convertJSONValueToDict(_ dict: [String: JSONValue]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dict {
            result[key] = convertJSONValueToAny(value)
        }
        return result
    }

    /// Convierte JSONValue a Any (paridad con Android)
    private func convertJSONValueToAny(_ value: JSONValue) -> Any {
        switch value {
        case .string(let str):
            return str
        case .int(let num):
            return num
        case .double(let num):
            return num
        case .bool(let bool):
            return bool
        case .object(let obj):
            var dict: [String: Any] = [:]
            for (key, val) in obj {
                dict[key] = convertJSONValueToAny(val)
            }
            return dict
        case .array(let arr):
            return arr.map { convertJSONValueToAny($0) }
        case .null:
            return NSNull()
        }
    }
}
