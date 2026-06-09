//
//  OfferwallListener.swift
//  LoomitOfferwallCore
//
//  Listener GLOBAL único de UX — invariante §2.2 single-path contract.
//
//  Reglas (ARCHITECTURE.md §2.2):
//  - TODOS los UX callbacks (onShow, onClose, onShowFailed, onRewarded,
//    onAvailabilityChanged) van EXCLUSIVAMENTE por este listener global.
//  - Ningún listener local (`OfferwallProviderListener`) puede entregar
//    UX callbacks al publisher.
//  - El dispatch va por `ListenerDispatcher` (centralizado, en main thread).
//
//  Si necesitás múltiples listeners, el publisher implementa un fan-out
//  por su lado. Core mantiene UN solo slot.
//

import Foundation
import LoomitOfferwallAdapterAPI

/// Listener UX que el publisher registra via `OfferwallSdk.setListener(...)`.
///
/// Todos los métodos se invocan en main thread.
@MainActor
public protocol OfferwallListener: AnyObject {

    /// Se invoca al fetchear (o re-fetchear) la config del backend.
    /// - Parameter result: éxito con la config wire o error estructurado.
    func offerwall(didReceiveConfig result: Result<ConfigResponse, OfferwallError>)

    /// La disponibilidad agregada del offerwall cambió. Se calcula como
    /// "al menos un provider del waterfall reporta `isAvailable == true`".
    func offerwall(didChangeAvailability available: Bool)

    /// Se mostró el offerwall.
    /// - Parameter providerKey: el provider que efectivamente lo presentó.
    /// - Parameter adSpace: ad_space activo (si fue setteado por el publisher).
    func offerwall(didShow providerKey: String, adSpace: String?)

    /// Falló mostrar el offerwall (waterfall agotado o error de provider).
    func offerwall(didFailToShow error: OfferwallError, adSpace: String?)

    /// Se cerró el offerwall.
    /// - Parameter providerKey: el provider que estaba mostrándolo.
    func offerwall(didClose providerKey: String)

    /// Se acreditó una recompensa al usuario.
    ///
    /// Las rewards definitivas vienen vía S2S al backend del publisher.
    /// Este callback es para señales del cliente (ej: Tapjoy `currencyEarned`).
    /// Core hace dedup contra S2S antes de invocarlo.
    func offerwall(didEarnRewardAmount amount: Int, currency: String, providerKey: String)

    /// Providers initialized successfully (at least one succeeded).
    func offerwallDidInitialize()

    /// All providers failed to initialize.
    func offerwall(didFailToInitialize reason: String)
}

// MARK: - Default implementations (todos opcionales)

extension OfferwallListener {
    public func offerwall(didReceiveConfig result: Result<ConfigResponse, OfferwallError>) {}
    public func offerwall(didChangeAvailability available: Bool) {}
    public func offerwall(didShow providerKey: String, adSpace: String?) {}
    public func offerwall(didFailToShow error: OfferwallError, adSpace: String?) {}
    public func offerwall(didClose providerKey: String) {}
    public func offerwall(didEarnRewardAmount amount: Int, currency: String, providerKey: String) {}
    public func offerwallDidInitialize() {}
    public func offerwall(didFailToInitialize reason: String) {}
}
