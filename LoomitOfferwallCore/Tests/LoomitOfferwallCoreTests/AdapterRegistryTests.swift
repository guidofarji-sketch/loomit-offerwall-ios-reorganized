//
//  AdapterRegistryTests.swift
//  LoomitOfferwallCoreTests
//

import XCTest
import UIKit
import LoomitOfferwallAdapterAPI
@testable import LoomitOfferwallCore

final class AdapterRegistryTests: XCTestCase {

    func test_registerAndLookup_caseInsensitive() async {
        let registry = AdapterRegistry()
        let mock = MockAdapter(providerName: "MyChips", supportedKeys: ["mychips", "MAF"])

        let replaced = await registry.register(mock)
        XCTAssertFalse(replaced)

        let foundLower  = await registry.adapter(for: "mychips")
        let foundUpper  = await registry.adapter(for: "MYCHIPS")
        let foundAlias  = await registry.adapter(for: "maf")
        let notFound    = await registry.adapter(for: "tapjoy")

        XCTAssertNotNil(foundLower)
        XCTAssertNotNil(foundUpper)
        XCTAssertNotNil(foundAlias)
        XCTAssertNil(notFound)
    }

    func test_register_replacesExistingForSameKey() async {
        let registry = AdapterRegistry()
        let original = MockAdapter(providerName: "A", supportedKeys: ["k"])
        let replacement = MockAdapter(providerName: "B", supportedKeys: ["k"])

        let firstReplaced = await registry.register(original)
        let secondReplaced = await registry.register(replacement)

        XCTAssertFalse(firstReplaced)
        XCTAssertTrue(secondReplaced)

        let resolved = await registry.adapter(for: "k") as? MockAdapter
        XCTAssertEqual(resolved?.providerName, "B")
    }

    func test_unregister_removesAllKeysOfAdapter() async {
        let registry = AdapterRegistry()
        let mock = MockAdapter(providerName: "X", supportedKeys: ["a", "b", "c"])
        await registry.register(mock)

        let removed = await registry.unregister(providerKey: "B")  // por una key cualquiera, case-insensitive
        XCTAssertTrue(removed)

        let foundA = await registry.adapter(for: "a")
        let foundB = await registry.adapter(for: "b")
        let foundC = await registry.adapter(for: "c")
        XCTAssertNil(foundA)
        XCTAssertNil(foundB)
        XCTAssertNil(foundC)
    }

    func test_count_andRegisteredKeys() async {
        let registry = AdapterRegistry()
        await registry.register(MockAdapter(providerName: "A", supportedKeys: ["a"]))
        await registry.register(MockAdapter(providerName: "B", supportedKeys: ["b1", "b2"]))

        let count = await registry.count
        let keys  = await registry.registeredKeys

        XCTAssertEqual(count, 2)
        XCTAssertEqual(keys, ["a", "b1", "b2"])
    }

    func test_removeAll_clearsRegistry() async {
        let registry = AdapterRegistry()
        await registry.register(MockAdapter(providerName: "A", supportedKeys: ["a"]))
        await registry.removeAll()

        let count = await registry.count
        let found = await registry.adapter(for: "a")
        XCTAssertEqual(count, 0)
        XCTAssertNil(found)
    }
}

// MARK: - MockAdapter

private struct MockAdapter: OfferwallAdapter {
    let providerName: String
    let supportedKeys: [String]

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
