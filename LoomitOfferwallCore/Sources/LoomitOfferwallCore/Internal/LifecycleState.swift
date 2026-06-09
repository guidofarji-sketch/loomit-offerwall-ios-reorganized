//
//  LifecycleState.swift
//  LoomitOfferwallCore
//
//  Máquina de estados del SDK. Centraliza las transiciones válidas y permite
//  validar invariantes (no se puede `show` sin `ready`, no se puede inicializar
//  dos veces, etc.).
//

import Foundation

/// Estado de alto nivel del SDK.
///
/// Transiciones válidas:
/// ```
///   .uninitialized
///       └─ setLoomitApiKey() ──> .configured
///                                    │
///                                    ├─ fetchConfig() (loading) ──> .ready
///                                    │                              ─┐
///                                    │                               ├─ show() ──> .showing
///                                    │                               │            └─ close() ──> .ready
///                                    │                               ├─ fetchConfig() (refresh) ──> .ready
///                                    │
///                                    └─ shutdown() ──> .uninitialized
/// ```
public enum LifecycleState: Sendable, Equatable {

    /// Estado inicial. No hay API key, no hay config.
    case uninitialized

    /// API key seteada. No hay config aún (o falló el fetch).
    case configured

    /// Config fetched y waterfall listo para inicializar/mostrar.
    case ready

    /// Offerwall actualmente mostrándose.
    case showing(providerKey: String, adSpace: String?)
}

extension LifecycleState {

    /// Etiqueta corta para logs / debug. No es localized.
    public var label: String {
        switch self {
        case .uninitialized:        return "uninitialized"
        case .configured:           return "configured"
        case .ready:                return "ready"
        case .showing:              return "showing"
        }
    }
}
