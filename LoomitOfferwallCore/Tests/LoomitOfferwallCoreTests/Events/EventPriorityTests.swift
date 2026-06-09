//
//  EventPriorityTests.swift
//  LoomitOfferwallCoreTests
//

import XCTest
@testable import LoomitOfferwallCore

final class EventPriorityTests: XCTestCase {

    func test_critical_eventTypes() {
        XCTAssertEqual(EventPriority.from(eventType: "init_provider_start"), .critical)
        XCTAssertEqual(EventPriority.from(eventType: "init_provider_success"), .critical)
        XCTAssertEqual(EventPriority.from(eventType: "init_provider_failed"), .critical)
        XCTAssertEqual(EventPriority.from(eventType: "config_success"), .critical)
        XCTAssertEqual(EventPriority.from(eventType: "config_error"), .critical)
        XCTAssertEqual(EventPriority.from(eventType: "rewarded"), .critical)
    }

    func test_high_eventTypes() {
        XCTAssertEqual(EventPriority.from(eventType: "content_show"), .high)
        XCTAssertEqual(EventPriority.from(eventType: "content_dismiss"), .high)
        XCTAssertEqual(EventPriority.from(eventType: "show_failed"), .high)
        XCTAssertEqual(EventPriority.from(eventType: "provider_failover"), .high)
        XCTAssertEqual(EventPriority.from(eventType: "provider_available"), .high)
    }

    func test_normal_isDefault() {
        XCTAssertEqual(EventPriority.from(eventType: "anything_else"), .normal)
        XCTAssertEqual(EventPriority.from(eventType: ""), .normal)
    }

    func test_ordering() {
        XCTAssertGreaterThan(EventPriority.critical, EventPriority.high)
        XCTAssertGreaterThan(EventPriority.high, EventPriority.normal)
    }
}
