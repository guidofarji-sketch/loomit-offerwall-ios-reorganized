//
//  ProductionLoggerTests.swift
//  LoomitOfferwallCoreTests
//

import XCTest
@testable import LoomitOfferwallCore

final class ProductionLoggerTests: XCTestCase {

    private func makeConfig(
        enabled: Bool = true,
        endpoint: String? = "https://example.test/upload",
        categories: [String: CategoryConfigDTO] = [:]
    ) -> LoggingConfigDTO {
        LoggingConfigDTO(
            enabled: enabled,
            endpoint: endpoint,
            batchSize: nil,
            flushIntervalMs: nil,
            categories: categories
        )
    }

    private func alwaysOnCategory() -> CategoryConfigDTO {
        CategoryConfigDTO(enabled: true, samplingRate: 1.0, maxPerHour: 1000, minLevel: nil)
    }

    func test_disabledConfig_dropsAllLogs() async {
        let uploader = MockLogUploader()
        let logger = ProductionLogger(
            deviceHash: "dh",
            appId: "app",
            appVersion: "1.0",
            uploader: uploader,
            config: makeConfig(enabled: false, categories: ["x": alwaysOnCategory()])
        )

        let cat = await logger.category("x")
        await cat.info(["k": .string("v")])
        await logger.flush()

        XCTAssertEqual(uploader.batchCount, 0)
    }

    func test_normalCategory_buffersUntilFlush() async {
        let uploader = MockLogUploader()
        let logger = ProductionLogger(
            deviceHash: "dh",
            appId: "app",
            appVersion: "1.0",
            uploader: uploader,
            config: makeConfig(categories: ["telemetry": alwaysOnCategory()]),
            maxBufferSize: 10,
            flushInterval: 60
        )
        let cat = await logger.category("telemetry")
        await cat.info([:])
        await cat.info([:])

        // No flush automático todavía.
        XCTAssertEqual(uploader.batchCount, 0)
        let buffered = await logger.bufferedCount()
        XCTAssertEqual(buffered, 2)

        await logger.flush()
        XCTAssertEqual(uploader.batchCount, 1)
        XCTAssertEqual(uploader.totalLogsUploaded, 2)
    }

    func test_priorityCategory_flushesImmediately() async {
        let uploader = MockLogUploader()
        let logger = ProductionLogger(
            deviceHash: "dh",
            appId: "app",
            appVersion: "1.0",
            uploader: uploader,
            config: makeConfig(categories: ["provider_init_failures": alwaysOnCategory()]),
            maxBufferSize: 10,
            flushInterval: 60
        )
        let cat = await logger.category("provider_init_failures")
        await cat.info([:])

        XCTAssertEqual(uploader.batchCount, 1, "priority category triggers immediate flush")
    }

    func test_errorLevel_flushesImmediately() async {
        let uploader = MockLogUploader()
        let logger = ProductionLogger(
            deviceHash: "dh",
            appId: "app",
            appVersion: "1.0",
            uploader: uploader,
            config: makeConfig(categories: ["telemetry": alwaysOnCategory()]),
            maxBufferSize: 10,
            flushInterval: 60
        )
        let cat = await logger.category("telemetry")
        await cat.error(["msg": .string("boom")])
        XCTAssertEqual(uploader.batchCount, 1, "error level triggers immediate flush")
    }

    func test_bufferFull_triggersFlush() async {
        let uploader = MockLogUploader()
        let logger = ProductionLogger(
            deviceHash: "dh",
            appId: "app",
            appVersion: "1.0",
            uploader: uploader,
            config: makeConfig(categories: ["telemetry": alwaysOnCategory()]),
            maxBufferSize: 3,
            flushInterval: 60
        )
        let cat = await logger.category("telemetry")
        await cat.info([:])
        await cat.info([:])
        XCTAssertEqual(uploader.batchCount, 0)
        await cat.info([:])  // 3rd → buffer full → flush

        XCTAssertEqual(uploader.batchCount, 1)
        XCTAssertEqual(uploader.totalLogsUploaded, 3)
    }

    func test_updateConfig_reconfiguresExistingCategoryLoggers() async {
        let uploader = MockLogUploader()
        let logger = ProductionLogger(
            deviceHash: "dh",
            appId: "app",
            appVersion: "1.0",
            uploader: uploader,
            config: makeConfig(categories: ["x": alwaysOnCategory()]),
            maxBufferSize: 10,
            flushInterval: 60
        )
        let cat = await logger.category("x")
        await cat.info([:])
        let bufferedBefore = await logger.bufferedCount()
        XCTAssertEqual(bufferedBefore, 1)

        // Disable category via updateConfig.
        let disabled = CategoryConfigDTO(enabled: false, samplingRate: 0, maxPerHour: 0, minLevel: nil)
        await logger.updateConfig(makeConfig(categories: ["x": disabled]))

        await cat.info([:])
        let bufferedAfter = await logger.bufferedCount()
        XCTAssertEqual(bufferedAfter, 1, "disabled config must drop new logs")
    }

    func test_uploadFailure_doesNotCrash() async {
        let uploader = MockLogUploader()
        uploader.failNext(10)
        let logger = ProductionLogger(
            deviceHash: "dh",
            appId: "app",
            appVersion: "1.0",
            uploader: uploader,
            config: makeConfig(categories: ["telemetry": alwaysOnCategory()])
        )
        let cat = await logger.category("telemetry")
        await cat.info([:])
        await logger.flush()
        // No crash; batchCount sigue en 0 porque todos los uploads fallaron.
        XCTAssertEqual(uploader.batchCount, 0)
    }

    func test_deviceHash_isStableTruncated16() {
        let h1 = ProductionLogger.deviceHash(forIdentifier: "xifa-abc")
        let h2 = ProductionLogger.deviceHash(forIdentifier: "xifa-abc")
        XCTAssertEqual(h1, h2)
        XCTAssertEqual(h1.count, 16)
    }
}
