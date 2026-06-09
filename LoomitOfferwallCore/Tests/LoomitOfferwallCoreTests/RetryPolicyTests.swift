//
//  RetryPolicyTests.swift
//  LoomitOfferwallCoreTests
//

import XCTest
@testable import LoomitOfferwallCore

final class RetryPolicyTests: XCTestCase {

    func test_delayBefore_firstAttempt_isZero() {
        let p = RetryPolicy(maxAttempts: 3, initialDelay: 1, maxDelay: 10, multiplier: 2, jitter: 0)
        XCTAssertEqual(p.delayBefore(attempt: 1, randomSource: { 0 }), 0)
    }

    func test_delayBefore_growsExponentially() {
        let p = RetryPolicy(maxAttempts: 5, initialDelay: 1, maxDelay: 100, multiplier: 2, jitter: 0)
        XCTAssertEqual(p.delayBefore(attempt: 2, randomSource: { 0 }), 1.0,  accuracy: 1e-9)
        XCTAssertEqual(p.delayBefore(attempt: 3, randomSource: { 0 }), 2.0,  accuracy: 1e-9)
        XCTAssertEqual(p.delayBefore(attempt: 4, randomSource: { 0 }), 4.0,  accuracy: 1e-9)
        XCTAssertEqual(p.delayBefore(attempt: 5, randomSource: { 0 }), 8.0,  accuracy: 1e-9)
    }

    func test_delayBefore_respectsMaxDelay() {
        let p = RetryPolicy(maxAttempts: 10, initialDelay: 1, maxDelay: 5, multiplier: 2, jitter: 0)
        // Sin jitter: 1, 2, 4, 5, 5, ...
        XCTAssertEqual(p.delayBefore(attempt: 5, randomSource: { 0 }), 5.0, accuracy: 1e-9)
        XCTAssertEqual(p.delayBefore(attempt: 9, randomSource: { 0 }), 5.0, accuracy: 1e-9)
    }

    func test_delayBefore_jitter_addsBoundedAmount() {
        let p = RetryPolicy(maxAttempts: 5, initialDelay: 10, maxDelay: 100, multiplier: 2, jitter: 0.5)
        // Con jitter 0.5 y random=1: delay = 10 + 10*0.5*1 = 15.
        XCTAssertEqual(p.delayBefore(attempt: 2, randomSource: { 1 }), 15.0, accuracy: 1e-9)
        // Con jitter 0.5 y random=0: delay = 10 + 0 = 10.
        XCTAssertEqual(p.delayBefore(attempt: 2, randomSource: { 0 }), 10.0, accuracy: 1e-9)
    }

    func test_none_doesNotRetry() {
        XCTAssertEqual(RetryPolicy.none.maxAttempts, 1)
    }

    func test_default_isReasonable() {
        let p = RetryPolicy.default
        XCTAssertGreaterThanOrEqual(p.maxAttempts, 2)
        XCTAssertLessThanOrEqual(p.maxAttempts, 5)
        XCTAssertGreaterThan(p.maxDelay, p.initialDelay)
    }
}
