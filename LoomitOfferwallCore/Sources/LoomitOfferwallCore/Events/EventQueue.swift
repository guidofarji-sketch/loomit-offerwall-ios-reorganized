//
//  EventQueue.swift
//  LoomitOfferwallCore
//
//  Cola persistente de eventos. Paridad funcional con Android `SQLiteEventQueue`,
//  pero implementada como **JSON-on-disk** para no traer dependencias.
//
//  Trade-offs respecto a SQLite:
//  - Operaciones lockean toda la cola (file rewrite). OK para volúmenes bajos
//    típicos del SDK (cientos a miles de events/día).
//  - Para volúmenes altos en el futuro: migrar a SQLite via GRDB o similar.
//
//  Garantías:
//  - Thread-safe (actor).
//  - Persistente entre cold starts.
//  - Ordering: dequeue retorna primero por prioridad DESC, luego timestamp ASC.
//  - Drop policy: cuando `getSize() >= maxQueueSize`, al enqueuear se dropean
//    los eventos más viejos de menor prioridad.
//

import Foundation

/// Evento persistido con metadata de retry y prioridad.
public struct PersistedEvent: Sendable, Codable, Equatable, Identifiable {
    public let id: Int64
    public let event: OfferwallEvent
    public let timestamp: Int64           // epoch ms
    public let retryCount: Int
    public let priority: EventPriority

    public init(
        id: Int64,
        event: OfferwallEvent,
        timestamp: Int64,
        retryCount: Int,
        priority: EventPriority
    ) {
        self.id = id
        self.event = event
        self.timestamp = timestamp
        self.retryCount = retryCount
        self.priority = priority
    }
}

/// Operaciones de cola. Async porque escriben en disco.
public protocol EventQueue: Sendable {
    func enqueue(_ event: OfferwallEvent, priority: EventPriority) async -> Bool
    func dequeue(batchSize: Int) async -> [PersistedEvent]
    func markSent(ids: [Int64]) async -> Int
    /// Incrementa retry count. Retorna `false` si superó `maxRetries` (y se dropea).
    func incrementRetry(id: Int64, maxRetries: Int) async -> Bool
    /// Dropea eventos más viejos que `maxAge`.
    func prune(maxAge: TimeInterval) async -> Int
    func getSize() async -> Int
    func getSizeByPriority() async -> [EventPriority: Int]
    func clear() async -> Int
    func getAllForDebug() async -> [PersistedEvent]
    /// Peek all events without removing them (for debugging/monitoring).
    func peekAll() async -> [PersistedEvent]
}

// MARK: - FileEventQueue

/// Implementación de `EventQueue` basada en un único archivo JSON en disco.
///
/// Layout en disco:
/// ```
/// {
///   "next_id": 42,
///   "events": [PersistedEvent, PersistedEvent, ...]
/// }
/// ```
public actor FileEventQueue: EventQueue {

    private let fileURL: URL
    private let maxQueueSize: Int
    private let clock: @Sendable () -> Date

    private var nextId: Int64 = 1
    private var events: [PersistedEvent] = []
    private var loaded = false

    /// Init.
    /// - Parameters:
    ///   - fileURL: URL del archivo JSON.
    ///   - maxQueueSize: hard cap. Al enqueuear con la cola llena, se dropean
    ///                   los más viejos de menor prioridad.
    public init(
        fileURL: URL,
        maxQueueSize: Int = 1000,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileURL = fileURL
        self.maxQueueSize = maxQueueSize
        self.clock = clock
    }

    /// Conveniencia: crea una cola en `Application Support / loomit / event_queue.json`.
    public static func defaultLocation() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("loomit", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("event_queue.json")
    }

    // MARK: - EventQueue conformance

    public func enqueue(_ event: OfferwallEvent, priority: EventPriority) async -> Bool {
        await ensureLoaded()

        let now = Int64(clock().timeIntervalSince1970 * 1000)
        let persisted = PersistedEvent(
            id: nextId,
            event: event,
            timestamp: now,
            retryCount: 0,
            priority: priority
        )
        nextId &+= 1
        events.append(persisted)

        // Drop policy si excedimos el cap.
        if events.count > maxQueueSize {
            dropLowPriorityOverflow()
        }

        return persistToDisk()
    }

    public func dequeue(batchSize: Int) async -> [PersistedEvent] {
        await ensureLoaded()
        guard batchSize > 0 else { return [] }

        // Orden: priority DESC, timestamp ASC.
        let sorted = events.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.timestamp < rhs.timestamp
        }
        return Array(sorted.prefix(batchSize))
    }

    public func markSent(ids: [Int64]) async -> Int {
        await ensureLoaded()
        guard !ids.isEmpty else { return 0 }
        let toRemove = Set(ids)
        let before = events.count
        events.removeAll { toRemove.contains($0.id) }
        let removed = before - events.count
        if removed > 0 {
            _ = persistToDisk()
        }
        return removed
    }

    public func incrementRetry(id: Int64, maxRetries: Int) async -> Bool {
        await ensureLoaded()
        guard let idx = events.firstIndex(where: { $0.id == id }) else { return false }
        let current = events[idx]
        if current.retryCount >= maxRetries {
            events.remove(at: idx)
            _ = persistToDisk()
            return false
        }
        events[idx] = PersistedEvent(
            id: current.id,
            event: current.event,
            timestamp: current.timestamp,
            retryCount: current.retryCount + 1,
            priority: current.priority
        )
        _ = persistToDisk()
        return true
    }

    public func prune(maxAge: TimeInterval) async -> Int {
        await ensureLoaded()
        let cutoff = Int64((clock().timeIntervalSince1970 - maxAge) * 1000)
        let before = events.count
        events.removeAll { $0.timestamp < cutoff }
        let removed = before - events.count
        if removed > 0 {
            _ = persistToDisk()
        }
        return removed
    }

    public func getSize() async -> Int {
        await ensureLoaded()
        return events.count
    }

    public func getSizeByPriority() async -> [EventPriority: Int] {
        await ensureLoaded()
        var result: [EventPriority: Int] = [:]
        for e in events {
            result[e.priority, default: 0] += 1
        }
        return result
    }

    public func clear() async -> Int {
        await ensureLoaded()
        let count = events.count
        events.removeAll()
        _ = persistToDisk()
        return count
    }

    public func getAllForDebug() async -> [PersistedEvent] {
        await ensureLoaded()
        return events.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.timestamp < rhs.timestamp
        }
    }

    public func peekAll() async -> [PersistedEvent] {
        await ensureLoaded()
        return events.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.timestamp < rhs.timestamp
        }
    }

    // MARK: - Persistence

    private struct Wire: Codable {
        let nextId: Int64
        let events: [PersistedEvent]

        enum CodingKeys: String, CodingKey {
            case nextId = "next_id"
            case events
        }
    }

    private func ensureLoaded() async {
        guard !loaded else { return }
        defer { loaded = true }

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        guard let data = try? Data(contentsOf: fileURL) else { return }

        let decoder = JSONDecoder()
        guard let wire = try? decoder.decode(Wire.self, from: data) else {
            // Archivo corrupto; arrancamos vacíos.
            return
        }
        self.nextId = wire.nextId
        self.events = wire.events
    }

    @discardableResult
    private func persistToDisk() -> Bool {
        let wire = Wire(nextId: nextId, events: events)
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(wire) else { return false }
        do {
            // write atómicamente en una temp y luego rename.
            let tmp = fileURL.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            // mover temp → fileURL
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try FileManager.default.moveItem(at: tmp, to: fileURL)
            return true
        } catch {
            return false
        }
    }

    private func dropLowPriorityOverflow() {
        // Mantenemos los `maxQueueSize` mejores: priority DESC, timestamp DESC (nuevos primero).
        // Después del sort, los mejores están al principio. Eliminamos los últimos (peores).
        events.sort { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.timestamp > rhs.timestamp  // Nuevos primero
        }
        if events.count > maxQueueSize {
            events.removeLast(events.count - maxQueueSize)
        }
    }
}
