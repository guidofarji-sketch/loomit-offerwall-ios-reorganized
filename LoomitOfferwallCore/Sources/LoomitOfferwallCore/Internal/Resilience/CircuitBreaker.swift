//
//  CircuitBreaker.swift
//  LoomitOfferwallCore
//
//  Circuit breaker de 3 estados (CLOSED/OPEN/HALF_OPEN) para evitar
//  cascading failures contra el backend. Paridad con Android
//  `com.example.offerwallsdk.resilience.CircuitBreaker`.
//

import Foundation

/// Estados del circuit breaker.
///
/// - `closed`: operación normal, requests pasan
/// - `open`: failing fast, requests se rechazan de inmediato
/// - `halfOpen`: probando si el servicio se recuperó (requests limitados)
public enum CircuitState: String, Sendable {
    case closed = "CLOSED"
    case open = "OPEN"
    case halfOpen = "HALF_OPEN"
}

/// Configuración del comportamiento del circuit breaker.
public struct CircuitBreakerConfig: Sendable, Equatable {

    /// Cantidad de fallos consecutivos antes de abrir el circuito.
    public let failureThreshold: Int

    /// Cantidad de éxitos consecutivos en `halfOpen` para cerrar el circuito.
    public let successThreshold: Int

    /// Cuánto tiempo queda en `open` antes de intentar `halfOpen`.
    public let openDuration: TimeInterval

    /// Máximo de test attempts permitidos en `halfOpen`.
    public let halfOpenMaxAttempts: Int

    public init(
        failureThreshold: Int = 5,
        successThreshold: Int = 2,
        openDuration: TimeInterval = 60,
        halfOpenMaxAttempts: Int = 3
    ) {
        self.failureThreshold = failureThreshold
        self.successThreshold = successThreshold
        self.openDuration = openDuration
        self.halfOpenMaxAttempts = halfOpenMaxAttempts
    }

    public static let `default` = CircuitBreakerConfig()
}

/// Error lanzado cuando el circuito está en `open` y se rechaza el request.
public struct CircuitOpenError: Error, CustomStringConvertible, Sendable {
    public let name: String
    public let reason: String

    public var description: String {
        "CircuitOpenError[\(name)]: \(reason)"
    }
}

/// Snapshot de métricas para monitoring/diagnóstico.
public struct CircuitBreakerMetrics: Sendable, Equatable {
    public let name: String
    public let state: CircuitState
    public let failureCount: Int
    public let successCount: Int
    public let lastFailureTime: Date?
    public let config: CircuitBreakerConfig
}

/// Circuit breaker actor-isolated. Thread-safe.
///
/// Transiciones:
/// 1. CLOSED → OPEN: tras `failureThreshold` fallos consecutivos
/// 2. OPEN → HALF_OPEN: tras `openDuration` elapsed
/// 3. HALF_OPEN → CLOSED: tras `successThreshold` éxitos consecutivos
/// 4. HALF_OPEN → OPEN: en cualquier fallo
public actor CircuitBreaker {

    private let name: String
    private let config: CircuitBreakerConfig
    private let onStateChange: (@Sendable (CircuitState, CircuitState) -> Void)?

    private var state: CircuitState = .closed
    private var failureCount: Int = 0
    private var successCount: Int = 0
    private var lastFailureTime: Date?
    private var halfOpenAttempts: Int = 0

    /// Clock injectable para tests (default: `Date()`).
    private let clock: @Sendable () -> Date

    public init(
        name: String,
        config: CircuitBreakerConfig = .default,
        clock: @escaping @Sendable () -> Date = { Date() },
        onStateChange: (@Sendable (CircuitState, CircuitState) -> Void)? = nil
    ) {
        self.name = name
        self.config = config
        self.clock = clock
        self.onStateChange = onStateChange
    }

    // MARK: - Public API

    /// Ejecuta una operación protegida por el circuit breaker.
    ///
    /// - Throws: `CircuitOpenError` si el circuito rechaza el request, o cualquier
    ///           error propagado de la operación.
    public func execute<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        switch state {
        case .open:
            if shouldAttemptReset() {
                transition(to: .halfOpen)
                return try await executeAndRecord(operation)
            } else {
                throw CircuitOpenError(name: name, reason: "circuit is OPEN")
            }

        case .halfOpen:
            halfOpenAttempts += 1
            if halfOpenAttempts > config.halfOpenMaxAttempts {
                throw CircuitOpenError(name: name, reason: "max HALF_OPEN attempts exceeded")
            }
            return try await executeAndRecord(operation)

        case .closed:
            return try await executeAndRecord(operation)
        }
    }

    /// Resetea manualmente el circuit breaker al estado `closed`.
    /// Usar con cuidado; típicamente para tests u override administrativo.
    public func reset() {
        state = .closed
        resetCounters()
        lastFailureTime = nil
    }

    public func getState() -> CircuitState { state }

    public func getMetrics() -> CircuitBreakerMetrics {
        CircuitBreakerMetrics(
            name: name,
            state: state,
            failureCount: failureCount,
            successCount: successCount,
            lastFailureTime: lastFailureTime,
            config: config
        )
    }

    // MARK: - Internal state management

    private func executeAndRecord<T: Sendable>(_ op: @Sendable () async throws -> T) async throws -> T {
        do {
            let result = try await op()
            onSuccess()
            return result
        } catch {
            onFailure(error)
            throw error
        }
    }

    private func onSuccess() {
        switch state {
        case .halfOpen:
            successCount += 1
            if successCount >= config.successThreshold {
                transition(to: .closed)
                resetCounters()
            }

        case .closed:
            if failureCount > 0 {
                failureCount = 0
            }

        case .open:
            // Inesperado; no hacemos nada.
            break
        }
    }

    private func onFailure(_ error: Error) {
        lastFailureTime = clock()

        switch state {
        case .closed:
            failureCount += 1
            if failureCount >= config.failureThreshold {
                transition(to: .open)
            }

        case .halfOpen:
            transition(to: .open)
            resetCounters()

        case .open:
            // Esperado; no cambia nada.
            break
        }
    }

    private func shouldAttemptReset() -> Bool {
        guard let lastFailure = lastFailureTime else { return true }
        let elapsed = clock().timeIntervalSince(lastFailure)
        return elapsed >= config.openDuration
    }

    private func transition(to newState: CircuitState) {
        let oldState = state
        guard oldState != newState else { return }
        state = newState
        if newState == .halfOpen {
            halfOpenAttempts = 0
        }
        onStateChange?(oldState, newState)
    }

    private func resetCounters() {
        failureCount = 0
        successCount = 0
        halfOpenAttempts = 0
    }
}
