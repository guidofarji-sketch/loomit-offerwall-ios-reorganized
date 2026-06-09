//
//  OfferwallProviderListener.swift
//  LoomitOfferwallAdapterAPI
//
//  Listener LOCAL del provider hacia core.
//
//  IMPORTANTE — Single-path listener contract (ARCHITECTURE.md §2.2):
//  Este listener es **solo para callbacks de inicialización y disponibilidad**
//  que el adapter reporta a core. Los UX callbacks que el publisher consume
//  (onShow, onClose, onRewarded, onShowFailed) **deben** despacharse via el
//  listener global de OfferwallSdk. Adapters NO deben tener listeners locales
//  de UX.
//
//  NOTA: `providerDidClose` y `providerDidShow` aquí son señales INTERNAS
//  del provider a core. Core las convierte en eventos backend + callbacks UX
//  via el listener global. No violan el single-path contract.

import Foundation

/// Listener que core registra en cada provider para recibir señales de
/// inicialización y disponibilidad.
///
/// **Solo para uso interno entre core y adapters.** Los publishers nunca
/// implementan ni reciben este protocolo.
@MainActor
public protocol OfferwallProviderListener: AnyObject {

    /// El provider terminó de inicializar exitosamente.
    func providerDidInitialize(_ providerKey: String)

    /// El provider falló al inicializar.
    func provider(_ providerKey: String, didFailToInitializeWith error: OfferwallError)

    /// La disponibilidad del provider cambió (ej: contenido cargado/agotado).
    /// Core puede usar esto para refrescar `OfferwallListener.onOfferwallAvailabilityChanged`.
    func provider(_ providerKey: String, didChangeAvailability isAvailable: Bool)

    /// El provider reportó una recompensa.
    ///
    /// **Nota**: la mayoría de providers entregan recompensas via S2S callback
    /// al backend del publisher. Este callback existe para los providers que
    /// emiten reward también del lado cliente (ej: Tapjoy `currencyEarned`).
    /// Core hará dedup con S2S si corresponde.
    func provider(_ providerKey: String, didEarnRewardAmount amount: Int, currency: String)

    /// El offerwall fue cerrado por el usuario o por el provider.
    ///
    /// Core emitirá `content_dismiss` y dispatchará `onClose` al listener global.
    func providerDidClose(_ providerKey: String)

    /// El offerwall fue mostrado exitosamente.
    ///
    /// Core emitirá `content_show` y dispatchará `onShow` al listener global.
    /// Este callback es opcional — si el provider no lo llama, core emite
    /// `content_show` cuando `show()` retorna `.success`.
    func providerDidShow(_ providerKey: String)
}

// MARK: - Default implementations (backward compatibility)

extension OfferwallProviderListener {
    public func providerDidClose(_ providerKey: String) {
        // Default: no-op. Adapters existentes pueden no implementar esto.
    }

    public func providerDidShow(_ providerKey: String) {
        // Default: no-op. Core emite content_show cuando show() retorna success.
    }
}
