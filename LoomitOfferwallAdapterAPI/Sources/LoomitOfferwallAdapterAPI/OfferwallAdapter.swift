//
//  OfferwallAdapter.swift
//  LoomitOfferwallAdapterAPI
//
//  Factory descriptor de un provider. Los adapters son descubiertos por core
//  via registro explícito (`OfferwallSdk.registerAdapter(...)`).
//
//  Decisión arquitectónica (vs Android/ServiceLoader):
//  - En Android usamos `ServiceLoader` + META-INF/services para discovery
//    automático. En iOS no existe equivalente built-in confiable que funcione
//    con frameworks compilados (XCFrameworks no exponen recursos a un loader
//    central). Optamos por **registro explícito** desde el publisher en su
//    AppDelegate / SceneDelegate. Es más simple, más auditable, y evita el
//    pitfall §10.4 (modulos opcionales no presentes).
//  - El sample-app demuestra el patrón: `OfferwallSdk.shared.registerAdapter(MyChipsAdapter())`.
//

import Foundation

/// Factory + descriptor de un provider concreto.
///
/// Cada módulo `LoomitOfferwallAdapter*` expone exactamente un tipo que
/// conforma `OfferwallAdapter`. El publisher lo registra en `OfferwallSdk`
/// durante el bootstrap de la app (típicamente `AppDelegate.didFinishLaunching`).
public protocol OfferwallAdapter: Sendable {

    /// Nombre legible del provider (ej: "Tapjoy", "MyChips", "Digital Turbine").
    /// Usado en UI de debug y logs.
    var providerName: String { get }

    /// Lista de keys que este adapter sabe manejar. Matching es case-insensitive.
    ///
    /// Ejemplos:
    /// - Tapjoy: `["tapjoy"]`
    /// - MyChips/MAF: `["mychips", "maf"]` (alias por compatibilidad backend)
    var supportedKeys: [String] { get }

    /// Crea una nueva instancia del provider. Llamado una vez por core
    /// durante `initAllFromPlan`.
    ///
    /// **Importante**: `createProvider()` debe ser barato y no hacer trabajo
    /// pesado. La inicialización real va en `OfferwallProvider.initialize(...)`.
    @MainActor
    func createProvider() -> OfferwallProvider
}

extension OfferwallAdapter {

    /// Helper: ¿este adapter sabe manejar `key`? Case-insensitive.
    public func supports(key: String) -> Bool {
        let normalized = key.lowercased()
        return supportedKeys.contains { $0.lowercased() == normalized }
    }
}
