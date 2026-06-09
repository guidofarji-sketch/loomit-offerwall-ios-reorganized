//
//  ProductionLogger.swift
//  LoomitOfferwallCore
//
//  Punto de entrada del subsistema de logging.
//
//  Diferencia clave con Android: acá usamos un `actor` inyectable en lugar de
//  un `object` global. La instancia "compartida" se construye desde
//  `OfferwallSdk` después del primer `fetchConfig` exitoso.
//
//  Comportamiento (paridad con Android `ProductionLogger`):
//  - Buffer de hasta `maxBufferSize` entradas (default 10).
//  - Flush automático cuando: buffer lleno, level ∈ {error, critical},
//    categoría ∈ priorityCategories, o pasaron `flushInterval` segundos.
//  - sessionId aleatorio, persiste durante la vida del logger.
//

import Foundation

public actor ProductionLogger {

    // MARK: - Tunables

    private let maxBufferSize: Int
    private let flushInterval: TimeInterval

    /// Categorías que disparan flush inmediato al loguear.
    private let priorityCategories: Set<String> = [
        LogCategory.providerInitFailures,
        LogCategory.contentShowFailures,
        LogCategory.sdkCrashes,
        LogCategory.providerFailovers
    ]

    /// Levels que disparan flush inmediato.
    private let priorityLevels: Set<LogLevel> = [.error, .critical]

    // MARK: - State

    public let sessionId: String

    private let deviceHash: String
    private let appId: String
    private let appVersion: String
    private let uploader: LogUploader

    /// Config recibida del backend (puede actualizarse).
    private var config: LoggingRuntimeConfig

    /// Loggers por categoría (cacheados).
    private var categoryLoggers: [String: CategoryLogger] = [:]

    /// Buffer de entradas pendientes de flush.
    private var buffer: [LogEntry] = []

    private var lastFlushTime: Date

    private let clock: @Sendable () -> Date

    // MARK: - Init

    public init(
        deviceHash: String,
        appId: String,
        appVersion: String,
        uploader: LogUploader,
        config: LoggingConfigDTO? = nil,
        sessionId: String = UUID().uuidString,
        maxBufferSize: Int = 10,
        flushInterval: TimeInterval = 15,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.deviceHash = deviceHash
        self.appId = appId
        self.appVersion = appVersion
        self.uploader = uploader
        self.sessionId = sessionId
        self.maxBufferSize = maxBufferSize
        self.flushInterval = flushInterval
        self.config = LoggingRuntimeConfig.from(config)
        self.clock = clock
        self.lastFlushTime = clock()
    }

    // MARK: - Public API

    /// Actualiza la config (típicamente después de un nuevo `fetchConfig`).
    /// También se invoca desde `OfferwallSdk` cada vez que llega un nuevo
    /// `loggingConfig` del backend.
    public func updateConfig(_ newConfig: LoggingConfigDTO?) async {
        let runtime = LoggingRuntimeConfig.from(newConfig)
        self.config = runtime

        // Reconfigurar loggers existentes.
        for (name, logger) in categoryLoggers {
            let cat = runtime.categories[name] ?? .disabled
            await logger.updateConfig(cat)
        }
    }

    /// Obtiene (o crea) el logger para una categoría.
    public func category(_ name: String) async -> CategoryLogger {
        if let existing = categoryLoggers[name] {
            return existing
        }

        let cat = config.categories[name] ?? .disabled
        let session = sessionId
        let device = deviceHash

        // Capturamos `self` débilmente — actor's onLog es self-binding.
        // Para evitar reference cycle: `[weak self]` + check.
        let logger = CategoryLogger(
            categoryName: name,
            config: cat,
            deviceHash: device,
            sessionId: session,
            onLog: { [weak self] entry in
                await self?.addToBuffer(entry)
            },
            clock: clock
        )
        categoryLoggers[name] = logger
        return logger
    }

    /// Flushea el buffer al backend. Best-effort; no tira si falla la subida.
    public func flush() async {
        guard !buffer.isEmpty else { return }
        guard config.enabled else { buffer.removeAll(); return }

        let batch = LogBatch(
            deviceId: deviceHash,
            sessionId: sessionId,
            appId: appId,
            logs: buffer,
            appVersion: appVersion
        )
        buffer.removeAll()
        lastFlushTime = clock()

        try? await uploader.upload(batch)
    }

    /// Snapshot del buffer (sólo para tests / debug).
    public func bufferedCount() -> Int { buffer.count }

    // MARK: - Internal

    private func addToBuffer(_ entry: LogEntry) async {
        buffer.append(entry)

        let timeSinceFlush = clock().timeIntervalSince(lastFlushTime)
        let level = LogLevel(rawValue: entry.level)
        let isHighPriority = level.map { priorityLevels.contains($0) } ?? false
        let isPriorityCategory = priorityCategories.contains(entry.category)

        let shouldFlush =
            buffer.count >= maxBufferSize ||
            isHighPriority ||
            isPriorityCategory ||
            timeSinceFlush > flushInterval

        if shouldFlush {
            await flush()
        }
    }
}

// MARK: - Helper for deviceHash construction

extension ProductionLogger {
    /// Hash determinístico de un identifier (típicamente el XIFA), truncado a 16
    /// caracteres hexa. Paridad con Android `hashDeviceId`.
    public static func deviceHash(forIdentifier id: String) -> String {
        let bytes = Data(id.utf8)
        let digest = SHA256Hasher.hash(bytes)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }
}

// CryptoKit ya está disponible (lo usamos en ConfigCache); reusamos.
import CryptoKit

@available(iOS 13.0, *)
private enum SHA256Hasher {
    static func hash(_ data: Data) -> [UInt8] {
        Array(SHA256.hash(data: data))
    }
}
