//
//  BackendEnvironment.swift
//  LoomitOfferwallCore
//
//  Entornos de backend Loomit. Paridad con Android `SupabaseEnvironment`.
//

import Foundation

/// Environment del backend Loomit.
///
/// `live` y `test` apuntan a los hosts Supabase de Loomit. `custom` permite
/// override para dev local o staging custom.
public enum BackendEnvironment: Sendable, Equatable {

    /// Producción.
    case live

    /// Test / staging compartido.
    case test

    /// Override custom (ej: dev local con tunnel, staging propio).
    case custom(baseURL: URL)

    public var baseURL: URL {
        switch self {
        case .live:
            // swiftlint:disable:next force_unwrapping
            return URL(string: "https://gqxplbooemsqtrwbllya.supabase.co/functions/v1")!
        case .test:
            // swiftlint:disable:next force_unwrapping
            return URL(string: "https://ephrjxiqtbikewfjeabv.supabase.co/functions/v1")!
        case .custom(let url):
            return url
        }
    }
}

// MARK: - CustomStringConvertible

extension BackendEnvironment: CustomStringConvertible {
    public var description: String {
        switch self {
        case .live:
            return "live"
        case .test:
            return "test"
        case .custom(let url):
            return url.absoluteString
        }
    }
}

// MARK: - Endpoints

/// Endpoints conocidos del backend Loomit. Siempre relativos a `environment.baseURL`.
struct BackendEndpoints: Sendable {

    let environment: BackendEnvironment

    init(environment: BackendEnvironment) {
        self.environment = environment
    }

    /// `POST /get-app-config` — fetch config del publisher/usuario.
    var getAppConfig: URL {
        environment.baseURL.appendingPathComponent("get-app-config")
    }

    /// `POST /track-event` — push de eventos.
    var trackEvent: URL {
        environment.baseURL.appendingPathComponent("track-event")
    }

    /// `POST /track-antifraud-event` — eventos antifraud.
    var trackAntifraudEvent: URL {
        environment.baseURL.appendingPathComponent("track-antifraud-event")
    }

    /// `POST /upload-logs` — batch upload de logs (logger).
    var uploadLogs: URL {
        environment.baseURL.appendingPathComponent("upload-logs")
    }
}
