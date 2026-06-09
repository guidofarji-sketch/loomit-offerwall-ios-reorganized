//
//  MockLogUploader.swift
//  LoomitOfferwallCoreTests
//

import Foundation
@testable import LoomitOfferwallCore

final class MockLogUploader: LogUploader, @unchecked Sendable {

    private let lock = NSLock()
    private var failuresRemaining: Int = 0
    private(set) var batches: [LogBatch] = []

    var batchCount: Int {
        lock.lock(); defer { lock.unlock() }
        return batches.count
    }

    var totalLogsUploaded: Int {
        lock.lock(); defer { lock.unlock() }
        return batches.reduce(0) { $0 + $1.logs.count }
    }

    func failNext(_ count: Int) {
        lock.lock(); defer { lock.unlock() }
        failuresRemaining = count
    }

    func upload(_ batch: LogBatch) async throws {
        lock.lock()
        let shouldFail = failuresRemaining > 0
        if shouldFail { failuresRemaining -= 1 }
        if !shouldFail { batches.append(batch) }
        lock.unlock()

        if shouldFail {
            throw NSError(domain: "MockLogUploader", code: 500)
        }
    }
}
