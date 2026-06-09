//
//  OfferwallErrorTests.swift
//  LoomitOfferwallAdapterAPITests
//

import XCTest
@testable import LoomitOfferwallAdapterAPI

final class OfferwallErrorTests: XCTestCase {

    func test_diagnosticCode_isStableForBackendContract() {
        // Estos códigos son contrato con backend de logging; los hardcodeamos
        // para detectar renames accidentales en code review.
        XCTAssertEqual(OfferwallError.notInitialized(reason: "x").diagnosticCode, "not_initialized")
        XCTAssertEqual(OfferwallError.invalidConfiguration(reason: "x").diagnosticCode, "invalid_configuration")
        XCTAssertEqual(OfferwallError.missingApiKey.diagnosticCode, "missing_api_key")
        XCTAssertEqual(OfferwallError.backendUnreachable(underlying: "x").diagnosticCode, "backend_unreachable")
        XCTAssertEqual(OfferwallError.backendHTTPError(statusCode: 500, body: nil).diagnosticCode, "backend_http_error")
        XCTAssertEqual(OfferwallError.backendDecodingError(underlying: "x").diagnosticCode, "backend_decoding_error")
        XCTAssertEqual(OfferwallError.circuitOpenNoFallback.diagnosticCode, "circuit_open_no_fallback")
        XCTAssertEqual(OfferwallError.timeout(operation: "x").diagnosticCode, "timeout")
        XCTAssertEqual(OfferwallError.providerNotRegistered(key: "x").diagnosticCode, "provider_not_registered")
        XCTAssertEqual(OfferwallError.providerInitializationFailed(provider: "x", underlying: "y").diagnosticCode, "provider_initialization_failed")
        XCTAssertEqual(OfferwallError.providerUnavailable(provider: "x", reason: "y").diagnosticCode, "provider_unavailable")
        XCTAssertEqual(OfferwallError.providerShowFailed(provider: "x", underlying: "y").diagnosticCode, "provider_show_failed")
        XCTAssertEqual(OfferwallError.waterfallExhausted(attempted: ["a"]).diagnosticCode, "waterfall_exhausted")
        XCTAssertEqual(OfferwallError.invalidState(expected: "x", actual: "y").diagnosticCode, "invalid_state")
        XCTAssertEqual(OfferwallError.cancelled.diagnosticCode, "cancelled")
        XCTAssertEqual(OfferwallError.unknown(underlying: "x").diagnosticCode, "unknown")
    }

    func test_localizedDescription_includesContext() {
        let err = OfferwallError.providerInitializationFailed(provider: "tapjoy", underlying: "bad sdk_key")
        let desc = err.errorDescription ?? ""
        XCTAssertTrue(desc.contains("tapjoy"))
        XCTAssertTrue(desc.contains("bad sdk_key"))
    }

    func test_equatable() {
        XCTAssertEqual(
            OfferwallError.providerNotRegistered(key: "tapjoy"),
            OfferwallError.providerNotRegistered(key: "tapjoy")
        )
        XCTAssertNotEqual(
            OfferwallError.providerNotRegistered(key: "tapjoy"),
            OfferwallError.providerNotRegistered(key: "mychips")
        )
        XCTAssertNotEqual(
            OfferwallError.missingApiKey,
            OfferwallError.cancelled
        )
    }
}
