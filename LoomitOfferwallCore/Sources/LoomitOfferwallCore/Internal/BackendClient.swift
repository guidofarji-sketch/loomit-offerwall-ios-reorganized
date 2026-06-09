//
//  BackendClient.swift
//  LoomitOfferwallCore
//
//  Protocolo del cliente backend + impl HTTP.
//
//  Diseño:
//  - Protocolo `BackendClient` abstracto para mocking en tests.
//  - `HTTPBackendClient` concreto usa URLSession.
//  - `ResilientBackendClient` (futuro) wrapea para circuit breaker + cache.
//

import Foundation
import LoomitOfferwallAdapterAPI

/// Cliente backend abstracto.
///
/// Acepta inyección para tests (mock impl) y para wrappers (resilient impl).
public protocol BackendClient: Sendable {

    /// `POST /get-app-config`.
    func fetchConfig(_ request: ConfigRequest) async throws -> ConfigResponse
}

// MARK: - HTTPBackendClient

/// Impl de `BackendClient` basada en `URLSession`.
///
/// **No tiene retry ni circuit breaker** — esos los agrega un wrapper externo.
/// Esto mantiene la unidad de responsabilidad clara.
public final class HTTPBackendClient: BackendClient {

    private let endpoints: BackendEndpoints
    private let apiKey: String
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let timeout: TimeInterval

    public init(
        environment: BackendEnvironment,
        apiKey: String,
        session: URLSession = .shared,
        timeout: TimeInterval = 15.0
    ) {
        self.endpoints = BackendEndpoints(environment: environment)
        self.apiKey = apiKey
        self.session = session
        self.timeout = timeout

        let encoder = JSONEncoder()
        // CodingKeys ya están en snake_case en cada modelo, no usamos
        // keyEncodingStrategy global para evitar doble conversión.
        encoder.outputFormatting = []
        self.encoder = encoder

        self.decoder = JSONDecoder()
    }

    public func fetchConfig(_ request: ConfigRequest) async throws -> ConfigResponse {
        let url = endpoints.getAppConfig

        print("[LoomitOW] fetchConfig → POST \(url.absoluteString)")

        var urlRequest = URLRequest(url: url, timeoutInterval: timeout)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("loomit-offerwall-ios/\(SdkVersion.current)", forHTTPHeaderField: "User-Agent")

        do {
            let requestBody = try encoder.encode(request)
            urlRequest.httpBody = requestBody

            // Record request for debug panel (paridad con Android BackendClient.kt línea 736)
            if let requestJson = String(data: requestBody, encoding: .utf8) {
                await OfferwallSdk.shared.recordDebugConfigRequest(json: requestJson)
            }
        } catch {
            throw OfferwallError.invalidConfiguration(reason: "encode ConfigRequest: \(error.localizedDescription)")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError where error.code == .timedOut {
            throw OfferwallError.timeout(operation: "fetchConfig")
        } catch let error as URLError {
            throw OfferwallError.backendUnreachable(underlying: "URLError(\(error.code.rawValue)): \(error.localizedDescription)")
        } catch {
            throw OfferwallError.backendUnreachable(underlying: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OfferwallError.backendUnreachable(underlying: "non-HTTP response")
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw OfferwallError.backendHTTPError(statusCode: http.statusCode, body: body?.truncated(to: 512))
        }

        do {
            return try decoder.decode(ConfigResponse.self, from: data)
        } catch {
            throw OfferwallError.backendDecodingError(underlying: error.localizedDescription)
        }
    }
}

// MARK: - String helper

private extension String {
    func truncated(to max: Int) -> String {
        count <= max ? self : String(prefix(max)) + "…"
    }
}
