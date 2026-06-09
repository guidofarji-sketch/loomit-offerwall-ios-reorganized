//
//  HTTPEventPusher.swift
//  LoomitOfferwallCore
//
//  Pusher concreto que postea a `/track-event` del backend Loomit (Supabase).
//  Paridad funcional con Android `SupabaseEventPusher`.
//

import Foundation
import LoomitOfferwallAdapterAPI

public final class HTTPEventPusher: OfferwallEventPusher {

    private let endpoint: URL
    private let apiKey: String
    private let session: URLSession
    private let timeout: TimeInterval
    private let encoder: JSONEncoder

    public init(
        environment: BackendEnvironment,
        apiKey: String,
        session: URLSession = .shared,
        timeout: TimeInterval = 10
    ) {
        self.endpoint = BackendEndpoints(environment: environment).trackEvent
        self.apiKey = apiKey
        self.session = session
        self.timeout = timeout
        self.encoder = JSONEncoder()
    }

    public func push(_ event: OfferwallEvent) async throws {
        let body = try encoder.encode(buildWirePayload(from: event))

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.httpBody = body

        let (data, response) = try await session.data(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw OfferwallError.backendUnreachable(underlying: "non-HTTP response")
        }

        if !(200..<300).contains(http.statusCode) {
            let bodyStr = String(data: data, encoding: .utf8)
            throw OfferwallError.backendHTTPError(statusCode: http.statusCode, body: bodyStr)
        }
    }

    // MARK: - Wire payload

    /// Estructura wire que se envía al backend. Mantenemos la forma exacta del
    /// payload Android (`SupabaseEventPusher.buildRequestBody`).
    private struct WirePayload: Codable {
        let eventName: String
        let userId: String?
        let appId: String?
        let platform: String
        let lifecycleId: Int?
        let eventProperties: [String: JSONValue]
        let country: String?
        let appVersion: String?
        let sdkVersion: String?
        let deviceModel: String
        let osVersion: String
        let sessionId: String?
        let provider: String?
        let xifa: String?
        let timestampMs: Int64

        enum CodingKeys: String, CodingKey {
            case eventName        = "event_name"
            case userId           = "user_id"
            case appId            = "app_id"
            case platform
            case lifecycleId      = "lifecycle_id"
            case eventProperties  = "event_properties"
            case country
            case appVersion       = "app_version"
            case sdkVersion       = "sdk_version"
            case deviceModel      = "device_model"
            case osVersion        = "os_version"
            case sessionId        = "session_id"
            case provider
            case xifa
            case timestampMs      = "timestamp_ms"
        }
    }

    private func buildWirePayload(from event: OfferwallEvent) -> WirePayload {
        // userId resolution: si el publisher mandó user_id en data, usarlo;
        // sino caer al xifa.
        let userId: String? = {
            if case let .string(s) = event.data["user_id"] { return s }
            return event.xifa
        }()

        // event_properties: preservamos el `data` y aseguramos provider/xifa/lifecycle.
        var properties = event.data
        if properties["provider"] == nil {
            properties["provider"] = .string(event.provider)
        }
        if let xifa = event.xifa, properties["xifa"] == nil {
            properties["xifa"] = .string(xifa)
        }
        if let lid = event.lifecycleId, properties["lifecycle_id"] == nil {
            properties["lifecycle_id"] = .int(Int64(lid))
        }

        let sessionId: String? = {
            if case let .string(s) = event.data["session_id"] { return s }
            return nil
        }()

        return WirePayload(
            eventName: event.type,
            userId: userId,
            appId: event.appId,
            platform: event.platform,
            lifecycleId: event.lifecycleId,
            eventProperties: properties,
            country: event.country,
            appVersion: event.appVersion,
            sdkVersion: event.sdkVersion,
            deviceModel: event.deviceModel,
            osVersion: event.osVersion,
            sessionId: sessionId,
            provider: event.provider,
            xifa: event.xifa,
            timestampMs: event.timestampMs
        )
    }
}
