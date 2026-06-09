//
//  HTTPBackendClientTests.swift
//  LoomitOfferwallCoreTests
//
//  Tests del HTTP backend client usando URLProtocol mock — no hacen tráfico real.
//

import XCTest
import LoomitOfferwallAdapterAPI
@testable import LoomitOfferwallCore

final class HTTPBackendClientTests: XCTestCase {

    override func tearDown() {
        URLProtocolMock.reset()
        super.tearDown()
    }

    // MARK: - Success path

    func test_fetchConfig_sendsCorrectRequest() async throws {
        URLProtocolMock.responder = { request in
            (200, Data("{}".utf8), ["Content-Type": "application/json"])
        }

        let client = HTTPBackendClient(
            environment: .live,
            apiKey: "TEST-KEY-123",
            session: URLProtocolMock.makeSession()
        )

        _ = try await client.fetchConfig(ConfigRequest(clientId: "X", xifa: "Y"))

        let captured = try XCTUnwrap(URLProtocolMock.lastRequest)
        XCTAssertEqual(captured.httpMethod, "POST")
        XCTAssertEqual(
            captured.url?.absoluteString,
            "https://gqxplbooemsqtrwbllya.supabase.co/functions/v1/get-app-config"
        )
        XCTAssertEqual(captured.value(forHTTPHeaderField: "x-api-key"), "TEST-KEY-123")
        XCTAssertEqual(captured.value(forHTTPHeaderField: "Content-Type"), "application/json")

        // Body debe contener client_id y xifa (snake_case por contrato wire)
        let body = try XCTUnwrap(URLProtocolMock.lastBody)
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("\"client_id\":\"X\""), bodyString)
        XCTAssertTrue(bodyString.contains("\"xifa\":\"Y\""), bodyString)
    }

    func test_fetchConfig_decodesResponse() async throws {
        let payload = """
        {
            "segment": "premium",
            "offerwall": {
                "default_waterfall": [
                    {"provider_id": "tapjoy", "provider_priority": 1, "credentials": {"sdk_key": "abc"}}
                ]
            }
        }
        """
        URLProtocolMock.responder = { _ in (200, Data(payload.utf8), [:]) }

        let client = HTTPBackendClient(
            environment: .test,
            apiKey: "K",
            session: URLProtocolMock.makeSession()
        )

        let response = try await client.fetchConfig(ConfigRequest(clientId: "X", xifa: "Y"))
        XCTAssertEqual(response.segment, "premium")
        XCTAssertEqual(response.offerwall?.defaultWaterfall.first?.providerId, "tapjoy")
    }

    // MARK: - Error paths

    func test_fetchConfig_throwsHTTPError_on500() async {
        URLProtocolMock.responder = { _ in (500, Data("internal error".utf8), [:]) }

        let client = HTTPBackendClient(
            environment: .live,
            apiKey: "K",
            session: URLProtocolMock.makeSession()
        )

        do {
            _ = try await client.fetchConfig(ConfigRequest(clientId: "X", xifa: "Y"))
            XCTFail("expected throw")
        } catch let error as OfferwallError {
            guard case .backendHTTPError(let code, let body) = error else {
                XCTFail("wrong error variant: \(error)"); return
            }
            XCTAssertEqual(code, 500)
            XCTAssertEqual(body, "internal error")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_fetchConfig_throwsDecodingError_onBadJson() async {
        URLProtocolMock.responder = { _ in (200, Data("not json".utf8), [:]) }

        let client = HTTPBackendClient(
            environment: .live,
            apiKey: "K",
            session: URLProtocolMock.makeSession()
        )

        do {
            _ = try await client.fetchConfig(ConfigRequest(clientId: "X", xifa: "Y"))
            XCTFail("expected throw")
        } catch let error as OfferwallError {
            XCTAssertEqual(error.diagnosticCode, "backend_decoding_error")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_fetchConfig_endpointForCustomEnvironment() async throws {
        URLProtocolMock.responder = { _ in (200, Data("{}".utf8), [:]) }
        let custom = URL(string: "https://staging.loomit.example/v1")!

        let client = HTTPBackendClient(
            environment: .custom(baseURL: custom),
            apiKey: "K",
            session: URLProtocolMock.makeSession()
        )

        _ = try await client.fetchConfig(ConfigRequest(clientId: "X", xifa: "Y"))
        let captured = try XCTUnwrap(URLProtocolMock.lastRequest)
        XCTAssertEqual(
            captured.url?.absoluteString,
            "https://staging.loomit.example/v1/get-app-config"
        )
    }
}

// MARK: - URLProtocolMock

/// URLProtocol mock global que captura requests y responde según `responder`.
final class URLProtocolMock: URLProtocol {

    nonisolated(unsafe) static var responder: ((URLRequest) -> (Int, Data, [String: String]))?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    static func reset() {
        responder = nil
        lastRequest = nil
        lastBody = nil
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        URLProtocolMock.lastRequest = request
        // URLProtocol no expone httpBody directamente para POSTs construidos
        // con httpBody; sí expone httpBodyStream. Capturamos via stream o el
        // body del mismo request.
        if let body = request.httpBody {
            URLProtocolMock.lastBody = body
        } else if let stream = request.httpBodyStream {
            URLProtocolMock.lastBody = Data(reading: stream)
        }

        guard let responder = URLProtocolMock.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }

        let (status, data, headers) = responder(request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://stub.local")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension Data {
    init(reading stream: InputStream) {
        var data = Data()
        stream.open()
        defer { stream.close() }
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        self = data
    }
}
