//
//  ConfigCacheTests.swift
//  LoomitOfferwallCoreTests
//

import XCTest
@testable import LoomitOfferwallCore

final class ConfigCacheTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "loomit.tests.cache"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func test_load_returnsNil_whenEmpty() {
        let cache = UserDefaultsConfigCache(defaults: defaults, namespace: "ns")
        XCTAssertNil(cache.load())
        XCTAssertNil(cache.getAge())
    }

    func test_save_then_load_roundtrip() throws {
        let cache = UserDefaultsConfigCache(defaults: defaults, namespace: "ns")
        let snapshot = ConfigSnapshot(
            config: ConfigResponse(segment: "test_seg"),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            source: .network,
            checksum: ""
        )
        XCTAssertTrue(cache.save(snapshot))

        let loaded = cache.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.config.segment, "test_seg")
        XCTAssertEqual(loaded?.timestamp, snapshot.timestamp)
        XCTAssertEqual(loaded?.source, .network)
    }

    func test_clear_removesAll() throws {
        let cache = UserDefaultsConfigCache(defaults: defaults, namespace: "ns")
        let snap = ConfigSnapshot(
            config: ConfigResponse(segment: "x"),
            timestamp: Date(),
            source: .network,
            checksum: ""
        )
        _ = cache.save(snap)
        XCTAssertNotNil(cache.load())

        cache.clear()
        XCTAssertNil(cache.load())
    }

    func test_isStale_returnsTrue_whenOlderThanMaxAge() {
        let clock = TestClock(Date(timeIntervalSince1970: 2_000_000_000))
        let cache = UserDefaultsConfigCache(
            defaults: defaults,
            namespace: "ns",
            clock: { clock.now }
        )
        let snap = ConfigSnapshot(
            config: ConfigResponse(segment: "x"),
            timestamp: clock.now,
            source: .network,
            checksum: ""
        )
        _ = cache.save(snap)

        // Avanzo 25h
        clock.advance(25 * 3600)
        XCTAssertTrue(cache.isStale(maxAge: 24 * 3600))
        XCTAssertFalse(cache.isStale(maxAge: 30 * 3600))
    }

    func test_corruptedChecksum_returnsNilAndClears() {
        let cache = UserDefaultsConfigCache(defaults: defaults, namespace: "ns")
        let snap = ConfigSnapshot(
            config: ConfigResponse(segment: "x"),
            timestamp: Date(),
            source: .network,
            checksum: ""
        )
        _ = cache.save(snap)

        // Tamper: corromper el checksum guardado
        defaults.set("deadbeef", forKey: "ns.config_checksum")

        let loaded = cache.load()
        XCTAssertNil(loaded, "tampered checksum must invalidate cache")
        // Y el cache debería haberse limpiado
        XCTAssertFalse(defaults.dictionaryRepresentation().keys.contains("ns.config_json"))
    }
}
