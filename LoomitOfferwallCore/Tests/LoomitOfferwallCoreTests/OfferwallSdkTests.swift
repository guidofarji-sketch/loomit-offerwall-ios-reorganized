//
//  OfferwallSdkTests.swift
//  LoomitOfferwallCoreTests
//
//  Tests del entry point principal. Usamos el init `__forTestingIdentifiers`
//  (internal, accesible via @testable import) para inyectar dependencias.
//

import XCTest
import LoomitOfferwallAdapterAPI
@testable import LoomitOfferwallCore

final class OfferwallSdkTests: XCTestCase {

    // MARK: - State machine

    func test_initialState_isUninitialized() async {
        let sdk = makeSdk()
        let state = await sdk.state
        XCTAssertEqual(state, .uninitialized)
    }

    func test_setLoomitApiKey_promotesToConfigured() async {
        let sdk = makeSdk()
        await sdk.setLoomitApiKey("TEST-KEY")
        let state = await sdk.state
        XCTAssertEqual(state, .configured)
    }

    // MARK: - userId cascade (invariante §2.3)

    func test_resolvedUserId_fallsBackToXifa() async {
        let store = MockIdentifierStore()
        store.stubbedXifa = "xifa-only"
        let sdk = makeSdk(identifiers: store)

        await sdk.setLoomitApiKey("K")
        let id = await sdk.resolvedUserId()
        XCTAssertEqual(id, "xifa-only")
    }

    func test_resolvedUserId_publisherUserId_overridesXifa() async {
        let store = MockIdentifierStore()
        store.stubbedXifa = "xifa-only"
        let sdk = makeSdk(identifiers: store)

        await sdk.setLoomitApiKey("K")
        await sdk.setPublisherUserId("publisher-42")
        let id = await sdk.resolvedUserId()
        XCTAssertEqual(id, "publisher-42")
    }

    func test_resolvedUserId_currentUserId_hasHighestPriority() async {
        let store = MockIdentifierStore()
        store.stubbedXifa = "xifa-only"
        let sdk = makeSdk(identifiers: store)

        await sdk.setLoomitApiKey("K")
        await sdk.setPublisherUserId("publisher-42")
        await sdk.setCurrentUserId("session-user-99")
        let id = await sdk.resolvedUserId()
        XCTAssertEqual(id, "session-user-99")
    }

    func test_resolvedUserId_emptyStringsAreSkipped() async {
        let store = MockIdentifierStore()
        store.stubbedXifa = "xifa-only"
        let sdk = makeSdk(identifiers: store)

        await sdk.setLoomitApiKey("K")
        await sdk.setCurrentUserId("")  // empty no override
        let id = await sdk.resolvedUserId()
        XCTAssertEqual(id, "xifa-only")
    }

    // MARK: - Identifiers exposure

    func test_xifa_andFingerprint_passThroughToStore() async {
        let store = MockIdentifierStore()
        store.stubbedXifa = "xifa-1"
        store.stubbedFingerprint = "fp-1"
        let sdk = makeSdk(identifiers: store)

        let xifa = await sdk.xifa()
        let fp   = await sdk.deviceFingerprint()
        XCTAssertEqual(xifa, "xifa-1")
        XCTAssertEqual(fp, "fp-1")
    }

    // MARK: - fetchConfig

    func test_fetchConfig_throws_whenApiKeyNotSet() async {
        let sdk = makeSdk()
        do {
            _ = try await sdk.fetchConfig()
            XCTFail("expected throw")
        } catch let error as OfferwallError {
            XCTAssertEqual(error.diagnosticCode, "not_initialized")
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func test_fetchConfig_throws_whenApiKeyEmpty() async {
        let sdk = makeSdk()
        await sdk.setLoomitApiKey("")
        do {
            _ = try await sdk.fetchConfig()
            XCTFail("expected throw")
        } catch let error as OfferwallError {
            XCTAssertEqual(error.diagnosticCode, "missing_api_key")
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func test_fetchConfig_success_promotesToReady_andStoresConfig() async throws {
        let mock = MockBackendClient()
        mock.enqueueSuccess(ConfigResponse(segment: "premium"))
        let sdk = makeSdk(backendClient: mock)

        await sdk.setLoomitApiKey("K")
        let response = try await sdk.fetchConfig()

        XCTAssertEqual(response.segment, "premium")

        let state = await sdk.state
        let last = await sdk.lastConfig
        XCTAssertEqual(state, .ready)
        XCTAssertEqual(last?.segment, "premium")
    }

    func test_fetchConfig_buildsRequestWithXifaAndFingerprint() async throws {
        let store = MockIdentifierStore()
        store.stubbedXifa = "xifa-test"
        store.stubbedBundleId = "com.publisher.app"

        let mock = MockBackendClient()
        mock.enqueueSuccess()

        let sdk = makeSdk(identifiers: store, backendClient: mock)

        await sdk.setLoomitApiKey("KEY-42")
        await sdk.setClientId("CLIENT-99")
        await sdk.setPublisherUserId("user-123")
        await sdk.setAppId("APP-XYZ")
        await sdk.setCustomProperties(["tier": "gold"])
        await sdk.setPrivacy(tcfConsentString: "TCF-CO", subjectToGdpr: true, gdprConsent: true)

        _ = try await sdk.fetchConfig()

        let req = try XCTUnwrap(mock.receivedRequests.first)
        XCTAssertEqual(req.clientId, "CLIENT-99")
        XCTAssertEqual(req.xifa, "xifa-test")
        XCTAssertEqual(req.packageName, "com.publisher.app")
        XCTAssertEqual(req.publisherUserId, "user-123")
        XCTAssertEqual(req.appId, "APP-XYZ")
        XCTAssertEqual(req.customProperties?["tier"], "gold")
        XCTAssertEqual(req.tcfConsentString, "TCF-CO")
        XCTAssertEqual(req.subjectToGdpr, true)
        XCTAssertEqual(req.gdprConsent, true)
        XCTAssertEqual(req.platform, "ios")
        XCTAssertEqual(req.sdkVersion, SdkVersion.current)
    }

    // MARK: - Adapter registry

    func test_registerAdapter_isReachableThroughSdk() async {
        let sdk = makeSdk()
        await sdk.setLoomitApiKey("K")

        let stub = StubAdapter(supportedKeys: ["mychips", "MAF"])
        await sdk.registerAdapter(stub)

        let keys = await sdk.registeredAdapterKeys()
        XCTAssertEqual(keys, ["maf", "mychips"])
    }

    // MARK: - Helpers

    private func makeSdk(
        identifiers: IdentifierStoring = MockIdentifierStore(),
        backendClient: BackendClient? = nil
    ) -> OfferwallSdk {
        OfferwallSdk(
            __forTestingIdentifiers: identifiers,
            registry: AdapterRegistry(),
            backendClient: backendClient,
            retryPolicy: .none
        )
    }
}

// MARK: - StubAdapter

private struct StubAdapter: OfferwallAdapter {
    let providerName = "Stub"
    let supportedKeys: [String]

    @MainActor
    func createProvider() -> OfferwallProvider { fatalError("not used in this test") }
}
