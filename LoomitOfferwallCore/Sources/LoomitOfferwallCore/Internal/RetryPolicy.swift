//
//  RetryPolicy.swift
//  LoomitOfferwallCore
//
//  Política de retry para operaciones de red.
//
//  Etapa 4: implementación simple con exponential backoff.
//  Etapa 4-bis (futura): integrar con CircuitBreaker para evitar reintentar
//  cuando el circuito está abierto.
//

import Foundation

/// Configuración de retry. Inmutable y `Sendable`.
public struct RetryPolicy: Sendable, Equatable {

    /// Máximo de intentos (incluye el primero). 1 = no retry.
    public let maxAttempts: Int

    /// Delay inicial entre el primer fail y el primer retry, en segundos.
    public let initialDelay: TimeInterval

    /// Delay máximo, en segundos. Cap del backoff exponencial.
    public let maxDelay: TimeInterval

    /// Multiplicador del backoff. `delay_n = min(initialDelay * multiplier^(n-1), maxDelay)`.
    public let multiplier: Double

    /// Jitter (0...1) — % aleatorio sumado al delay para evitar thundering-herd.
    public let jitter: Double

    public init(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 10.0,
        multiplier: Double = 2.0,
        jitter: Double = 0.2
    ) {
        precondition(maxAttempts >= 1, "maxAttempts must be >= 1")
        precondition(initialDelay >= 0, "initialDelay must be >= 0")
        precondition(maxDelay >= initialDelay, "maxDelay must be >= initialDelay")
        precondition(multiplier >= 1.0, "multiplier must be >= 1.0")
        precondition(jitter >= 0 && jitter <= 1, "jitter must be in [0, 1]")

        self.maxAttempts = maxAttempts
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.multiplier = multiplier
        self.jitter = jitter
    }

    /// Default sensato para fetchConfig.
    public static let `default` = RetryPolicy()

    /// No retry — útil para tests o operaciones que no deben reintentar.
    public static let none = RetryPolicy(maxAttempts: 1)

    /// Calcula el delay antes del intento `attempt` (1-indexed).
    /// `attempt == 1` ⇒ 0 (es el primer intento, no hay delay previo).
    /// `attempt == 2` ⇒ initialDelay (con jitter).
    /// `attempt == 3` ⇒ initialDelay * multiplier (cap maxDelay) (con jitter).
    public func delayBefore(attempt: Int, randomSource: () -> Double = { Double.random(in: 0...1) }) -> TimeInterval {
        guard attempt > 1 else { return 0 }

        let exponent = Double(attempt - 2)  // attempt 2 ⇒ exponent 0
        let base = min(initialDelay * pow(multiplier, exponent), maxDelay)
        let jitterAmount = base * jitter * randomSource()
        return base + jitterAmount
    }
}
