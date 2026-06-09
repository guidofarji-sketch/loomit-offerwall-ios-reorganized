//
//  FileEventQueueTests.swift
//  LoomitOfferwallCoreTests
//

import XCTest
@testable import LoomitOfferwallCore

final class FileEventQueueTests: XCTestCase {

    private var tempDir: URL!
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("loomit.tests.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        fileURL = tempDir.appendingPathComponent("queue.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeEvent(type: String = "content_show", id: String = "x") -> OfferwallEvent {
        OfferwallEvent(
            type: type,
            provider: "loomit",
            xifa: "xifa-1",
            appId: "app-1",
            platform: "ios",
            country: "AR",
            appVersion: "1.0",
            sdkVersion: "0.1",
            deviceModel: "iPhone16,1",
            osVersion: "17.4",
            lifecycleId: 1,
            timestampMs: 1_000,
            data: ["k": .string(id)]
        )
    }

    func test_enqueue_then_dequeue_returnsEvent() async {
        let q = FileEventQueue(fileURL: fileURL)
        _ = await q.enqueue(makeEvent(), priority: .normal)

        let batch = await q.dequeue(batchSize: 10)
        XCTAssertEqual(batch.count, 1)
        XCTAssertEqual(batch[0].event.type, "content_show")
    }

    func test_dequeue_orderByPriority_thenTimestamp() async {
        let clock = TestClock(Date(timeIntervalSince1970: 1_000))
        let q = FileEventQueue(fileURL: fileURL, clock: { clock.now })

        // Inserto 3 normal con timestamps incrementales
        _ = await q.enqueue(makeEvent(type: "n1"), priority: .normal)
        clock.advance(1)
        _ = await q.enqueue(makeEvent(type: "n2"), priority: .normal)
        clock.advance(1)
        // 1 critical después: debería salir primero
        _ = await q.enqueue(makeEvent(type: "c1"), priority: .critical)

        let batch = await q.dequeue(batchSize: 10)
        XCTAssertEqual(batch.map { $0.event.type }, ["c1", "n1", "n2"])
    }

    func test_markSent_removesFromQueue() async {
        let q = FileEventQueue(fileURL: fileURL)
        _ = await q.enqueue(makeEvent(type: "a"), priority: .normal)
        _ = await q.enqueue(makeEvent(type: "b"), priority: .normal)

        let batch = await q.dequeue(batchSize: 10)
        let firstId = batch[0].id
        let removed = await q.markSent(ids: [firstId])
        XCTAssertEqual(removed, 1)

        let remaining = await q.getSize()
        XCTAssertEqual(remaining, 1)
    }

    func test_incrementRetry_dropsAfterMaxRetries() async {
        let q = FileEventQueue(fileURL: fileURL)
        _ = await q.enqueue(makeEvent(), priority: .normal)
        let id = (await q.dequeue(batchSize: 1))[0].id

        // 1st: 0 → 1
        var ok = await q.incrementRetry(id: id, maxRetries: 2)
        XCTAssertTrue(ok)
        // 2nd: 1 → 2
        ok = await q.incrementRetry(id: id, maxRetries: 2)
        XCTAssertTrue(ok)
        // 3rd: count == max → drop
        ok = await q.incrementRetry(id: id, maxRetries: 2)
        XCTAssertFalse(ok)

        let size = await q.getSize()
        XCTAssertEqual(size, 0)
    }

    func test_persistence_acrossInstances() async {
        let q1 = FileEventQueue(fileURL: fileURL)
        _ = await q1.enqueue(makeEvent(type: "persisted"), priority: .high)

        // Nueva instancia mismo archivo
        let q2 = FileEventQueue(fileURL: fileURL)
        let batch = await q2.dequeue(batchSize: 10)
        XCTAssertEqual(batch.count, 1)
        XCTAssertEqual(batch[0].event.type, "persisted")
    }

    func test_prune_removesOldEvents() async {
        let clock = TestClock(Date(timeIntervalSince1970: 10_000))
        let q = FileEventQueue(fileURL: fileURL, clock: { clock.now })
        _ = await q.enqueue(makeEvent(type: "old"), priority: .normal)
        clock.advance(100)
        _ = await q.enqueue(makeEvent(type: "new"), priority: .normal)

        // Prune > 50s atrás → "old" se va
        let pruned = await q.prune(maxAge: 50)
        XCTAssertEqual(pruned, 1)
        let remaining = await q.dequeue(batchSize: 10)
        XCTAssertEqual(remaining.map { $0.event.type }, ["new"])
    }

    func test_overflow_dropsLowPriority() async {
        let q = FileEventQueue(fileURL: fileURL, maxQueueSize: 2)
        _ = await q.enqueue(makeEvent(type: "n1"), priority: .normal)
        _ = await q.enqueue(makeEvent(type: "n2"), priority: .normal)
        _ = await q.enqueue(makeEvent(type: "c1"), priority: .critical)

        let size = await q.getSize()
        XCTAssertEqual(size, 2)

        // El critical debe estar (porque es prioridad alta)
        let batch = await q.dequeue(batchSize: 10)
        XCTAssertTrue(batch.map { $0.event.type }.contains("c1"))
    }

    func test_clear_emptiesQueue() async {
        let q = FileEventQueue(fileURL: fileURL)
        _ = await q.enqueue(makeEvent(), priority: .normal)
        _ = await q.enqueue(makeEvent(), priority: .normal)

        let cleared = await q.clear()
        XCTAssertEqual(cleared, 2)
        let size = await q.getSize()
        XCTAssertEqual(size, 0)
    }
}
