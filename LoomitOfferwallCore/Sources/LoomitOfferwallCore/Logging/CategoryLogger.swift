//
//  CategoryLogger.swift
//  LoomitOfferwallCore
//
//  Logger por categoría: aplica sampling determinista, rate-limit por hora
//  y sanitización de PII. Paridad con Android `CategoryLogger`.
//

import Foundation

public actor CategoryLogger {

    private let categoryName: String
    private var config: CategoryRuntimeConfig
    private let deviceHash: String
    private let sessionId: String
    private let sdkVersion: String
    private let onLog: @Sendable (LogEntry) async -> Void
    private let clock: @Sendable () -> Date

    /// `hour epoch (ms / 3_600_000) -> count`
    private var logCounts: [Int64: Int] = [:]

    init(
        categoryName: String,
        config: CategoryRuntimeConfig,
        deviceHash: String,
        sessionId: String,
        sdkVersion: String = SdkVersion.current,
        onLog: @escaping @Sendable (LogEntry) async -> Void,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.categoryName = categoryName
        self.config = config
        self.deviceHash = deviceHash
        self.sessionId = sessionId
        self.sdkVersion = sdkVersion
        self.onLog = onLog
        self.clock = clock
    }

    func updateConfig(_ newConfig: CategoryRuntimeConfig) {
        self.config = newConfig
    }

    public func debug(_ data: [String: JSONValue]) async    { await log(.debug,    data: data) }
    public func info(_ data: [String: JSONValue]) async     { await log(.info,     data: data) }
    public func warning(_ data: [String: JSONValue]) async  { await log(.warning,  data: data) }
    public func error(_ data: [String: JSONValue]) async    { await log(.error,    data: data) }
    public func critical(_ data: [String: JSONValue]) async { await log(.critical, data: data) }

    public func log(_ level: LogLevel, data: [String: JSONValue]) async {
        guard config.enabled else { return }
        guard shouldSample() else { return }
        guard checkRateLimit() else { return }

        let entry = LogEntry(
            category: categoryName,
            level: level.rawValue,
            data: Self.sanitize(data),
            sdkVersion: sdkVersion,
            deviceId: deviceHash,
            sessionId: sessionId
        )
        await onLog(entry)
    }

    // MARK: - Sampling

    /// Sampling **determinista** por hash(deviceHash + categoryName).
    /// Mantiene la misma decisión a lo largo de la vida del install,
    /// igual que en Android.
    private func shouldSample() -> Bool {
        let key = deviceHash + categoryName
        let hash = abs(Int(Self.djb2(key)))
        let normalized = Double(hash % 1000) / 1000.0
        return normalized < config.samplingRate
    }

    /// djb2 hash — determinístico y estable entre runs (a diferencia de
    /// `String.hashValue` que cambia entre procesos en Swift).
    static func djb2(_ str: String) -> Int64 {
        var hash: Int64 = 5381
        for byte in str.utf8 {
            hash = (hash &* 33) &+ Int64(byte)
        }
        return hash
    }

    // MARK: - Rate limit

    private func checkRateLimit() -> Bool {
        let nowMs = Int64(clock().timeIntervalSince1970 * 1000)
        let currentHour = nowMs / (60 * 60 * 1000)

        // Cleanup horas viejas (sólo retenemos current y current-1).
        logCounts = logCounts.filter { $0.key >= currentHour - 1 }

        let count = logCounts[currentHour, default: 0]
        if count >= config.maxPerHour { return false }
        logCounts[currentHour] = count + 1
        return true
    }

    // MARK: - Sanitization

    static func sanitize(_ data: [String: JSONValue]) -> [String: JSONValue] {
        let piiKeys: Set<String> = ["email", "phone", "address", "user_name", "password"]
        var result: [String: JSONValue] = [:]
        for (key, value) in data {
            if piiKeys.contains(key.lowercased()) { continue }
            result[key] = truncate(value)
        }
        return result
    }

    private static func truncate(_ value: JSONValue) -> JSONValue {
        switch value {
        case .string(let s) where s.count > 500:
            return .string(String(s.prefix(500)) + "...")
        case .array(let arr) where arr.count > 20:
            return .array(Array(arr.prefix(20)) + [.string("...")])
        default:
            return value
        }
    }
    
    // MARK: - Factory
    
    /// Returns a disabled logger that does nothing.
    public static func disabled() -> CategoryLogger {
        CategoryLogger(
            categoryName: "disabled",
            config: .disabled,
            deviceHash: "",
            sessionId: "",
            onLog: { _ in }
        )
    }
}
