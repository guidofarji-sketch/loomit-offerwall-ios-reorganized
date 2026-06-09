//
//  SdkVersion.swift
//  LoomitOfferwallCore
//
//  Constante única de versión del SDK. Editar acá al releasear.
//

import Foundation

/// Versión semántica del SDK Loomit Offerwall iOS.
///
/// Bumped manualmente. Idealmente leemos del Package.swift en runtime
/// pero SPM no expone eso de forma estable.
public enum SdkVersion {

    /// Versión semántica. Mantener sincronizada con Android cuando hace sentido.
    public static let current: String = "0.3.0-beta"

    /// Plataforma (siempre "ios" para este SDK).
    public static let platform: String = "ios"
}
