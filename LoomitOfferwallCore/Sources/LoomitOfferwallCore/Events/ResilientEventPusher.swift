//
//  ResilientEventPusher.swift
//  LoomitOfferwallCore
//
//  Decorator de un `OfferwallEventPusher` que agrega:
//  - Retry exponencial inmediato (in-memory)
//  - Persistencia en disco si todos los retries fallan
//  - Background flush periódico de la cola
//  - Auto-prune de eventos vencidos
//
//  Paridad funcional con Android `ResilientEventPusher`.
//

import Foundation
import LoomitOfferwallAdapterAPI

public actor ResilientEventPusher: OfferwallEventPusher {

    private let delegate: OfferwallEventPusher
    private let queue: EventQueue
    private let policy: EventPushPolicy
    private let clock: @Sendable () -> Date

    private var flushTask: Task<Void, Never>?
    private var pruneTask: Task<Void, Never>?

    /// Si `true`, las llamadas a `push(_:)` esperan a que el retry termine antes
    /// de retornar. Útil en tests; en runtime normal usamos `pushFireAndForget`.
    private let synchronousPush: Bool

    public init(
        delegate: OfferwallEventPusher,
        queue: EventQueue,
        policy: EventPushPolicy = .default,
        synchronousPush: Bool = false,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.delegate = delegate
        self.queue = queue
        self.policy = policy
        self.synchronousPush = synchronousPush
        self.clock = clock
    }

    deinit {
        flushTask?.cancel()
        pruneTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Arranca los background tasks de flush y prune.
    public func start() {
        if flushTask == nil {
            flushTask = Task { [weak self] in
                await self?.flushLoop()
            }
        }
        if pruneTask == nil {
            pruneTask = Task { [weak self] in
                await self?.pruneLoop()
            }
        }
    }

    /// Cancela los background tasks.
    public func stop() {
        flushTask?.cancel()
        flushTask = nil
        pruneTask?.cancel()
        pruneTask = nil
    }

    // MARK: - OfferwallEventPusher

    public func push(_ event: OfferwallEvent) async throws {
        if synchronousPush {
            await pushWithRetryAndPersist(event)
        } else {
            // Fire-and-forget: lanzamos un task hijo y retornamos.
            Task { [weak self] in
                await self?.pushWithRetryAndPersist(event)
            }
        }
    }

    // MARK: - Internal

    private func pushWithRetryAndPersist(_ event: OfferwallEvent) async {
        let priority = EventPriority.from(eventType: event.type)
        let success = await pushWithRetry(event)

        if !success && policy.persistToDisk {
            _ = await queue.enqueue(event, priority: priority)
        }
    }

    /// Push con retry. Retorna `true` si el delegate aceptó el evento.
    private func pushWithRetry(_ event: OfferwallEvent) async -> Bool {
        var attempt = 0
        var delay = policy.initialDelay

        while attempt < policy.maxRetries {
            attempt += 1
            do {
                try await delegate.push(event)
                return true
            } catch {
                if attempt >= policy.maxRetries { break }
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay = min(delay * policy.backoffMultiplier, policy.maxDelay)
            }
        }
        return false
    }

    /// Flushea hasta `batchSize` eventos persistidos en cola. Llamable a demanda
    /// (también lo invoca el background loop).
    @discardableResult
    public func flushOnce() async -> Int {
        let batch = await queue.dequeue(batchSize: policy.batchSize)
        guard !batch.isEmpty else { return 0 }

        var sentIds: [Int64] = []
        for persisted in batch {
            do {
                try await delegate.push(persisted.event)
                sentIds.append(persisted.id)
            } catch {
                _ = await queue.incrementRetry(id: persisted.id, maxRetries: policy.maxRetries)
            }
        }
        if !sentIds.isEmpty {
            _ = await queue.markSent(ids: sentIds)
        }
        return sentIds.count
    }

    private func flushLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(policy.flushInterval * 1_000_000_000))
            if Task.isCancelled { return }
            _ = await flushOnce()
        }
    }

    private func pruneLoop() async {
        // Cada 24h.
        let day: TimeInterval = 24 * 3600
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(day * 1_000_000_000))
            if Task.isCancelled { return }
            _ = await queue.prune(maxAge: policy.maxEventAge)
        }
    }

    // MARK: - Diagnostics

    public func queueSize() async -> Int {
        await queue.getSize()
    }

    public func queueSizeByPriority() async -> [EventPriority: Int] {
        await queue.getSizeByPriority()
    }
}
