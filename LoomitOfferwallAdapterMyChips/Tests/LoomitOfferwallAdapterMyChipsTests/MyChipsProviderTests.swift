//
//  MyChipsProviderTests.swift
//  LoomitOfferwallAdapterMyChipsTests
//

import XCTest
import UIKit
import LoomitOfferwallAdapterAPI
@testable import LoomitOfferwallAdapterMyChips

@MainActor
final class MyChipsProviderTests: XCTestCase {

    // Captures de listener.
    final class CapturingListener: OfferwallProviderListener {
        var initialized: [String] = []
        var failed: [(String, OfferwallError)] = []
        var availabilityChanges: [(String, Bool)] = []
        var rewards: [(String, Int, String)] = []

        func providerDidInitialize(_ providerKey: String) {
            initialized.append(providerKey)
        }
        func provider(_ providerKey: String, didFailToInitializeWith error: OfferwallError) {
            failed.append((providerKey, error))
        }
        func provider(_ providerKey: String, didChangeAvailability isAvailable: Bool) {
            availabilityChanges.append((providerKey, isAvailable))
        }
        func provider(_ providerKey: String, didEarnRewardAmount amount: Int, currency: String) {
            rewards.append((providerKey, amount, currency))
        }
    }

    final class CapturingRewardListener: MyChipsRewardListener, @unchecked Sendable {
        var rewards: [(MyChipsReward, String)] = []
        var errors: [(NSError, String)] = []
        func myChipsDidEarn(reward: MyChipsReward, adUnitId: String) {
            rewards.append((reward, adUnitId))
        }
        func myChipsRewardCheckFailed(error: Error, adUnitId: String) {
            errors.append((error as NSError, adUnitId))
        }
    }

    private func makeConfig(
        credentials: [String: String] = ["api_key": "k", "ad_unit_id": "a"],
        settings: [String: String] = [:],
        userId: String = "user-1"
    ) -> ProviderConfig {
        ProviderConfig(
            providerKey: "mychips",
            priority: 1,
            credentials: credentials,
            settings: settings,
            privacy: .empty,
            userId: userId,
            xifa: "xifa-1",
            appId: "app",
            country: "AR",
            sdkVersion: "0.1",
            appVersion: "1.0"
        )
    }

    func test_initialize_appliesAllSettersInOrder() async {
        let bridge = MockMyChipsSDKBridge()
        let provider = MyChipsProvider(bridge: bridge)
        let listener = CapturingListener()

        let cfg = makeConfig(
            credentials: [
                "api_key": "K1", "ad_unit_id": "AD",
                "aff_sub1": "s1", "aff_sub2": "s2", "aff_sub3": "s3",
                "aff_sub4": "s4", "aff_sub5": "s5",
                "title": "Earn coins!",
                "age": "25", "gender": "male"
            ],
            userId: "user-xyz"
        )
        let result = await provider.initialize(config: cfg, listener: listener)

        guard case .success = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(listener.initialized, ["mychips"])
        XCTAssertEqual(listener.availabilityChanges.count, 1)
        XCTAssertEqual(listener.availabilityChanges[0].1, true)

        XCTAssertEqual(bridge.calls, [
            .configure(apiKey: "K1"),
            .setUserId("user-xyz"),
            .setAge(25),
            .setGender(.male),
            .setAffSub1("s1"),
            .setAffSub2("s2"),
            .setAffSub3("s3"),
            .setAffSub4("s4"),
            .setAffSub5("s5"),
            .setToolbarTitle("Earn coins!")
        ])
    }

    func test_initialize_passesIdfa_whenProvidedInCredentials() async {
        let bridge = MockMyChipsSDKBridge()
        let provider = MyChipsProvider(bridge: bridge)
        let listener = CapturingListener()

        let cfg = makeConfig(credentials: [
            "api_key": "K", "ad_unit_id": "A", "idfa": "AB-CD-EF"
        ])
        _ = await provider.initialize(config: cfg, listener: listener)

        XCTAssertTrue(bridge.calls.contains(.setIdfa("AB-CD-EF")))
    }

    func test_initialize_failsWhenApiKeyMissing() async {
        let bridge = MockMyChipsSDKBridge()
        let provider = MyChipsProvider(bridge: bridge)
        let listener = CapturingListener()

        let cfg = makeConfig(credentials: ["ad_unit_id": "A"])
        let result = await provider.initialize(config: cfg, listener: listener)

        guard case .failure(let err) = result else { return XCTFail() }
        if case .invalidConfiguration = err {
            // expected
        } else {
            XCTFail("expected invalidConfiguration, got \(err)")
        }
        XCTAssertEqual(listener.failed.count, 1)
        XCTAssertEqual(listener.initialized, [])
        XCTAssertTrue(bridge.calls.isEmpty, "no SDK call must be made if config invalid")
    }

    func test_isAvailable_falseUntilInitialized() async {
        let provider = MyChipsProvider(bridge: MockMyChipsSDKBridge())
        XCTAssertFalse(provider.isAvailable())

        _ = await provider.initialize(config: makeConfig(), listener: CapturingListener())
        XCTAssertTrue(provider.isAvailable())
    }

    func test_show_pushesIntoNavigationController() async {
        let bridge = MockMyChipsSDKBridge()
        let provider = MyChipsProvider(bridge: bridge)
        _ = await provider.initialize(config: makeConfig(), listener: CapturingListener())

        let root = UIViewController()
        let nav = UINavigationController(rootViewController: root)

        let result = await provider.show(from: nav, adSpace: nil)

        guard case .success = result else { return XCTFail() }
        XCTAssertTrue(bridge.calls.contains(.makeWebViewController(adUnitId: "a")))
        XCTAssertEqual(nav.viewControllers.count, 2, "WebVC was pushed")
    }

    func test_show_usesAdSpaceOverride_whenProvided() async {
        let bridge = MockMyChipsSDKBridge()
        let provider = MyChipsProvider(bridge: bridge)
        _ = await provider.initialize(
            config: makeConfig(credentials: ["api_key": "k", "ad_unit_id": "default-ad"]),
            listener: CapturingListener()
        )

        let nav = UINavigationController(rootViewController: UIViewController())
        _ = await provider.show(from: nav, adSpace: "override-ad")

        XCTAssertTrue(bridge.calls.contains(.makeWebViewController(adUnitId: "override-ad")))
        XCTAssertFalse(bridge.calls.contains(.makeWebViewController(adUnitId: "default-ad")))
    }

    func test_show_failsWhenNotInitialized() async {
        let provider = MyChipsProvider(bridge: MockMyChipsSDKBridge())
        let result = await provider.show(from: UIViewController(), adSpace: nil)
        guard case .failure(let err) = result else { return XCTFail() }
        if case .providerUnavailable = err {} else {
            XCTFail("expected providerUnavailable, got \(err)")
        }
    }

    func test_checkPendingReward_callsListenerOnReward() async {
        let bridge = MockMyChipsSDKBridge()
        bridge.rewardToReturn = MyChipsReward(virtualCurrencyReward: 42.0)

        let rewardListener = CapturingRewardListener()
        let provider = MyChipsProvider(bridge: bridge, rewardListener: rewardListener)
        _ = await provider.initialize(config: makeConfig(), listener: CapturingListener())

        provider.checkPendingReward()

        XCTAssertTrue(bridge.calls.contains(.getReward(adUnitId: "a")))
        XCTAssertEqual(rewardListener.rewards.count, 1)
        XCTAssertEqual(rewardListener.rewards[0].0.virtualCurrencyReward, 42.0)
        XCTAssertEqual(rewardListener.rewards[0].1, "a")
    }

    func test_checkPendingReward_callsListenerOnError() async {
        let bridge = MockMyChipsSDKBridge()
        bridge.errorToReturn = NSError(domain: "test", code: 99)

        let rewardListener = CapturingRewardListener()
        let provider = MyChipsProvider(bridge: bridge, rewardListener: rewardListener)
        _ = await provider.initialize(config: makeConfig(), listener: CapturingListener())

        provider.checkPendingReward()

        XCTAssertEqual(rewardListener.errors.count, 1)
        XCTAssertEqual(rewardListener.errors[0].0.code, 99)
    }
}
