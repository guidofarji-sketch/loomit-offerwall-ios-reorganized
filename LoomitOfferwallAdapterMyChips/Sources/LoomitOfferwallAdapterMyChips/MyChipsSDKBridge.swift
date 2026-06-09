//
//  MyChipsSDKBridge.swift
//  LoomitOfferwallAdapterMyChips
//
//  Capa fina sobre `MCOfferwallSDK.shared` + `MCWebViewController`.
//
//  ¿Por qué un protocol y no llamar al SDK directo?
//  - Testabilidad: el SDK MyChips se distribuye como XCFramework binario;
//    al testear el adapter en CI no queremos depender del binario real.
//    Con un protocol mockeable podemos verificar la secuencia de llamadas
//    sin linkear el SDK.
//  - Evita reflection (que es lo que Android usa con `Class.forName`).
//
//  La impl `LiveMyChipsSDKBridge` delega 1:1 al SDK real.
//

import Foundation
import UIKit
import MyChipsSdk

/// Resultado de un reward check vía `getReward(adunitId:)`.
public struct MyChipsReward: Sendable, Equatable {
    /// Cantidad de currency virtual ganada en el período consultado.
    public let virtualCurrencyReward: Double

    public init(virtualCurrencyReward: Double) {
        self.virtualCurrencyReward = virtualCurrencyReward
    }
}

/// Abstracción del SDK MyChips iOS. Una instancia por proceso suele bastar
/// (el SDK real es singleton).
@MainActor
public protocol MyChipsSDKBridge: AnyObject {

    // MARK: - Init / setters
    func configure(apiKey: String)
    func setUserId(_ userId: String)
    func setIdfa(_ idfa: String?)
    func setAge(_ age: Int?)
    func setGender(_ gender: MyChipsGender?)
    func setAffSub1(_ value: String?)
    func setAffSub2(_ value: String?)
    func setAffSub3(_ value: String?)
    func setAffSub4(_ value: String?)
    func setAffSub5(_ value: String?)
    func setToolbarTitle(_ title: String?)

    // MARK: - Show
    /// Construye el `UIViewController` que el adapter empuja/presenta. El
    /// closure `onClose` debe invocarse cuando el usuario cierra el offerwall.
    func makeWebViewController(adUnitId: String, onClose: @escaping () -> Void) -> UIViewController

    // MARK: - Reward (Self-Managed Currency)
    func getReward(
        adUnitId: String,
        onReward: @escaping (MyChipsReward) -> Void,
        onError: @escaping (Error) -> Void
    )
}

// MARK: - Live impl (delega al SDK real)

/// Default impl que delega al SDK MyChips real. **Main-actor isolated** porque
/// el SDK manipula UI.
@MainActor
public final class LiveMyChipsSDKBridge: MyChipsSDKBridge {

    public init() {}

    public func configure(apiKey: String) {
        MCOfferwallSDK.shared.configure(apiKey: apiKey)
    }

    public func setUserId(_ userId: String) {
        MCOfferwallSDK.shared.setUserId(userId: userId)
    }

    public func setIdfa(_ idfa: String?) {
        MCOfferwallSDK.shared.setIdfa(idfa: idfa)
    }

    public func setAge(_ age: Int?) {
        MCOfferwallSDK.shared.setAge(age)
    }

    public func setGender(_ gender: MyChipsGender?) {
        let mapped: MCGenderEnum?
        switch gender {
        case .male:    mapped = .male
        case .female:  mapped = .female
        case .other:   mapped = .other
        case nil:      mapped = nil
        }
        MCOfferwallSDK.shared.setGender(mapped)
    }

    public func setAffSub1(_ value: String?) { MCOfferwallSDK.shared.setAffSub1(value) }
    public func setAffSub2(_ value: String?) { MCOfferwallSDK.shared.setAffSub2(value) }
    public func setAffSub3(_ value: String?) { MCOfferwallSDK.shared.setAffSub3(value) }
    public func setAffSub4(_ value: String?) { MCOfferwallSDK.shared.setAffSub4(value) }
    public func setAffSub5(_ value: String?) { MCOfferwallSDK.shared.setAffSub5(value) }

    public func setToolbarTitle(_ title: String?) {
        MCOfferwallSDK.shared.setToolbarTitle(title)
    }

    public func makeWebViewController(adUnitId: String, onClose: @escaping () -> Void) -> UIViewController {
        MCWebViewController(adunitId: adUnitId, onClose: onClose)
    }

    public func getReward(
        adUnitId: String,
        onReward: @escaping (MyChipsReward) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        MCOfferwallSDK.shared.getReward(
            adunitId: adUnitId,
            onReward: { reward in
                onReward(MyChipsReward(virtualCurrencyReward: reward.virtualCurrencyReward))
            },
            onError: { error in
                onError(error)
            }
        )
    }
}
