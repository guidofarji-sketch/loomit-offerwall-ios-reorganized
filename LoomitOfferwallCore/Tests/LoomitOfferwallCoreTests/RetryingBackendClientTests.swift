//
//  RetryingBackendClientTests.swift
//  LoomitOfferwallCoreTests
//

import XCTest
import LoomitOfferwallAdapterAPI
@testable import LoomitOfferwallCore

final class RetryingBackendClientTests: XCTestCase {

    private let dummyRequest = ConfigRequest(clientId: "X", xifa: "Y")

    // MARK: - Retry behavior

    func test_succeedsOnFirstAttempt_noRetry() async throws {
        let mock = MockBackendClient()
        mock.enqueueSuccess()

        let client = RetryingBackendClient(
            wrapping: mock,
            policy: RetryPolicy(maxAttempts: 3, initialDelay: 0, maxDelay: 0, multiplier: 1, jitter: 0),
            sleeper: { _ in }
        )

        _ = try await client.fetchConfig(dummyRequest)
        XCTAssertEqual(mock.callCount, 1)
    }

    func test_succeedsAfterTransientFailures() async throws {
        let mock = MockBackendClient()
        mock.enqueueError(OfferwallError.timeout(operation: "fetchConfig"))
        mock.enqueueError(OfferwallError.backendUnreachable(underlying: "x"))
        mock.enqueueSuccess()

        let client = RetryingBackendClient(
            wrapping: mock,
            policy: RetryPolicy(maxAttempts: 3, initialDelay: 0, maxDelay: 0, multiplier: 1, jitter: 0),
            sleeper: { _ in }
        )

        _ = try await client.fetchConfig(dummyRequest)
        XCTAssertEqual(mock.callCount, 3)
    }

    func test_throwsAfterMaxAttempts() async {
        let mock = MockBackendClient()
        for _ in 0..<5 {
            mock.enqueueError(OfferwallError.timeout(operation: "fetchConfig"))
        }

        let client = RetryingBackendClient(
            wrapping: mock,
            policy: RetryPolicy(maxAttempts: 3, initialDelay: 0, maxDelay: 0, multiplier: 1, jitter: 0),
            sleeper: { _ in }
        )

        do {
            _ = try await client.fetchConfig(dummyRequest)
            XCTFail("expected to throw")
        } catch let error as OfferwallError {
            XCTAssertEqual(error.diagnosticCode, "timeout")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
        XCTAssertEqual(mock.callCount, 3, "should have tried exactly maxAttempts times")
    }

    // MARK: - Non-retriable errors

    func test_doesNotRetry_onDecodingError() async {
        let mock = MockBackendClient()
        mock.enqueueError(OfferwallError.backendDecodingError(underlying: "x"))
        mock.enqueueSuccess()

        let client = RetryingBackendClient(
            wrapping: mock,
            policy: RetryPolicy(maxAttempts: 3, initialDelay: 0, maxDelay: 0, multiplier: 1, jitter: 0),
            sleeper: { _ in }
        )

        do {
            _ = try await client.fetchConfig(dummyRequest)
            XCTFail()
        } catch {}
        XCTAssertEqual(mock.callCount, 1, "decoding errors should not retry")
    }

    func test_doesNotRetry_on4xx() async {
        let mock = MockBackendClient()
        mock.enqueueError(OfferwallError.backendHTTPError(statusCode: 401, body: nil))

        let client = RetryingBackendClient(
            wrapping: mock,
            policy: RetryPolicy(maxAttempts: 3, initialDelay: 0, maxDelay: 0, multiplier: 1, jitter: 0),
            sleeper: { _ in }
        )

        do {
            _ = try await client.fetchConfig(dummyRequest)
            XCTFail()
        } catch {}
        XCTAssertEqual(mock.callCount, 1, "401 should not retry")
    }

    func test_retries_on5xx_408_429() async {
        for status in [500, 502, 503, 408, 429] {
            let mock = MockBackendClient()
            mock.enqueueError(OfferwallError.backendHTTPError(statusCode: status, body: nil))
            mock.enqueueSuccess()

            let client = RetryingBackendClient(
                wrapping: mock,
                policy: RetryPolicy(maxAttempts: 3, initialDelay: 0, maxDelay: 0, multiplier: 1, jitter: 0),
                sleeper: { _ in }
            )

            do {
                _ = try await client.fetchConfig(dummyRequest)
            } catch {
                XCTFail("should have succeeded on retry for status \(status)")
            }
            XCTAssertEqual(mock.callCount, 2, "status \(status) should have retried once")
        }
    }

    // MARK: - isRetriable matrix

    func test_isRetriable_matrix() {
        XCTAssertTrue(RetryingBackendClient.isRetriable(.timeout(operation: "x")))
        XCTAssertTrue(RetryingBackendClient.isRetriable(.backendUnreachable(underlying: "x")))
        XCTAssertTrue(RetryingBackendClient.isRetriable(.backendHTTPError(statusCode: 500, body: nil)))
        XCTAssertTrue(RetryingBackendClient.isRetriable(.backendHTTPError(statusCode: 503, body: nil)))
        XCTAssertTrue(RetryingBackendClient.isRetriable(.backendHTTPError(statusCode: 408, body: nil)))
        XCTAssertTrue(RetryingBackendClient.isRetriable(.backendHTTPError(statusCode: 429, body: nil)))

        XCTAssertFalse(RetryingBackendClient.isRetriable(.backendHTTPError(statusCode: 400, body: nil)))
        XCTAssertFalse(RetryingBackendClient.isRetriable(.backendHTTPError(statusCode: 401, body: nil)))
        XCTAssertFalse(RetryingBackendClient.isRetriable(.backendHTTPError(statusCode: 403, body: nil)))
        XCTAssertFalse(RetryingBackendClient.isRetriable(.backendDecodingError(underlying: "x")))
        XCTAssertFalse(RetryingBackendClient.isRetriable(.invalidConfiguration(reason: "x")))
        XCTAssertFalse(RetryingBackendClient.isRetriable(.missingApiKey))
        XCTAssertFalse(RetryingBackendClient.isRetriable(.cancelled))
    }
}
