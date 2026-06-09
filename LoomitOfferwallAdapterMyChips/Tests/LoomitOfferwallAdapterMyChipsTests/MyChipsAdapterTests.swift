//
//  MyChipsAdapterTests.swift
//  LoomitOfferwallAdapterMyChipsTests
//

import XCTest
@testable import LoomitOfferwallAdapterMyChips

final class MyChipsAdapterTests: XCTestCase {

    func test_supportedKeys_includeMyChipsAndMaf() {
        let adapter = MyChipsAdapter()
        XCTAssertTrue(adapter.supports(key: "mychips"))
        XCTAssertTrue(adapter.supports(key: "MyChips"))
        XCTAssertTrue(adapter.supports(key: "MAF"))
        XCTAssertTrue(adapter.supports(key: "maf"))
        XCTAssertFalse(adapter.supports(key: "tapjoy"))
    }

    func test_providerName_isStable() {
        XCTAssertEqual(MyChipsAdapter().providerName, "MyChips")
    }

    @MainActor
    func test_createProvider_returnsConfiguredInstance() async {
        let bridge = MockMyChipsSDKBridge()
        let adapter = MyChipsAdapter(
            bridgeFactory: { bridge },
            rewardListener: nil
        )
        let provider = adapter.createProvider()
        XCTAssertEqual(provider.providerKey, "mychips")
    }
}
