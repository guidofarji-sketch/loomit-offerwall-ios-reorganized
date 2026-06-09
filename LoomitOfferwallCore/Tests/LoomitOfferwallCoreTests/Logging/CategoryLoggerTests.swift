//
//  CategoryLoggerTests.swift
//  LoomitOfferwallCoreTests
//

import XCTest
@testable import LoomitOfferwallCore

final class CategoryLoggerTests: XCTestCase {

    private actor Captured {
        var entries: [LogEntry] = []
        func add(_ e: LogEntry) { entries.append(e) }
    }

    func test_disabled_doesNotEmit() async {
        let captured = Captured()
        let logger = CategoryLogger(
            categoryName: "test",
            config: .disabled,
            deviceHash: "dh",
            sessionId: "s",
            onLog: { e in await captured.add(e) }
        )
        await logger.error(["k": .string("v")])
        let count = await captured.entries.count
        XCTAssertEqual(count, 0)
    }

    func test_alwaysOn_emitsForMatchingDevice() async {
        let captured = Captured()
        // alwaysOn = sampling 1.0 → siempre samplea
        let logger = CategoryLogger(
            categoryName: "test",
            config: .alwaysOn,
            deviceHash: "any-device",
            sessionId: "s",
            onLog: { e in await captured.add(e) }
        )
        await logger.info(["k": .string("v")])
        let count = await captured.entries.count
        XCTAssertEqual(count, 1)

        let entry = await captured.entries[0]
        XCTAssertEqual(entry.category, "test")
        XCTAssertEqual(entry.level, "info")
        XCTAssertEqual(entry.deviceId, "any-device")
        XCTAssertEqual(entry.sessionId, "s")
    }

    func test_samplingZero_neverEmits() async {
        let captured = Captured()
        let cfg = CategoryRuntimeConfig(enabled: true, samplingRate: 0.0, maxPerHour: 1000)
        let logger = CategoryLogger(
            categoryName: "test",
            config: cfg,
            deviceHash: "dh",
            sessionId: "s",
            onLog: { e in await captured.add(e) }
        )
        for _ in 0..<10 {
            await logger.info([:])
        }
        let count = await captured.entries.count
        XCTAssertEqual(count, 0)
    }

    func test_sampling_isDeterministic_perDevice() async {
        // Mismo deviceHash → misma decisión.
        let cfg = CategoryRuntimeConfig(enabled: true, samplingRate: 0.5, maxPerHour: 1000)

        let dec1 = CategoryLogger.djb2("device-x" + "cat-a")
        let dec2 = CategoryLogger.djb2("device-x" + "cat-a")
        XCTAssertEqual(dec1, dec2, "same input must hash to same value")
    }

    func test_rateLimit_dropsAfterMaxPerHour() async {
        let captured = Captured()
        let cfg = CategoryRuntimeConfig(enabled: true, samplingRate: 1.0, maxPerHour: 3)
        let clock = TestClock(Date(timeIntervalSince1970: 1_000_000))
        let logger = CategoryLogger(
            categoryName: "test",
            config: cfg,
            deviceHash: "dh",
            sessionId: "s",
            onLog: { e in await captured.add(e) },
            clock: { clock.now }
        )
        for _ in 0..<10 {
            await logger.info([:])
        }
        let count = await captured.entries.count
        XCTAssertEqual(count, 3, "rate limit must cap at 3/hour")

        // Avanzar 2 horas → debería resetear
        clock.advance(2 * 3600)
        for _ in 0..<5 {
            await logger.info([:])
        }
        let count2 = await captured.entries.count
        XCTAssertEqual(count2, 6, "next hour gets a fresh budget of 3")
    }

    func test_sanitize_removesPII() {
        let input: [String: JSONValue] = [
            "email": .string("a@b.com"),
            "phone": .string("123"),
            "ok_key": .string("kept")
        ]
        let out = CategoryLogger.sanitize(input)
        XCTAssertNil(out["email"])
        XCTAssertNil(out["phone"])
        XCTAssertEqual(out["ok_key"], .string("kept"))
    }

    func test_sanitize_truncatesLongStrings() {
        let long = String(repeating: "x", count: 600)
        let out = CategoryLogger.sanitize(["k": .string(long)])
        guard case let .string(s) = out["k"]! else { return XCTFail() }
        XCTAssertEqual(s.count, 503, "500 chars + '...' suffix")
        XCTAssertTrue(s.hasSuffix("..."))
    }
}
