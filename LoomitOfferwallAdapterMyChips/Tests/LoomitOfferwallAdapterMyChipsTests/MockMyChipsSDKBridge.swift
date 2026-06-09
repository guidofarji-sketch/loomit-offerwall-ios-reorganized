//
//  MockMyChipsSDKBridge.swift
//  LoomitOfferwallAdapterMyChipsTests
//

import Foundation
import UIKit
@testable import LoomitOfferwallAdapterMyChips

/// Mock que captura toda la secuencia de llamadas hechas al SDK.
@MainActor
final class MockMyChipsSDKBridge: MyChipsSDKBridge {

    enum Call: Equatable {
        case configure(apiKey: String)
        case setUserId(String)
        case setIdfa(String?)
        case setAge(Int?)
        case setGender(MyChipsGender?)
        case setAffSub1(String?)
        case setAffSub2(String?)
        case setAffSub3(String?)
        case setAffSub4(String?)
        case setAffSub5(String?)
        case setToolbarTitle(String?)
        case makeWebViewController(adUnitId: String)
        case getReward(adUnitId: String)
    }

    private(set) var calls: [Call] = []

    /// Cuándo se llamó makeWebViewController, capturamos el callback para
    /// poder simular `onClose` desde el test.
    private(set) var lastOnClose: (() -> Void)?

    /// Reward listener payload (empuje desde tests).
    var rewardToReturn: MyChipsReward?
    var errorToReturn: Error?

    func configure(apiKey: String) {
        calls.append(.configure(apiKey: apiKey))
    }
    func setUserId(_ userId: String) {
        calls.append(.setUserId(userId))
    }
    func setIdfa(_ idfa: String?) {
        calls.append(.setIdfa(idfa))
    }
    func setAge(_ age: Int?) {
        calls.append(.setAge(age))
    }
    func setGender(_ gender: MyChipsGender?) {
        calls.append(.setGender(gender))
    }
    func setAffSub1(_ value: String?) { calls.append(.setAffSub1(value)) }
    func setAffSub2(_ value: String?) { calls.append(.setAffSub2(value)) }
    func setAffSub3(_ value: String?) { calls.append(.setAffSub3(value)) }
    func setAffSub4(_ value: String?) { calls.append(.setAffSub4(value)) }
    func setAffSub5(_ value: String?) { calls.append(.setAffSub5(value)) }
    func setToolbarTitle(_ title: String?) {
        calls.append(.setToolbarTitle(title))
    }

    func makeWebViewController(adUnitId: String, onClose: @escaping () -> Void) -> UIViewController {
        calls.append(.makeWebViewController(adUnitId: adUnitId))
        self.lastOnClose = onClose
        return UIViewController()
    }

    func getReward(
        adUnitId: String,
        onReward: @escaping (MyChipsReward) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        calls.append(.getReward(adUnitId: adUnitId))
        if let r = rewardToReturn {
            onReward(r)
        }
        if let e = errorToReturn {
            onError(e)
        }
    }
}
