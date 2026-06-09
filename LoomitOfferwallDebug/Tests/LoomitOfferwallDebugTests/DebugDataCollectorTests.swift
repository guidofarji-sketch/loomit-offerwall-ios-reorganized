//
//  DebugDataCollectorTests.swift
//  LoomitOfferwallDebugTests
//

import XCTest
@testable import LoomitOfferwallDebug
import LoomitOfferwallCore

final class DebugDataCollectorTests: XCTestCase {

    func test_recordEvent_capturesAndIdsIncrement() async {
        let collector = DebugDataCollector()
        await collector.recordEvent(type: "init_start", provider: "tapjoy")
        await collector.recordEvent(type: "init_done", provider: "tapjoy", level: .info)

        let events = await collector.recentEvents()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].id, 1)
        XCTAssertEqual(events[1].id, 2)
        XCTAssertEqual(events[0].type, "init_start")
        XCTAssertEqual(events[1].provider, "tapjoy")
    }

    func test_recordEvent_respectsRingBufferSize() async {
        let collector = DebugDataCollector(eventBufferSize: 3)
        for i in 1...5 {
            await collector.recordEvent(type: "evt_\(i)")
        }
        let events = await collector.recentEvents()
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.map { $0.type }, ["evt_3", "evt_4", "evt_5"])
    }

    func test_recentEvents_withLimit() async {
        let collector = DebugDataCollector()
        for i in 1...10 {
            await collector.recordEvent(type: "e\(i)")
        }
        let last3 = await collector.recentEvents(limit: 3)
        XCTAssertEqual(last3.map { $0.type }, ["e8", "e9", "e10"])
    }

    func test_clearEvents() async {
        let collector = DebugDataCollector()
        await collector.recordEvent(type: "x")
        let countBefore = await collector.eventCount()
        XCTAssertEqual(countBefore, 1)

        await collector.clearEvents()
        let countAfter = await collector.eventCount()
        XCTAssertEqual(countAfter, 0)
    }

    func test_snapshot_returnsNilWithoutBridge() async {
        let collector = DebugDataCollector()
        let snap = await collector.snapshot()
        XCTAssertNil(snap)
    }

    func test_snapshot_returnsDataWithBridge() async {
        let bridge = StubBridge(
            xifa: "xifa-123",
            deviceFingerprint: "fp-abc",
            bundleIdentifier: "com.test",
            registeredAdapterKeys: ["mychips", "tapjoy"]
        )
        let collector = DebugDataCollector()
        await collector.attach(bridge: bridge)

        let snap = await collector.snapshot()
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?.xifa, "xifa-123")
        XCTAssertEqual(snap?.deviceFingerprint, "fp-abc")
        XCTAssertEqual(snap?.bundleIdentifier, "com.test")
        XCTAssertEqual(snap?.registeredAdapterKeys, ["mychips", "tapjoy"])
        XCTAssertEqual(snap?.resilienceState.operationMode, .normal)
    }

    func test_pendingEvents_delegatesToBridge() async {
        let pending = [
            PendingEventInfo(id: 1, type: "rewarded", provider: "tapjoy",
                             timestamp: 100, retryCount: 0, priority: "CRITICAL")
        ]
        let bridge = StubBridge(pendingEvents: pending)
        let collector = DebugDataCollector()
        await collector.attach(bridge: bridge)

        let result = await collector.pendingEvents()
        XCTAssertEqual(result, pending)
    }
}

// MARK: - Stub bridge

private final class StubBridge: DebugBridge, @unchecked Sendable {

    let xifaValue: String
    let deviceFingerprintValue: String
    let bundleIdentifierValue: String?
    let registeredAdapterKeysValue: [String]
    let pendingEventsValue: [PendingEventInfo]

    init(
        xifa: String = "xifa",
        deviceFingerprint: String = "fp",
        bundleIdentifier: String? = "com.test",
        registeredAdapterKeys: [String] = [],
        pendingEvents: [PendingEventInfo] = []
    ) {
        self.xifaValue = xifa
        self.deviceFingerprintValue = deviceFingerprint
        self.bundleIdentifierValue = bundleIdentifier
        self.registeredAdapterKeysValue = registeredAdapterKeys
        self.pendingEventsValue = pendingEvents
    }

    func xifa() async -> String { xifaValue }
    func deviceFingerprint() async -> String { deviceFingerprintValue }
    func bundleIdentifier() async -> String? { bundleIdentifierValue }
    func hasAdvertisingId() async -> Bool { false }
    func advertisingId() async -> String? { nil }
    func publisherUserId() async -> String? { nil }
    func lastConfig() async -> ConfigResponse? { nil }
    func lastConfigSource() async -> ConfigSource? { nil }
    func cachedConfigInfo() async -> CachedConfigInfo? { nil }
    func resilienceState() async -> ResilienceState {
        ResilienceState(
            operationMode: .normal,
            configSource: nil,
            cacheAge: nil,
            backendCircuitState: .closed
        )
    }
    func pendingEvents() async -> [PendingEventInfo] { pendingEventsValue }
    func pendingEventQueueSize() async -> Int { pendingEventsValue.count }
    func registeredAdapterKeys() async -> [String] { registeredAdapterKeysValue }
    func customPropertyDebugState() async -> [String: DebugCustomProperty] { [:] }
}
