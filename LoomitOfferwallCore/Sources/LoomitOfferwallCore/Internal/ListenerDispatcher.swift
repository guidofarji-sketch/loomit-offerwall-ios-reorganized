//
//  ListenerDispatcher.swift
//  LoomitOfferwallCore
//
//  Punto único de despacho a los listeners globales del publisher.
//  Invariante §2.2 — single-path: todo UX callback pasa por acá.
//
//  Diseño:
//  - La clase NO es `@MainActor` (puede construirse e invocar setters desde
//    cualquier thread / contexto de actor). Esto es necesario porque
//    `OfferwallSdk` es un actor y sus init/setters no garantizan main.
//  - Los `dispatch*` saltan a `MainActor` antes de invocar el protocolo
//    del publisher (que sí es `@MainActor`).
//  - `weak` references a los listeners (publisher dueño del lifecycle).
//  - Acceso al weak guarded por NSLock para safety cross-thread.
//

import Foundation
import LoomitOfferwallAdapterAPI

/// Despachador centralizado de UX callbacks al `OfferwallListener` global.
///
/// **No despachar a listeners directamente desde otros sitios** — siempre via
/// esta clase. Code-review debe rechazar dispatches paralelos.
final class ListenerDispatcher: @unchecked Sendable {

    private let lock = NSLock()
    private weak var uxListener: OfferwallListener?
    private weak var trackingListener: OfferwallTrackingListener?

    init() {}

    // MARK: - Setters (any thread)

    func setUXListener(_ listener: OfferwallListener?) {
        lock.lock()
        uxListener = listener
        lock.unlock()
    }

    func setTrackingListener(_ listener: OfferwallTrackingListener?) {
        lock.lock()
        trackingListener = listener
        lock.unlock()
    }

    // MARK: - UX dispatch (hop to main)

    func dispatchConfigResult(_ result: Result<ConfigResponse, OfferwallError>) {
        let listener = currentUXListener()
        Task { @MainActor in
            listener?.offerwall(didReceiveConfig: result)
        }
    }

    func dispatchAvailabilityChanged(_ available: Bool) {
        let listener = currentUXListener()
        Task { @MainActor in
            listener?.offerwall(didChangeAvailability: available)
        }
    }

    func dispatchDidShow(providerKey: String, adSpace: String?) {
        let listener = currentUXListener()
        Task { @MainActor in
            listener?.offerwall(didShow: providerKey, adSpace: adSpace)
        }
    }

    func dispatchDidFailToShow(_ error: OfferwallError, adSpace: String?) {
        let listener = currentUXListener()
        Task { @MainActor in
            listener?.offerwall(didFailToShow: error, adSpace: adSpace)
        }
    }

    func dispatchDidClose(providerKey: String) {
        let listener = currentUXListener()
        Task { @MainActor in
            listener?.offerwall(didClose: providerKey)
        }
    }

    func dispatchReward(amount: Int, currency: String, providerKey: String) {
        let listener = currentUXListener()
        Task { @MainActor in
            listener?.offerwall(didEarnRewardAmount: amount, currency: currency, providerKey: providerKey)
        }
    }

    func dispatchDidInitialize() {
        let listener = currentUXListener()
        Task { @MainActor in
            listener?.offerwallDidInitialize()
        }
    }

    func dispatchDidFailToInitialize(_ reason: String) {
        let listener = currentUXListener()
        Task { @MainActor in
            listener?.offerwall(didFailToInitialize: reason)
        }
    }

    // MARK: - Tracking dispatch

    func dispatchTrackingEvent(_ name: String, payload: [String: JSONValue]) {
        let listener = currentTrackingListener()
        Task { @MainActor in
            listener?.offerwallTracking(didDispatchEvent: name, payload: payload)
        }
    }

    // MARK: - Helpers

    private func currentUXListener() -> OfferwallListener? {
        lock.lock(); defer { lock.unlock() }
        return uxListener
    }

    private func currentTrackingListener() -> OfferwallTrackingListener? {
        lock.lock(); defer { lock.unlock() }
        return trackingListener
    }
}
