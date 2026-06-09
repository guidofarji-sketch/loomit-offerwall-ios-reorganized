//
//  OfferwallAdapterTests.swift
//  LoomitOfferwallAdapterAPITests
//

import XCTest
import UIKit
@testable import LoomitOfferwallAdapterAPI

final class OfferwallAdapterTests: XCTestCase {

    func test_supports_isCaseInsensitive() {
        let adapter = MockAdapter(supportedKeys: ["mychips", "MAF"])

        XCTAssertTrue(adapter.supports(key: "mychips"))
        XCTAssertTrue(adapter.supports(key: "MyChips"))
        XCTAssertTrue(adapter.supports(key: "MYCHIPS"))
        XCTAssertTrue(adapter.supports(key: "maf"))
        XCTAssertTrue(adapter.supports(key: "Maf"))
        XCTAssertFalse(adapter.supports(key: "tapjoy"))
        XCTAssertFalse(adapter.supports(key: ""))
    }

    func test_supports_emptyKeysReturnsFalse() {
        let adapter = MockAdapter(supportedKeys: [])
        XCTAssertFalse(adapter.supports(key: "tapjoy"))
    }
}

// MARK: - Mocks

private final class MockAdapter: OfferwallAdapter, @unchecked Sendable {
    let providerName: String = "Mock"
    let supportedKeys: [String]

    init(supportedKeys: [String]) {
        self.supportedKeys = supportedKeys
    }

    @MainActor
    func createProvider() -> OfferwallProvider {
        MockProvider()
    }
}

@MainActor
private final class MockProvider: OfferwallProvider {
    nonisolated var providerKey: String { "mock" }
    nonisolated var providerSdkVersion: String? { nil }

    func initialize(
        config: ProviderConfig,
        listener: OfferwallProviderListener
    ) async -> Result<Void, OfferwallError> {
        .success(())
    }

    func isAvailable() -> Bool { false }

    func show(
        from presenter: UIViewController,
        adSpace: String?
    ) async -> Result<Void, OfferwallError> {
        .success(())
    }

    func close() {}
}
