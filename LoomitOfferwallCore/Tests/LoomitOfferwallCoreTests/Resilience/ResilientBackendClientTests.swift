//
//  ResilientBackendClientTests.swift
//  LoomitOfferwallCoreTests
//

import XCTest
import LoomitOfferwallAdapterAPI
@testable import LoomitOfferwallCore

final class ResilientBackendClientTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "loomit.tests.resilient"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeRequest() -> ConfigRequest {
        ConfigRequest(
            clientId: "cid",
            appId: "aid",
            packageName: "com.test",
            publisherUserId: nil,
            xifa: "xifa-1",
            tcfConsentString: nil,
            usPrivacyString: nil,
            subjectToGdpr: nil,
            gdprConsent: nil,
            ccpaOptOut: nil,
            country: nil,
            platform: "ios",
            sdkVersion: "0.1",
            appVersion: nil,
            hasAdvertisingId: false,
            aaid: nil,
            customProperties: nil,
            abTestOverride: nil
        )
    }

    private func makeCache(clock: TestClock) -> UserDefaultsConfigCache {
        UserDefaultsConfigCache(
            defaults: defaults,
            namespace: "ns",
            clock: { clock.now }
        )
    }

    func test_success_savesToCache_andReportsNetworkSource() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_000))
        let mock = MockBackendClient()
        mock.enqueueSuccess(ConfigResponse(segment: "fresh"))

        let cache = makeCache(clock: clock)
        let breaker = CircuitBreaker(name: "t", config: .default, clock: { clock.now })
        let resilient = ResilientBackendClient(
            wrapping: mock,
            cache: cache,
            breaker: breaker,
            clock: { clock.now }
        )

        let result = await resilient.fetchConfigDetailed(makeRequest())
        guard case .success(let cfg, let source) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(cfg.segment, "fresh")
        XCTAssertEqual(source, .network)
        XCTAssertNotNil(cache.load(), "cache must be populated")
    }

    func test_networkFailure_fallbackToCacheFresh() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_000))
        let cache = makeCache(clock: clock)

        // Pre-poblar cache con algo
        let snap = ConfigSnapshot(
            config: ConfigResponse(segment: "cached"),
            timestamp: clock.now,
            source: .network,
            checksum: ""
        )
        XCTAssertTrue(cache.save(snap))

        let mock = MockBackendClient()
        mock.enqueueError(OfferwallError.backendUnreachable(underlying: "no net"))

        let breaker = CircuitBreaker(name: "t", config: .default, clock: { clock.now })
        let resilient = ResilientBackendClient(
            wrapping: mock,
            cache: cache,
            breaker: breaker,
            clock: { clock.now }
        )

        // Avanzar 1h: cache aún fresh
        clock.advance(3600)

        let result = await resilient.fetchConfigDetailed(makeRequest())
        guard case .success(let cfg, let source) = result else {
            return XCTFail("expected fallback success, got \(result)")
        }
        XCTAssertEqual(cfg.segment, "cached")
        XCTAssertEqual(source, .cacheFresh)
    }

    func test_networkFailure_fallbackToCacheStale_whenAllowed() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_000))
        let cache = makeCache(clock: clock)
        let snap = ConfigSnapshot(
            config: ConfigResponse(segment: "stale"),
            timestamp: clock.now,
            source: .network,
            checksum: ""
        )
        _ = cache.save(snap)

        // Avanzar 2 días → ya no es fresh, pero stale (< 7d) sí
        clock.advance(2 * 24 * 3600)

        let mock = MockBackendClient()
        mock.enqueueError(OfferwallError.backendUnreachable(underlying: "down"))

        let resilient = ResilientBackendClient(
            wrapping: mock,
            cache: cache,
            breaker: CircuitBreaker(name: "t", clock: { clock.now }),
            policy: .default,
            clock: { clock.now }
        )

        let result = await resilient.fetchConfigDetailed(makeRequest())
        guard case .success(let cfg, let source) = result else {
            return XCTFail("expected stale fallback, got \(result)")
        }
        XCTAssertEqual(cfg.segment, "stale")
        XCTAssertEqual(source, .cacheStale)
    }

    func test_networkFailure_noCache_returnsFailure() async {
        let clock = TestClock()
        let cache = makeCache(clock: clock)
        let mock = MockBackendClient()
        mock.enqueueError(OfferwallError.backendUnreachable(underlying: "x"))

        let resilient = ResilientBackendClient(
            wrapping: mock,
            cache: cache,
            breaker: CircuitBreaker(name: "t", clock: { clock.now }),
            clock: { clock.now }
        )

        let result = await resilient.fetchConfigDetailed(makeRequest())
        guard case .failure = result else {
            return XCTFail("expected failure, got \(result)")
        }
    }

    func test_circuitOpen_fallsBackToCache() async {
        let clock = TestClock()
        let cache = makeCache(clock: clock)
        // Pre-poblar cache
        _ = cache.save(ConfigSnapshot(
            config: ConfigResponse(segment: "via-cb-cache"),
            timestamp: clock.now,
            source: .network,
            checksum: ""
        ))

        let mock = MockBackendClient()
        // Encolar 2 fallos para abrir el circuito (failureThreshold=2)
        mock.enqueueError(OfferwallError.backendUnreachable(underlying: "x"))
        mock.enqueueError(OfferwallError.backendUnreachable(underlying: "x"))

        let breaker = CircuitBreaker(
            name: "t",
            config: CircuitBreakerConfig(failureThreshold: 2, openDuration: 60),
            clock: { clock.now }
        )
        let resilient = ResilientBackendClient(
            wrapping: mock,
            cache: cache,
            breaker: breaker,
            clock: { clock.now }
        )

        // Primer fallo: fallback a cache (fresh)
        _ = await resilient.fetchConfigDetailed(makeRequest())
        // Segundo fallo: abre el circuito
        _ = await resilient.fetchConfigDetailed(makeRequest())
        let cbState = await breaker.getState()
        XCTAssertEqual(cbState, .open)

        // Tercera invocación: el breaker rechaza → fallback a cache
        let result = await resilient.fetchConfigDetailed(makeRequest())
        guard case .success(_, let source) = result else {
            return XCTFail("expected cache fallback when circuit OPEN, got \(result)")
        }
        XCTAssertEqual(source, .cacheFresh)
        // Y el mock NO recibió un 3er request
        XCTAssertEqual(mock.callCount, 2)
    }
}
