//
//  ResilientEventPusherTests.swift
//  LoomitOfferwallCoreTests
//

import XCTest
@testable import LoomitOfferwallCore

final class ResilientEventPusherTests: XCTestCase {

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

    private func makeEvent(_ type: String = "content_show") -> OfferwallEvent {
        OfferwallEvent(
            type: type,
            provider: "loomit",
            xifa: "x",
            appId: "a",
            platform: "ios",
            country: nil,
            appVersion: nil,
            sdkVersion: nil,
            deviceModel: "m",
            osVersion: "o",
            lifecycleId: 0,
            timestampMs: 1,
            data: [:]
        )
    }

    private func policyFast() -> EventPushPolicy {
        EventPushPolicy(
            maxRetries: 2,
            initialDelay: 0.001,
            maxDelay: 0.001,
            backoffMultiplier: 1,
            persistToDisk: true,
            maxQueueSize: 100,
            batchSize: 10,
            flushInterval: 3600,   // disabled effectively
            maxEventAge: 7 * 24 * 3600
        )
    }

    func test_successfulPush_doesNotPersist() async {
        let mock = MockEventPusher()
        let queue = FileEventQueue(fileURL: fileURL)
        let pusher = ResilientEventPusher(
            delegate: mock,
            queue: queue,
            policy: policyFast(),
            synchronousPush: true
        )

        try? await pusher.push(makeEvent("rewarded"))

        XCTAssertEqual(mock.pushedCount, 1)
        let queueSize = await queue.getSize()
        XCTAssertEqual(queueSize, 0, "successful push must not persist")
    }

    func test_failedPush_afterRetries_persistsToQueue() async {
        let mock = MockEventPusher()
        mock.failNext(10)  // todos los intentos fallan
        let queue = FileEventQueue(fileURL: fileURL)
        let pusher = ResilientEventPusher(
            delegate: mock,
            queue: queue,
            policy: policyFast(),
            synchronousPush: true
        )

        try? await pusher.push(makeEvent("content_show"))

        XCTAssertEqual(mock.pushedCount, 0, "no event reached the delegate successfully")
        let queueSize = await queue.getSize()
        XCTAssertEqual(queueSize, 1, "event must be persisted after retries exhausted")
    }

    func test_retry_succeedsBeforeMaxAttempts() async {
        let mock = MockEventPusher()
        mock.failNext(1)  // 1 fallo, luego éxito
        let queue = FileEventQueue(fileURL: fileURL)
        let pusher = ResilientEventPusher(
            delegate: mock,
            queue: queue,
            policy: policyFast(),
            synchronousPush: true
        )

        try? await pusher.push(makeEvent("rewarded"))

        XCTAssertEqual(mock.pushedCount, 1, "should succeed on retry")
        let queueSize = await queue.getSize()
        XCTAssertEqual(queueSize, 0, "no need to persist after success")
    }

    func test_flushOnce_drainsQueue_whenDelegateRecovers() async {
        let mock = MockEventPusher()
        // Pre-popular cola directamente
        let queue = FileEventQueue(fileURL: fileURL)
        _ = await queue.enqueue(makeEvent("e1"), priority: .normal)
        _ = await queue.enqueue(makeEvent("e2"), priority: .normal)

        let pusher = ResilientEventPusher(
            delegate: mock,
            queue: queue,
            policy: policyFast(),
            synchronousPush: true
        )

        let sent = await pusher.flushOnce()
        XCTAssertEqual(sent, 2)
        XCTAssertEqual(mock.pushedCount, 2)
        let size = await queue.getSize()
        XCTAssertEqual(size, 0)
    }

    func test_flushOnce_keepsEventsInQueue_whenDelegateStillFails() async {
        let mock = MockEventPusher()
        mock.failNext(10)
        let queue = FileEventQueue(fileURL: fileURL)
        _ = await queue.enqueue(makeEvent("e1"), priority: .normal)

        let pusher = ResilientEventPusher(
            delegate: mock,
            queue: queue,
            policy: policyFast(),
            synchronousPush: true
        )

        let sent = await pusher.flushOnce()
        XCTAssertEqual(sent, 0)
        let size = await queue.getSize()
        XCTAssertEqual(size, 1, "failed flush keeps the event (with incremented retry)")
    }
}
