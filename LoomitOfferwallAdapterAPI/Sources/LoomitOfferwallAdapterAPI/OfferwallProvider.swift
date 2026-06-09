//
//  OfferwallProvider.swift
//  LoomitOfferwallAdapterAPI
//
//  Protocolo que cada adapter concreto debe implementar para representar
//  un offerwall provider (Tapjoy, MyChips/MAF, DT, Adjoe, Tyrads, etc.).
//
//  Contratos clave (ARCHITECTURE.md §2):
//  - UX callbacks (onShow, onClose, onRewarded) van por listener global.
//    Aquí solo aceptamos `OfferwallProviderListener` para callbacks de
//    inicialización/availability/reward dedup.
//  - `show(from:)` debe presentar el offerwall del provider y retornar
//    cuando comienza la presentación; core ya emitió `content_show`.
//  - El adapter es responsable de devolver disponibilidad real
//    (`isAvailable`), no asumir que init ⇒ available.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Implementación de un provider concreto. Cada adapter expone una.
///
/// Los métodos UI-bound están marcados `@MainActor`. Los métodos puros
/// (de lectura) son `nonisolated` cuando es seguro.
@MainActor
public protocol OfferwallProvider: AnyObject {

    /// Key normalizado del provider (lowercase). Coincide con uno de los
    /// `supportedKeys` del adapter.
    nonisolated var providerKey: String { get }

    /// Versión del SDK del provider integrado. Útil para logging y debug.
    /// Devolver `nil` si no se puede obtener.
    nonisolated var providerSdkVersion: String? { get }

    /// Inicializa el provider con la configuración entregada por core.
    ///
    /// Implementación esperada:
    /// 1. Guardar `config` para uso posterior.
    /// 2. Llamar al SDK del provider con `credentials`/`settings`.
    /// 3. Resolver el async con `.success(())` o `.failure(.providerInitializationFailed(...))`.
    /// 4. Adicionalmente llamar `listener.providerDidInitialize(...)` para core.
    ///
    /// El timeout total de init lo controla core; el adapter no debe colgar
    /// indefinidamente.
    func initialize(
        config: ProviderConfig,
        listener: OfferwallProviderListener
    ) async -> Result<Void, OfferwallError>

    /// Indica si el provider puede mostrar contenido en este momento.
    ///
    /// Implementación esperada: consultar el SDK nativo del provider, no
    /// inferir desde "init exitoso". Algunos providers exponen "content
    /// available" como señal separada.
    func isAvailable() -> Bool

    /// Presenta el offerwall del provider desde el `presenter` dado.
    ///
    /// El callback se resuelve cuando el offerwall fue presentado o falló
    /// la presentación. **No** se debe completar al cerrar; el cierre se
    /// reporta via listener global de core.
    ///
    /// - Parameters:
    ///   - presenter: ViewController desde el que presentar (modal). Core
    ///                garantiza que es válido y está en jerarquía.
    ///   - adSpace: Identificador opcional de placement / ad-space asignado
    ///              en el backend.
    #if canImport(UIKit)
    func show(
        from presenter: UIViewController,
        adSpace: String?
    ) async -> Result<Void, OfferwallError>
    #else
    func show(
        from presenter: Any,
        adSpace: String?
    ) async -> Result<Void, OfferwallError>
    #endif

    /// Cierra el offerwall si está visible. No-op si no lo está.
    func close()
}
