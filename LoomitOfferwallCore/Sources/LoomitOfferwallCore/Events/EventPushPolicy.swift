//
//  EventPushPolicy.swift
//  LoomitOfferwallCore
//
//  Política para `ResilientEventPusher`. Paridad con Android `EventPushPolicy`.
//

import Foundation

public struct EventPushPolicy: Sendable, Equatable {

    /// Cantidad de reintentos al pushear un evento.
    public let maxRetries: Int

    /// Delay inicial entre reintentos.
    public let initialDelay: TimeInterval

    /// Delay máximo (cap del backoff exponencial).
    public let maxDelay: TimeInterval

    /// Multiplier del backoff exponencial.
    public let backoffMultiplier: Double

    /// Si `true`, eventos que fallan luego de retries se persisten en disco.
    public let persistToDisk: Bool

    /// Tope de la cola en disco. Cuando se llena, se dropean los más viejos
    /// de menor prioridad.
    public let maxQueueSize: Int

    /// Tamaño del batch al flushear la cola.
    public let batchSize: Int

    /// Intervalo entre flushes de la cola persistente.
    public let flushInterval: TimeInterval

    /// Edad máxima de un evento en cola; se dropea si es más viejo.
    public let maxEventAge: TimeInterval

    public init(
        maxRetries: Int = 3,
        initialDelay: TimeInterval = 2,
        maxDelay: TimeInterval = 30,
        backoffMultiplier: Double = 2.0,
        persistToDisk: Bool = true,
        maxQueueSize: Int = 1000,
        batchSize: Int = 10,
        flushInterval: TimeInterval = 30,
        maxEventAge: TimeInterval = 7 * 24 * 60 * 60
    ) {
        self.maxRetries = maxRetries
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.backoffMultiplier = backoffMultiplier
        self.persistToDisk = persistToDisk
        self.maxQueueSize = maxQueueSize
        self.batchSize = batchSize
        self.flushInterval = flushInterval
        self.maxEventAge = maxEventAge
    }

    public static let `default` = EventPushPolicy()
}
