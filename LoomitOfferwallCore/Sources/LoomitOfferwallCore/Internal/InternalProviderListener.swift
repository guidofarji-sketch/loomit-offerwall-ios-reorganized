//
//  InternalProviderListener.swift
//  LoomitOfferwallCore
//
//  Implementación interna de `OfferwallProviderListener` que recibe
//  callbacks de inicialización y disponibilidad desde los adapters y los
//  propaga al core (`OfferwallSdk`).
//
//  Invariante §2.2: UX callbacks (onShow, onClose, onRewarded) van por
//  el listener global — NO por este listener interno.
//

import Foundation
import LoomitOfferwallAdapterAPI

/// Listener interno que core registra en cada provider.
///
/// Recibe señales de init, availability y reward del adapter y las propaga
/// al `OfferwallSdk` actor.
@MainActor
final class InternalProviderListener: OfferwallProviderListener {

    private let sdk: OfferwallSdk

    init(sdk: OfferwallSdk) {
        self.sdk = sdk
    }

    func providerDidInitialize(_ providerKey: String) {
        // Init success ya se maneja en initAllFromPlan via Result
    }

    func provider(_ providerKey: String, didFailToInitializeWith error: OfferwallError) {
        // Init error ya se maneja en initAllFromPlan via Result
    }

    func provider(_ providerKey: String, didChangeAvailability isAvailable: Bool) {
        Task {
            await sdk.handleProviderDidChangeAvailability(
                providerKey: providerKey,
                isAvailable: isAvailable
            )
        }
    }

    func provider(_ providerKey: String, didEarnRewardAmount amount: Int, currency: String) {
        Task {
            await sdk.handleProviderDidEarnReward(
                providerKey: providerKey,
                amount: amount,
                currency: currency
            )
        }
    }

    func providerDidClose(_ providerKey: String) {
        Task {
            await sdk.handleProviderDidClose(providerKey: providerKey)
        }
    }

    func providerDidShow(_ providerKey: String) {
        Task {
            await sdk.handleProviderDidShow(providerKey: providerKey)
        }
    }
}
