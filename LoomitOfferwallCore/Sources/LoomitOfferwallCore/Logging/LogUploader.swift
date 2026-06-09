//
//  LogUploader.swift
//  LoomitOfferwallCore
//
//  Subida HTTP de batches de logs. Endpoint dinámico (lo manda el backend en
//  `loggingConfig.endpoint`). Paridad con Android `BackendLogUploader`.
//

import Foundation

public protocol LogUploader: Sendable {
    func upload(_ batch: LogBatch) async throws
}

/// Implementación basada en `URLSession`.
///
/// Si el endpoint no está configurado (el backend no mandó `logging_config.endpoint`),
/// `upload` no-op silenciosamente.
public final class HTTPLogUploader: LogUploader, @unchecked Sendable {

    private let session: URLSession
    private let timeout: TimeInterval
    private let encoder: JSONEncoder
    private let lock = NSLock()
    private var apiKey: String
    private var endpoint: URL?

    public init(
        apiKey: String,
        endpoint: URL? = nil,
        session: URLSession = .shared,
        timeout: TimeInterval = 10
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.session = session
        self.timeout = timeout
        self.encoder = JSONEncoder()
    }

    public func updateEndpoint(_ newEndpoint: URL?) {
        lock.lock(); defer { lock.unlock() }
        self.endpoint = newEndpoint
    }

    public func updateApiKey(_ newApiKey: String) {
        lock.lock(); defer { lock.unlock() }
        self.apiKey = newApiKey
    }

    public func upload(_ batch: LogBatch) async throws {
        // Snapshot bajo lock
        let (endpointSnapshot, apiKeySnapshot) = await withCheckedContinuation { continuation in
            lock.lock()
            let endpoint = self.endpoint
            let apiKey = self.apiKey
            lock.unlock()
            continuation.resume(returning: (endpoint, apiKey))
        }

        guard let url = endpointSnapshot else {
            // Backend no configuró endpoint; no es un error — sólo no subimos.
            return
        }

        let body = try encoder.encode(batch)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(apiKeySnapshot, forHTTPHeaderField: "x-api-key")
        req.setValue(SdkVersion.current, forHTTPHeaderField: "X-SDK-Version")
        req.httpBody = body

        let (_, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // No tirar excepciones por logs; es best-effort.
            // La política de Android es la misma: no crashear el SDK por logs.
            return
        }
    }
}
