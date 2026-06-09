//
//  ResilientBackendClient.swift
//  LoomitOfferwallCore
//
//  Decorator que combina CircuitBreaker + ConfigCache sobre un `BackendClient`.
//  Paridad con Android `ResilientBackendClient`.
//
//  Flujo:
//  1. Si el circuito está OPEN y no llegó `openDuration`, intentar cache fresh/stale.
//  2. Ejecutar request con circuit breaker (que ya envuelve un `BackendClient`,
//     el cual puede ser a su vez `RetryingBackendClient`).
//  3. En éxito: guardar en cache con `ConfigSource.network` y retornar.
//  4. En fallo: según `ConfigFetchPolicy`, fallback a cache fresh, luego stale.
//

import Foundation
import LoomitOfferwallAdapterAPI

public actor ResilientBackendClient: BackendClient {

    private let wrapped: BackendClient
    private let cache: ConfigCache
    private let breaker: CircuitBreaker
    private let policy: ConfigFetchPolicy
    private let clock: @Sendable () -> Date
    private let emergencyLoader: EmergencyConfigLoader

    public init(
        wrapping wrapped: BackendClient,
        cache: ConfigCache,
        breaker: CircuitBreaker,
        policy: ConfigFetchPolicy = .default,
        clock: @escaping @Sendable () -> Date = { Date() },
        emergencyLoader: EmergencyConfigLoader? = nil
    ) {
        self.wrapped = wrapped
        self.cache = cache
        self.breaker = breaker
        self.policy = policy
        self.clock = clock
        self.emergencyLoader = emergencyLoader ?? EmergencyConfigLoader()
    }

    // MARK: - BackendClient conformance

    public func fetchConfig(_ request: ConfigRequest) async throws -> ConfigResponse {
        let result = await fetchConfigDetailed(request)
        switch result {
        case .success(let cfg, _):
            return cfg
        case .failure(let err, _):
            throw err
        }
    }

    // MARK: - Detailed API

    /// Versión detallada: retorna `ConfigFetchResult` con `ConfigSource`.
    public func fetchConfigDetailed(_ request: ConfigRequest) async -> ConfigFetchResult {
        // 1. Intentar request real (con circuit breaker).
        // recordDebugConfigRequest se llama en HTTPBackendClient con el encoder correcto.
        do {
            let wrapped = self.wrapped
            let response = try await breaker.execute {
                try await wrapped.fetchConfig(request)
            }

            // Record response for debug panel.
            if let responseJson = try? JSONEncoder().encode(response),
               let responseJsonString = String(data: responseJson, encoding: .utf8) {
                await OfferwallSdk.shared.recordDebugConfigResponse(json: responseJsonString)
            }

            print("[LoomitOW] ResilientClient: network success")
            // Guardar en cache como NETWORK.
            let snapshot = makeSnapshot(config: response, source: .network)
            _ = cache.save(snapshot)

            return .success(response, source: .network)
        } catch {
            // 2. Fallback a cache si la política lo permite.
            print("[LoomitOW] ResilientClient: network error → \(error)")
            let ofErr: OfferwallError = mapToOfferwallError(error)

            if policy.useCacheIfFailed, let snapshot = cache.load() {
                let age = snapshot.age(now: clock())

                // 2a. Cache fresh
                if age < policy.cacheMaxAge {
                    print("[LoomitOW] ResilientClient: cache FRESH fallback (age=\(Int(age))s)")
                    await recordCachedResponseForDebug(snapshot.config)
                    return .success(snapshot.config, source: .cacheFresh)
                }

                // 2b. Cache stale (último recurso)
                if policy.allowStaleCache, age < policy.staleMaxAge {
                    print("[LoomitOW] ResilientClient: cache STALE fallback (age=\(Int(age))s)")
                    await recordCachedResponseForDebug(snapshot.config)
                    return .success(snapshot.config, source: .cacheStale)
                }
            }

            // 3. Emergency fallback
            if let emergencySnapshot = emergencyLoader.load() {
                print("[LoomitOW] ResilientClient: EMERGENCY fallback")
                await recordCachedResponseForDebug(emergencySnapshot.config)
                return .success(emergencySnapshot.config, source: .emergency)
            }
            
            // 4. Sin fallback.
            return .failure(error: ofErr, fallbackAvailable: false)
        }
    }

    private func recordCachedResponseForDebug(_ config: ConfigResponse) async {
        if let json = try? JSONEncoder().encode(config),
           let jsonString = String(data: json, encoding: .utf8) {
            await OfferwallSdk.shared.recordDebugConfigResponse(json: jsonString)
        }
    }

    /// Lee el snapshot actual del cache (para debugging / resilience state).
    public func cachedSnapshot() -> ConfigSnapshot? {
        cache.load()
    }

    /// Estado actual del circuit breaker.
    public func circuitState() async -> CircuitState {
        await breaker.getState()
    }

    /// Fuerza reset del circuit breaker (para tests/admin).
    public func resetCircuit() async {
        await breaker.reset()
    }

    // MARK: - Helpers

    private func makeSnapshot(config: ConfigResponse, source: ConfigSource) -> ConfigSnapshot {
        // checksum se recalcula al guardar; acá ponemos placeholder vacío.
        ConfigSnapshot(
            config: config,
            timestamp: clock(),
            source: source,
            checksum: ""
        )
    }

    private func mapToOfferwallError(_ error: Error) -> OfferwallError {
        if let of = error as? OfferwallError { return of }
        if error is CircuitOpenError {
            return .circuitOpenNoFallback
        }
        return .unknown(underlying: error.localizedDescription)
    }
}
