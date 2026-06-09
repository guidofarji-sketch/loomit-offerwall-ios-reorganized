//
//  MockEventPusher.swift
//  LoomitOfferwallCoreTests
//

import Foundation
@testable import LoomitOfferwallCore

/// Pusher mock thread-safe que captura eventos y permite scriptear fallos.
final class MockEventPusher: OfferwallEventPusher, @unchecked Sendable {

    private let lock = NSLock()
    private var failuresRemaining: Int = 0
    private(set) var pushed: [OfferwallEvent] = []
    private(set) var attempts: Int = 0

    /// Si > 0, las próximas N llamadas fallan.
    func failNext(_ count: Int) {
        lock.lock(); defer { lock.unlock() }
        failuresRemaining = count
    }

    var pushedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return pushed.count
    }

    func push(_ event: OfferwallEvent) async throws {
        lock.lock()
        attempts += 1
        let shouldFail = failuresRemaining > 0
        if shouldFail { failuresRemaining -= 1 }
        if !shouldFail { pushed.append(event) }
        lock.unlock()

        if shouldFail {
            throw NSError(domain: "MockEventPusher", code: 500)
        }
    }
}
