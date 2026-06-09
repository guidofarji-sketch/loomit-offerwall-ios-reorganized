//
//  RetryingBackendClient.swift
//  LoomitOfferwallCore
//
//  Decorator que aplica `RetryPolicy` a cualquier `BackendClient`.
//
//  No reintenta ante:
//  - Errores no-retriables (4xx que no sean 408/429, decoding, configuración).
//
//  Sí reintenta ante:
//  - 5xx
//  - 408, 429
//  - timeouts
//  - backendUnreachable (network)
//

import Foundation
import LoomitOfferwallAdapterAPI

/// Wrapper que añade retry con exponential backoff a un `BackendClient`.
public final class RetryingBackendClient: BackendClient {

    private let inner: BackendClient
    private let policy: RetryPolicy
    private let sleeper: @Sendable (TimeInterval) async -> Void

    public init(
        wrapping inner: BackendClient,
        policy: RetryPolicy = .default,
        sleeper: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.inner = inner
        self.policy = policy
        self.sleeper = sleeper
    }

    public func fetchConfig(_ request: ConfigRequest) async throws -> ConfigResponse {
        var lastError: Error = OfferwallError.unknown(underlying: "no attempts made")

        for attempt in 1...policy.maxAttempts {
            let delay = policy.delayBefore(attempt: attempt)
            if delay > 0 {
                await sleeper(delay)
            }

            do {
                return try await inner.fetchConfig(request)
            } catch let error as OfferwallError where !Self.isRetriable(error) {
                throw error
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError
    }

    /// Decide si un `OfferwallError` justifica reintentar.
    static func isRetriable(_ error: OfferwallError) -> Bool {
        switch error {
        case .backendUnreachable, .timeout:
            return true
        case .backendHTTPError(let statusCode, _):
            // 5xx, 408 (Request Timeout), 429 (Too Many Requests)
            return statusCode >= 500 || statusCode == 408 || statusCode == 429
        case .backendDecodingError, .invalidConfiguration, .missingApiKey,
             .notInitialized, .invalidState, .cancelled,
             .providerNotRegistered, .providerInitializationFailed,
             .providerUnavailable, .providerShowFailed, .waterfallExhausted,
             .circuitOpenNoFallback, .unknown:
            return false
        }
    }
}
