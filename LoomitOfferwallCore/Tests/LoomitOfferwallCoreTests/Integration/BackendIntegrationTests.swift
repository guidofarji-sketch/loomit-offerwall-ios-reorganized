//
//  BackendIntegrationTests.swift
//  LoomitOfferwallCoreTests
//
//  Tests de integración contra el backend REAL de Loomit.
//
//  Diseño:
//  - Skipped por default — solo corren si la env var `LOOMIT_API_KEY` está
//    presente. Esto evita que CI / tests locales rompan por estar offline o
//    sin credenciales.
//  - Soporta `LOOMIT_ENV=test` para apuntar a Supabase TEST en vez de LIVE.
//  - Imprime resumen del response para ayudar al desarrollador a verificar
//    que la cadena identifiers → request → response funciona.
//
//  Cómo correr:
//
//      LOOMIT_API_KEY="..." \
//      LOOMIT_ENV=test \
//      xcodebuild test \
//          -scheme LoomitOfferwallCore \
//          -destination 'platform=iOS Simulator,name=iPhone 17' \
//          -only-testing:LoomitOfferwallCoreTests/BackendIntegrationTests
//

import XCTest
import LoomitOfferwallAdapterAPI
@testable import LoomitOfferwallCore

final class BackendIntegrationTests: XCTestCase {

    private var apiKey: String?
    private var clientId: String?
    private var appId: String?
    private var environment: BackendEnvironment = .live

    override func setUp() {
        super.setUp()

        let env = ProcessInfo.processInfo.environment

        // Variables de entorno (requeridas para integration tests)
        if let key = env["LOOMIT_API_KEY"], !key.isEmpty {
            apiKey = key
        }
        if let cid = env["LOOMIT_CLIENT_ID"], !cid.isEmpty {
            clientId = cid
        }
        if let aid = env["LOOMIT_APP_ID"], !aid.isEmpty {
            appId = aid
        }
        if env["LOOMIT_ENV"]?.lowercased() == "test" {
            environment = .test
        }
    }

    /// Test E2E: setea API key, client ID, app ID, pide config, valida que llega un response
    /// estructuralmente válido. **No** valida contenido específico (depende
    /// de la config del publisher en el backend).
    func test_fetchConfig_realBackend_E2E() async throws {
        try requireApiKey()
        try requireClientId()

        let sdk = OfferwallSdk(
            __forTestingIdentifiers: IdentifierStore(suiteForTesting: "loomit.integration.tests"),
            backendClient: nil,        // que use HTTP real
            retryPolicy: RetryPolicy(maxAttempts: 2, initialDelay: 1, maxDelay: 3, multiplier: 2, jitter: 0.2)
        )
        await sdk.setLoomitApiKey(apiKey!)
        await sdk.setClientId(clientId!)
        if let appId = appId {
            await sdk.setAppId(appId)
        }
        await sdk.setEnvironment(environment)

        let xifa = await sdk.xifa()
        let fp   = await sdk.deviceFingerprint()
        print("\n[Integration] xifa:        \(xifa)")
        print("[Integration] fingerprint: \(fp)")
        print("[Integration] env:         \(environment)")
        print("[Integration] endpoint:    \(BackendEndpoints(environment: environment).getAppConfig.absoluteString)")

        let response = try await sdk.fetchConfig()

        // ---- Assertions estructurales ----
        // El response puede tener cualquier shape válido; sólo aseguramos
        // que decodificó OK y que el SDK pasó a `.ready`.
        let state = await sdk.state
        XCTAssertEqual(state, .ready, "SDK should be .ready after successful fetch")

        // ---- Resumen para inspección humana ----
        print("\n[Integration] ---- ConfigResponse summary ----")
        print("[Integration] segment:           \(response.segment ?? "<nil>")")
        print("[Integration] debuggingStatus:   \(response.debuggingStatus.map(String.init) ?? "<nil>")")
        print("[Integration] configurations:    \(response.configurations.count)")

        if let waterfall = response.offerwall?.defaultWaterfall {
            print("[Integration] default_waterfall: \(waterfall.count) provider(s)")
            for (idx, entry) in waterfall.enumerated() {
                print("[Integration]   [\(idx)] \(entry.providerId) prio=\(entry.priority) active=\(entry.isActive) creds_keys=\(Array(entry.credentials.keys).sorted())")
            }
        } else {
            print("[Integration] offerwall: <nil>")
        }

        if let overrides = response.offerwall?.adSpaceOverrides, !overrides.isEmpty {
            print("[Integration] ad_space_overrides: \(overrides.keys.sorted())")
        }

        if let logging = response.loggingConfig {
            print("[Integration] logging: enabled=\(logging.enabled) categories=\(logging.categories.keys.sorted())")
        }

        print("[Integration] ---- end summary ----\n")
    }

    /// Test E2E: una API key inválida debe devolver 401 (no retryable).
    func test_fetchConfig_invalidApiKey_returns4xx() async throws {
        // Solo si tenemos backend real disponible; si LOOMIT_API_KEY no está,
        // skip (no necesitamos una válida para este test, pero queremos que
        // se corra solo cuando estamos validando integration explícitamente).
        try requireApiKey()

        let sdk = OfferwallSdk(
            __forTestingIdentifiers: IdentifierStore(suiteForTesting: "loomit.integration.tests"),
            backendClient: nil,
            retryPolicy: .none
        )
        await sdk.setLoomitApiKey("definitely-not-a-real-key")
        await sdk.setEnvironment(environment)

        do {
            _ = try await sdk.fetchConfig()
            XCTFail("expected throw with invalid API key")
        } catch let error as OfferwallError {
            print("\n[Integration] invalid-key test got error: \(error)")
            // Aceptamos cualquier 4xx o decoding error (el backend puede
            // responder 401, 403, o 200 con un payload de error).
            switch error {
            case .backendHTTPError(let status, _) where (400..<500).contains(status):
                break  // OK
            case .backendDecodingError:
                break  // OK — backend devuelve 200 + error JSON shape
            default:
                XCTFail("unexpected error variant: \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func requireApiKey() throws {
        guard apiKey != nil else {
            throw XCTSkip("Set LOOMIT_API_KEY env var to run integration tests")
        }
    }

    private func requireClientId() throws {
        guard clientId != nil else {
            throw XCTSkip("Set LOOMIT_CLIENT_ID env var to run integration tests")
        }
    }
}

// MARK: - IdentifierStore test convenience

extension IdentifierStore {
    /// Init para tests de integración: usa un suite UD aislado para no
    /// contaminar standard defaults.
    convenience init(suiteForTesting suite: String) {
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        self.init(defaults: defaults)
    }
}
