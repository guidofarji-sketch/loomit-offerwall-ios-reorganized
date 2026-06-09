//
//  MockBackendClient.swift
//  LoomitOfferwallCoreTests
//
//  Mock thread-safe de BackendClient para tests.
//

import Foundation
import LoomitOfferwallAdapterAPI
@testable import LoomitOfferwallCore

/// Mock backend client. Permite scriptear respuestas y contar llamadas.
final class MockBackendClient: BackendClient, @unchecked Sendable {

    private let lock = NSLock()
    private var responses: [Result<ConfigResponse, Error>] = []
    private(set) var receivedRequests: [ConfigRequest] = []

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return receivedRequests.count
    }

    func enqueue(_ result: Result<ConfigResponse, Error>) {
        lock.lock()
        responses.append(result)
        lock.unlock()
    }

    func enqueueSuccess(_ response: ConfigResponse = ConfigResponse()) {
        enqueue(.success(response))
    }

    func enqueueError(_ error: Error) {
        enqueue(.failure(error))
    }

    func fetchConfig(_ request: ConfigRequest) async throws -> ConfigResponse {
        lock.lock()
        receivedRequests.append(request)
        let next = responses.isEmpty ? nil : responses.removeFirst()
        lock.unlock()

        guard let result = next else {
            throw OfferwallError.unknown(underlying: "MockBackendClient: no enqueued response")
        }

        switch result {
        case .success(let r):  return r
        case .failure(let e):  throw e
        }
    }
}
