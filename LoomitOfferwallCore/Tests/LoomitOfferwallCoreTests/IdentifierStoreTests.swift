//
//  IdentifierStoreTests.swift
//  LoomitOfferwallCoreTests
//

import XCTest
import CryptoKit
@testable import LoomitOfferwallCore

final class IdentifierStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "loomit.tests.identifierstore"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - XIFA

    func test_xifa_isStableAcrossCalls() {
        let store = makeStore()
        XCTAssertEqual(store.xifa(), store.xifa())
        XCTAssertFalse(store.xifa().isEmpty)
    }

    func test_xifa_persistsAcrossInstances() {
        let first = makeStore().xifa()
        let second = makeStore().xifa()
        XCTAssertEqual(first, second)
    }

    func test_xifa_isUUIDFormat() {
        let xifa = makeStore().xifa()
        XCTAssertNotNil(UUID(uuidString: xifa), "expected UUID, got: \(xifa)")
    }

    func test_xifa_isLowercase() {
        let xifa = makeStore().xifa()
        XCTAssertEqual(xifa, xifa.lowercased())
    }

    // MARK: - Fingerprint

    func test_deviceFingerprint_isDeterministic() {
        let a = makeStore(idfv: "ABCD-1234", bundleId: "com.publisher.app").deviceFingerprint()
        let b = makeStore(idfv: "ABCD-1234", bundleId: "com.publisher.app").deviceFingerprint()
        XCTAssertEqual(a, b)
    }

    func test_deviceFingerprint_changesWhenIDFVChanges() {
        let a = makeStore(idfv: "AAA").deviceFingerprint()
        let b = makeStore(idfv: "BBB").deviceFingerprint()
        XCTAssertNotEqual(a, b)
    }

    func test_deviceFingerprint_changesWhenBundleChanges() {
        let a = makeStore(idfv: "X", bundleId: "com.app1").deviceFingerprint()
        let b = makeStore(idfv: "X", bundleId: "com.app2").deviceFingerprint()
        XCTAssertNotEqual(a, b)
    }

    func test_deviceFingerprint_isHex64() {
        let fp = makeStore(idfv: "X", bundleId: "y").deviceFingerprint()
        XCTAssertEqual(fp.count, 64)
        XCTAssertTrue(fp.allSatisfy { $0.isHexDigit })
    }

    /// Vector conocido — protege el contrato del fingerprint v1 contra
    /// cambios accidentales en el cómputo.
    func test_deviceFingerprint_knownVector() {
        // La impl lowercasea IDFV antes de hashear, así que el input efectivo
        // es "abcd-1234:com.publisher.app".
        let store = makeStore(idfv: "ABCD-1234", bundleId: "com.publisher.app")
        let actual = store.deviceFingerprint()
        let expected = sha256Hex("abcd-1234:com.publisher.app")
        XCTAssertEqual(
            actual, expected,
            "Contract: device_fingerprint v1 = SHA-256(idfv_lowercased + ':' + bundleId)"
        )
    }

    func test_deviceFingerprint_nilIDFV_usesPersistentFallback() {
        let a = makeStore(idfv: nil, bundleId: "com.app").deviceFingerprint()
        let b = makeStore(idfv: nil, bundleId: "com.app").deviceFingerprint()
        XCTAssertEqual(a, b, "fallback UUID should be persisted in UserDefaults")
    }

    // MARK: - Helpers

    private func makeStore(
        idfv: String? = "TEST-IDFV-AAAA",
        bundleId: String = "com.test.bundle"
    ) -> IdentifierStore {
        IdentifierStore(
            defaults: defaults,
            bundle: MockBundle(bundleIdentifier: bundleId),
            idfvProvider: { idfv }
        )
    }

    private func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - MockBundle

private final class MockBundle: Bundle, @unchecked Sendable {
    private let _bundleId: String?

    init(bundleIdentifier: String?) {
        self._bundleId = bundleIdentifier
        super.init()
    }

    override var bundleIdentifier: String? { _bundleId }
}
